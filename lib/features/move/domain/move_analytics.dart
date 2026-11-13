/// Analytics for Move games use buckets, never exact numbers, and never
/// images, landmarks or personal data (docs/designs/move_games.md §11).
abstract final class MoveAnalytics {
  static String repsBucket(int reps) => switch (reps) {
    <= 0 => '0',
    <= 5 => '1_5',
    <= 10 => '6_10',
    <= 20 => '11_20',
    <= 40 => '21_40',
    _ => '41_plus',
  };

  static String durationBucket(Duration d) => switch (d.inSeconds) {
    < 30 => 'lt_30s',
    <= 60 => '30_60s',
    <= 120 => '60_120s',
    _ => 'gt_120s',
  };

  /// Null when not measured (manual rounds).
  static String? fpsBucket(double? fps) => switch (fps) {
    null => null,
    < 8 => 'lt_8',
    < 15 => '8_15',
    _ => '15_plus',
  };
}
