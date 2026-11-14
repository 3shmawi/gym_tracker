import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:meta/meta.dart';

/// Which logo file to show for a gym: its path and version. Two refs are
/// equal when both are, so a replaced logo is a new ref.
@immutable
class GymLogoRef {
  const new({required this.gymId, required this.path, required this.version});

  final String gymId;
  final String path;

  /// Milliseconds since epoch of `logo_updated_at` (0: unknown).
  final int version;

  @override
  bool operator ==(Object other) =>
      other is GymLogoRef &&
      other.gymId == gymId &&
      other.path == path &&
      other.version == version;

  @override
  int get hashCode => Object.hash(gymId, path, version);
}

/// What the gym's setting says about an ended member's history in that gym:
/// still readable, or hidden (never deleted).
enum HistoryAfterEnd {
  readable,
  locked;

  static HistoryAfterEnd fromName(Object? name) =>
      name == 'locked' ? HistoryAfterEnd.locked : HistoryAfterEnd.readable;
}

/// A gym as the member sees it. Only what the app needs: no owner, no other
/// members.
@immutable
class Gym {
  const new({
    required this.id,
    required this.name,
    this.historyAfterEnd = HistoryAfterEnd.readable,
    this.brandColor,
    this.logoPath,
    this.logoVersion,
  });

  /// Reads the `gym` object the server returns. Anything of the wrong shape is
  /// a `FormatException` (the repository turns it into a failure).
  factory fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('gym without id or name');
    }
    return Gym(
      id: id,
      name: name,
      historyAfterEnd: HistoryAfterEnd.fromName(json['history_after_end']),
      brandColor: readBrandColor(json['brand_color']),
      logoPath: readLogoPath(id, json['logo_path']),
      logoVersion: readLogoVersion(json['logo_updated_at']),
    );
  }

  final String id;
  final String name;
  final HistoryAfterEnd historyAfterEnd;

  /// The colour the gym's owner chose for the app, as `#rrggbb`, or null for
  /// Azm's colours (docs/designs/gym_brand_colours.md).
  ///
  /// How the gym looks, not which gym it is: **not part of `==`**, so a new
  /// colour does not restart what depends on the membership (the workout
  /// repository, the plan, the pictures). Read it through
  /// `activeBrandColorProvider`.
  final String? brandColor;

  /// The server's or the cache's value if it is a colour the app accepts
  /// (`#rrggbb`, lower case, not black / white / grey), else null. A value
  /// of any other type or shape is "no colour", never an error.
  static String? readBrandColor(Object? value) =>
      BrandColorRule.parse(value) == null ? null : value! as String;

  /// Where the gym's logo is in the `gym-logos` bucket
  /// (`<this gym's id>/logo.png|jpg|jpeg`), or null: no logo, or a path the
  /// app refuses (docs/designs/gym_logo.md §3).
  ///
  /// Like [brandColor], how the gym looks: **not part of `==`**.
  final String? logoPath;

  /// When the logo was last written (`gyms.logo_updated_at`, set by the
  /// database only). A logo replaced at the same path has a new version.
  /// Not part of `==`.
  final DateTime? logoVersion;

  /// The logo to show, or null: [logoPath] with its version (0 when the
  /// server has none yet).
  GymLogoRef? get logo {
    final path = logoPath;
    if (path == null) return null;
    return GymLogoRef(
      gymId: id,
      path: path,
      version: logoVersion?.millisecondsSinceEpoch ?? 0,
    );
  }

  static final _logoPath = RegExp(
    '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'
    r'/logo\.(?:png|jpe?g)$',
  );

  /// [value] if it is a logo path in [gymId]'s own folder, else null: the
  /// dashboard's `LOGO_PATH` rule plus its "starts with the gym's id" check
  /// (`dashboard/src/gyms/gyms.ts`). Anything else is "no logo", never an
  /// error.
  static String? readLogoPath(Object? gymId, Object? value) {
    if (value is! String || gymId is! String || value.length > 128) {
      return null;
    }
    final match = _logoPath.firstMatch(value);
    return match != null && match.group(1) == gymId ? value : null;
  }

  /// The version as the server writes it (ISO 8601), or null.
  static DateTime? readLogoVersion(Object? value) {
    if (value is! String || value.length > 64) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  /// Up to two letters for the logo tile ("Iron House" → "IH").
  String get initials {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    String first(String w, int n) => String.fromCharCodes(w.runes.take(n));
    final letters = words.length == 1
        ? first(words.first, 2)
        : words.take(2).map((w) => first(w, 1)).join();
    return letters.toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      other is Gym &&
      other.id == id &&
      other.name == name &&
      other.historyAfterEnd == historyAfterEnd;

  @override
  int get hashCode => Object.hash(id, name, historyAfterEnd);
}
