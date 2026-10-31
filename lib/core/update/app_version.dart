import 'package:flutter/foundation.dart';

/// A semantic version (`major.minor.patch`). Build numbers (`+12`) and
/// pre-release tags (`-beta`) are ignored when comparing.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const new(this.major, this.minor, this.patch);

  /// Parses `1.2.3`, `1.2`, `1.2.3+45` or `1.2.3-beta`. Missing or invalid
  /// parts count as 0.
  factory parse(String value) {
    final core = value.trim().split(RegExp('[+-]')).first;
    final parts = core.split('.');
    int part(int index) =>
        index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0;
    return AppVersion(part(0), part(1), part(2));
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
