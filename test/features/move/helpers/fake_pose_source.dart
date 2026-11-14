import 'dart:async';

import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';

/// A pose source the test drives: push frames with [emit], choose how
/// [start] ends with [startsAs]. Counts starts and stops.
class FakePoseSource implements PoseSource {
  new({this.startsAs = const PoseSourceStatus(PoseSourceState.running)});

  PoseSourceStatus startsAs;

  /// When set, [start] waits for it: like the camera waiting for the
  /// member to answer the permission dialog.
  Completer<void>? gate;
  int starts = 0;
  int stops = 0;

  final _frames = StreamController<PoseFrame>.broadcast(sync: true);
  final _status = StreamController<PoseSourceStatus>.broadcast(sync: true);
  PoseSourceStatus _current = PoseSourceStatus.idle;

  @override
  Stream<PoseFrame> get frames => _frames.stream;

  @override
  Stream<PoseSourceStatus> get status => _status.stream;

  @override
  PoseSourceStatus get currentStatus => _current;

  void setStatus(PoseSourceStatus s) {
    _current = s;
    _status.add(s);
  }

  void emit(PoseFrame frame) => _frames.add(frame);

  @override
  Future<void> start() async {
    starts++;
    await gate?.future;
    setStatus(startsAs);
  }

  @override
  Future<void> stop() async {
    stops++;
    setStatus(PoseSourceStatus.idle);
  }
}

/// A fake camera that can zoom between [min] and [max]; starts at [min],
/// like the real one.
class FakeZoomablePoseSource extends FakePoseSource
    implements ZoomablePoseSource {
  new({this.min = 0.6, this.max = 8});

  final double min;
  final double max;
  CameraZoom? _zoom;
  final List<double> asked = [];

  @override
  CameraZoom? get zoom => _zoom;

  @override
  Future<void> start() async {
    await super.start();
    _zoom = CameraZoom(min: min, max: max, level: min);
  }

  @override
  Future<void> stop() async {
    _zoom = null;
    await super.stop();
  }

  @override
  Future<CameraZoom?> setZoom(double level) async {
    asked.add(level);
    final z = _zoom;
    if (z == null) return null;
    return _zoom = z.at(level);
  }
}
