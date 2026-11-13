import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_cycle.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';

/// Feeds [values] at [fps] starting at [from]; returns every event.
List<RepEvent> feed(
  RepCycle cycle,
  List<double?> values, {
  double fps = 15,
  Duration from = Duration.zero,
}) {
  final step = Duration(microseconds: (1e6 / fps).round());
  final events = <RepEvent>[];
  for (var i = 0; i < values.length; i++) {
    events.addAll(cycle.onSignal(values[i], from + step * i));
  }
  return events;
}

/// [n] frames of [v].
List<double?> hold(double? v, int n) => List.filled(n, v);

/// A smooth rep from 0 to [peak] and back in [frames] frames.
List<double> rep(int frames, {double peak = 1}) => [
  for (var i = 0; i <= frames; i++)
    peak * (i <= frames / 2 ? i / (frames / 2) : (frames - i) / (frames / 2)),
];

void main() {
  group('RepCycle', () {
    test('finds the body after half a second, then counts full reps', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        ...rep(24),
        ...hold(0, 6),
        ...rep(24),
        ...hold(0, 6),
      ]);
      expect(events.whereType<BodyFound>(), hasLength(1));
      expect(events.whereType<RepCounted>().map((e) => e.total), [1, 2]);
      expect(cycle.reps, 2);
      expect(cycle.phase, RepPhase.ready);
    });

    test('a rep is timed from the top to the top again', () {
      final cycle = RepCycle();
      final events = feed(cycle, [...hold(0, 15), ...rep(24), ...hold(0, 3)]);
      final counted = events.whereType<RepCounted>().single;
      // 24 frames at 15 fps, give or take the frames at the thresholds.
      expect(counted.took.inMilliseconds, inInclusiveRange(1000, 1800));
      expect(counted.depth, greaterThan(0.8));
    });

    test('a dip that does not reach full depth is a half rep', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        ...rep(24, peak: 0.6),
        ...hold(0, 6),
      ]);
      expect(events.whereType<HalfRep>(), hasLength(1));
      expect(events.whereType<RepCounted>(), isEmpty);
    });

    test('small dips (breathing, shifting) are ignored', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        ...rep(20, peak: 0.3),
        ...hold(0, 6),
      ]);
      expect(events.whereType<HalfRep>(), isEmpty);
      expect(events.whereType<RepCounted>(), isEmpty);
    });

    test('a full rep faster than the minimum is too fast, not counted', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        // 0.47 s top to top: deep enough, too quick.
        ...rep(14),
        ...hold(0, 6),
      ], fps: 30);
      expect(events.whereType<TooFast>(), hasLength(1));
      expect(cycle.reps, 0);
    });

    test('a slow rep with a long hold at the bottom counts', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        ...rep(20).take(11),
        ...hold(1, 30),
        ...rep(20).skip(11),
        ...hold(0, 5),
      ]);
      expect(events.whereType<RepCounted>(), hasLength(1));
    });

    test('starting at the bottom does not count until the top is seen', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(1, 15),
        ...[for (var i = 10; i >= 0; i--) i / 10],
        ...hold(0, 5),
      ]);
      expect(events.whereType<RepCounted>(), isEmpty);
      expect(cycle.phase, RepPhase.ready);
    });

    test('body lost after 1.5 s; the rep in progress is dropped', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        ...rep(24).take(13),
        ...hold(null, 30),
        ...hold(0, 15),
        ...rep(24),
        ...hold(0, 3),
      ]);
      expect(events.whereType<BodyLost>(), hasLength(1));
      expect(events.whereType<BodyFound>(), hasLength(2));
      expect(cycle.reps, 1);
    });

    test('a short gap does not lose the body or the rep', () {
      final cycle = RepCycle();
      final r = rep(24);
      final events = feed(cycle, [
        ...hold(0, 15),
        // The bottom is seen, then 8 frames (0.5 s) are missing.
        ...r.take(14),
        ...hold(null, 8),
        ...r.skip(22),
        ...hold(0, 3),
      ]);
      expect(events.whereType<BodyLost>(), isEmpty);
      expect(cycle.reps, 1);
    });

    test('no frames at all for a while (app paused) also loses the body', () {
      final cycle = RepCycle();
      feed(cycle, hold(0, 15));
      final later = cycle.onSignal(0, const Duration(seconds: 10));
      expect(later, contains(const BodyLost()));
    });

    test('one wild frame is dropped as a glitch', () {
      final cycle = RepCycle();
      final events = feed(cycle, [...hold(0, 15), 1, ...hold(0, 15)]);
      expect(events.whereType<HalfRep>(), isEmpty);
      expect(events.whereType<RepCounted>(), isEmpty);
    });

    test('frames older than the last one are ignored', () {
      final cycle = RepCycle();
      feed(cycle, hold(0, 15));
      expect(cycle.onSignal(1, Duration.zero), isEmpty);
      expect(cycle.onSignal(1, const Duration(seconds: 1)), isEmpty);
    });

    test('NaN and infinity are treated as "not visible"', () {
      final cycle = RepCycle();
      final events = feed(cycle, [
        ...hold(0, 15),
        ...hold(double.nan, 30),
        double.infinity,
      ]);
      expect(events.whereType<BodyLost>(), hasLength(1));
      expect(cycle.reps, 0);
    });

    test('reset starts over', () {
      final cycle = RepCycle();
      feed(cycle, [...hold(0, 15), ...rep(24), ...hold(0, 3)]);
      expect(cycle.reps, 1);
      cycle.reset();
      expect(cycle.reps, 0);
      expect(cycle.phase, RepPhase.notVisible);
      // Time may start again from zero after a reset.
      expect(feed(cycle, hold(0, 15)), contains(const BodyFound()));
    });
  });
}
