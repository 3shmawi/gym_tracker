import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:meta/meta.dart';

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
