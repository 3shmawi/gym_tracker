import 'dart:async';

import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';

/// Replays recorded frames at their own pace (or as fast as possible),
/// with no camera: tests, the iOS Simulator demo and the diagnostic screen.
class RecordedPoseSource implements PoseSource {
  new(this.recording, {this.realTime = true, this.loop = false});

  final List<PoseFrame> recording;

  /// Waits between frames like a camera; false sends them all at once.
  final bool realTime;

  /// Starts again from the first frame at the end.
  final bool loop;

  final _frames = StreamController<PoseFrame>.broadcast();
  final _status = StreamController<PoseSourceStatus>.broadcast();
  PoseSourceStatus _current = PoseSourceStatus.idle;
  int _run = 0;

  @override
  Stream<PoseFrame> get frames => _frames.stream;

  @override
  Stream<PoseSourceStatus> get status => _status.stream;

  @override
  PoseSourceStatus get currentStatus => _current;

  void _set(PoseSourceStatus s) {
    _current = s;
    _status.add(s);
  }

  @override
  Future<void> start() async {
    if (_current.state == PoseSourceState.running) return;
    final run = ++_run;
    _set(const PoseSourceStatus(PoseSourceState.running));
    unawaited(_play(run));
  }

  Future<void> _play(int run) async {
    var offset = Duration.zero;
    do {
      var previous = Duration.zero;
      for (final frame in recording) {
        if (run != _run) return;
        if (realTime) {
          final wait = frame.at - previous;
          if (wait > Duration.zero) await Future<void>.delayed(wait);
          if (run != _run) return;
        }
        previous = frame.at;
        _frames.add(
          PoseFrame(
            at: frame.at + offset,
            joints: frame.joints,
            aspect: frame.aspect,
          ),
        );
      }
      offset +=
          (recording.isEmpty ? Duration.zero : recording.last.at) +
          const Duration(milliseconds: 66);
      // Let listeners (and stop()) run between laps, even when not waiting
      // between frames; an empty recording would otherwise spin for ever.
      await Future<void>.delayed(Duration.zero);
    } while (loop && recording.isNotEmpty && run == _run);
  }

  @override
  Future<void> stop() async {
    _run++;
    _set(PoseSourceStatus.idle);
  }
}
