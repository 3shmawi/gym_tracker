import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/features/move/data/datasources/landmark_mapping.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';

/// The front camera and Google ML Kit's on-device pose model (base model,
/// stream mode). Each frame is turned into joints in memory and dropped:
/// no image or joint leaves this class except as a [PoseFrame] to the
/// detector, and nothing is written anywhere (docs/designs/move_games.md
/// §11).
class MlKitPoseSource implements PoseSource {
  new({this.maxFps = 15});

  /// Frames sent to the model per second at most; the rest are dropped.
  final double maxFps;

  final _frames = StreamController<PoseFrame>.broadcast();
  final _status = StreamController<PoseSourceStatus>.broadcast();
  PoseSourceStatus _current = PoseSourceStatus.idle;

  CameraController? _camera;
  PoseDetector? _model;
  bool _busy = false;
  int _failuresInARow = 0;
  final _clock = Stopwatch();
  Duration? _lastSent;
  final Queue<Duration> _finished = Queue();

  /// Starting or stopping; a second call waits for it.
  Future<void>? _change;

  @override
  Stream<PoseFrame> get frames => _frames.stream;

  @override
  Stream<PoseSourceStatus> get status => _status.stream;

  @override
  PoseSourceStatus get currentStatus => _current;

  void _set(PoseSourceStatus s) {
    if (s == _current) return;
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  @override
  Future<void> start() async {
    await _change;
    if (_current.state == PoseSourceState.running) return;
    final change = _start();
    _change = change;
    await change;
  }

  /// On iOS, ML Kit needs its model files copied into the app and two
  /// linker flags (the plugin's README); that set-up is not in the iOS
  /// project yet, and running the model without it can crash. Until it is,
  /// iOS reports the model as unavailable instead of calling it.
  static const iosModelInstalled = false;

  Future<void> _start() async {
    _set(const PoseSourceStatus(PoseSourceState.starting));
    if (Platform.isIOS && !iosModelInstalled) {
      return _fail(PoseProblem.modelFailed);
    }
    try {
      final cameras = await availableCameras();
      final front = cameras
          .where((c) => c.lensDirection == CameraLensDirection.front)
          .firstOrNull;
      if (front == null) return _fail(PoseProblem.noCamera);
      final camera = CameraController(
        front,
        // ≈ 640×480: ML Kit wants at least 480×360; more costs battery.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _camera = camera;
      await camera.initialize();
      // The defaults: the base model (the accurate one is not shipped, §9)
      // in stream mode (tracks one person, lower latency).
      _model = PoseDetector(options: PoseDetectorOptions());
      _failuresInARow = 0;
      _finished.clear();
      _lastSent = null;
      _clock
        ..reset()
        ..start();
      await camera.startImageStream(_onImage);
      _set(const PoseSourceStatus(PoseSourceState.running));
    } on CameraException catch (e) {
      await _release();
      return _fail(_problemOf(e.code));
    } on PlatformException catch (e, st) {
      await _release();
      unawaited(Monitoring.captureException(e, st));
      return _fail(PoseProblem.noCamera);
    } on Object catch (e, st) {
      await _release();
      unawaited(Monitoring.captureException(e, st));
      return _fail(PoseProblem.noCamera);
    }
  }

  static PoseProblem _problemOf(String code) => switch (code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => PoseProblem.denied,
    _ => PoseProblem.noCamera,
  };

  void _fail(PoseProblem problem) =>
      _set(PoseSourceStatus(PoseSourceState.failed, problem: problem));

  void _onImage(CameraImage image) {
    if (_busy || _model == null) return;
    final now = _clock.elapsed;
    final last = _lastSent;
    final minGap = Duration(microseconds: (1e6 / maxFps).round());
    if (last != null && now - last < minGap) return;
    _lastSent = now;
    _busy = true;
    unawaited(_process(image, now));
  }

  Future<void> _process(CameraImage image, Duration at) async {
    try {
      final camera = _camera;
      final model = _model;
      if (camera == null || model == null) return;
      final input = _inputOf(image, camera);
      if (input == null) return;
      final poses = await model.processImage(input.image);
      if (_model == null) return;
      _failuresInARow = 0;
      _frames.add(
        poseFrameFrom(
          poses.firstOrNull?.landmarks,
          at: at,
          width: input.width,
          height: input.height,
        ),
      );
      _measure(at);
    } on Object catch (e, st) {
      _failuresInARow++;
      if (_failuresInARow == 3) {
        unawaited(Monitoring.captureException(e, st));
        _fail(PoseProblem.modelFailed);
        unawaited(stop(keepStatus: true));
      }
    } finally {
      _busy = false;
    }
  }

  /// Frames finished in the last 3 seconds → fps.
  void _measure(Duration at) {
    _finished.addLast(at);
    while (_finished.isNotEmpty &&
        at - _finished.first > const Duration(seconds: 3)) {
      _finished.removeFirst();
    }
    if (_finished.length < 2) return;
    final span = (_finished.last - _finished.first).inMicroseconds / 1e6;
    if (span <= 0) return;
    final fps = ((_finished.length - 1) / span * 10).round() / 10;
    _set(PoseSourceStatus(PoseSourceState.running, fps: fps));
  }

  ({InputImage image, double width, double height})? _inputOf(
    CameraImage image,
    CameraController camera,
  ) {
    // The plugin types the raw format loosely; it is an int on both.
    final raw = image.format.raw;
    if (raw is! int) return null;
    final format = InputImageFormatValue.fromRawValue(raw);
    final expected = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;
    if (format != expected || image.planes.length != 1) return null;
    final plane = image.planes.single;
    final degrees = Platform.isAndroid
        ? androidRotation(
            sensorOrientation: camera.description.sensorOrientation,
            deviceDegrees: _degreesOf(camera.value.deviceOrientation),
            front: true,
          )
        : 0;
    final rotation =
        InputImageRotationValue.fromRawValue(degrees) ??
        InputImageRotation.rotation0deg;
    final size = uprightSize(image.width, image.height, degrees);
    return (
      image: InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format!,
          bytesPerRow: plane.bytesPerRow,
        ),
      ),
      width: size.width,
      height: size.height,
    );
  }

  static int _degreesOf(DeviceOrientation o) => switch (o) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };

  @override
  Future<void> stop({bool keepStatus = false}) async {
    await _change;
    final change = _release();
    _change = change;
    await change;
    if (!keepStatus) _set(PoseSourceStatus.idle);
  }

  Future<void> _release() async {
    final camera = _camera;
    final model = _model;
    _camera = null;
    _model = null;
    _clock.stop();
    try {
      if (camera != null) {
        if (camera.value.isStreamingImages) await camera.stopImageStream();
        await camera.dispose();
      }
    } on Object catch (e, st) {
      unawaited(Monitoring.captureException(e, st));
    }
    try {
      await model?.close();
    } on Object catch (e, st) {
      unawaited(Monitoring.captureException(e, st));
    }
  }
}
