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
    );
  }

  final String id;
  final String name;
  final HistoryAfterEnd historyAfterEnd;

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
