import 'dart:async';

import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';

/// A pose source the test drives: push frames with [emit], choose how
/// [start] ends with [startsAs]. Counts starts and stops.
class FakePoseSource implements PoseSource {
  new({this.startsAs = const PoseSourceStatus(PoseSourceState.running)});

  PoseSourceStatus startsAs;
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
    setStatus(startsAs);
  }

  @override
  Future<void> stop() async {
    stops++;
    setStatus(PoseSourceStatus.idle);
  }
}
