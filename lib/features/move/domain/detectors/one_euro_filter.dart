import 'dart:math' as math;

/// The 1€ filter (Casiez, Roussel and Vogel, CHI 2012): smooths jitter when
/// the value moves slowly and follows quickly when it moves fast.
class OneEuroFilter {
  new({required this.minCutoff, required this.beta, this.derivativeCutoff = 1});

  /// Hz. Lower = smoother at rest.
  final double minCutoff;

  /// How much speed raises the cutoff. Higher = less lag when moving.
  final double beta;
  final double derivativeCutoff;

  double? _x;
  double _dx = 0;
  double? _t;

  /// Feeds [value] at [seconds]; returns the smoothed value. A time that
  /// does not move forward returns the last value unchanged.
  double filter(double value, double seconds) {
    final lastX = _x;
    final lastT = _t;
    if (lastX == null || lastT == null) {
      _x = value;
      _t = seconds;
      return value;
    }
    final dt = seconds - lastT;
    if (dt <= 0) return lastX;
    final rawDx = (value - lastX) / dt;
    _dx = _dx + _alpha(derivativeCutoff, dt) * (rawDx - _dx);
    final cutoff = minCutoff + beta * _dx.abs();
    final x = lastX + _alpha(cutoff, dt) * (value - lastX);
    _x = x;
    _t = seconds;
    return x;
  }

  void reset() {
    _x = null;
    _t = null;
    _dx = 0;
  }

  static double _alpha(double cutoff, double dt) {
    final tau = 1 / (2 * math.pi * cutoff);
    return 1 / (1 + tau / dt);
  }
}
