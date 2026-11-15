import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Store text stays within Google Play / App Store limits. Placeholders are
/// only rejected when STORE_LISTING_RELEASE=true (the upload workflow).
void main() {
  const limits = {
    'title.txt': 30,
    'short_description.txt': 80,
    'full_description.txt': 4000,
    'name.txt': 30,
    'subtitle.txt': 30,
    'keywords.txt': 100,
    'promotional_text.txt': 170,
    'description.txt': 4000,
  };
  const placeholders = ['Feature one', 'keyword1', 'اكتب هنا', 'كلمة1'];
  final releasing = Platform.environment['STORE_LISTING_RELEASE'] == 'true';

  final files = Directory('store').existsSync()
      ? Directory('store')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => limits.containsKey(f.uri.pathSegments.last))
            .toList()
      : <File>[];

  test('every store text is within its limit', () {
    final tooLong = [
      for (final file in files)
        if (file.readAsStringSync().trim().runes.length >
            limits[file.uri.pathSegments.last]!)
          file.path,
    ];
    expect(tooLong, isEmpty);
  });

  test('no placeholder text is uploaded', () {
    final unfinished = [
      for (final file in files)
        if (placeholders.any(file.readAsStringSync().contains)) file.path,
    ];
    expect(unfinished, releasing ? isEmpty : anything);
  }, skip: releasing ? false : 'only checked by the Store listing workflow');

  test('the Play App content answers are complete', () {
    final file = File('store/play_app_content.json');
    if (!file.existsSync()) return;
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final sections = (data['sections'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(sections, isNotEmpty);
    final problems = <String>[];
    for (final section in sections) {
      for (final key in ['id', 'title', 'title_ar', 'items']) {
        if (section[key] == null) problems.add('${section['id']}: no $key');
      }
      for (final item
          in (section['items'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        final answer = item['a'] as String? ?? '';
        if (answer.trim().isEmpty) {
          problems.add('${section['id']}: "${item['q']}" has no answer');
        }
        // An unfinished answer says so; <CODE>-style values are typed in.
        if (releasing && answer.contains('TODO')) {
          problems.add('${section['id']}: "${item['q']}" is a TODO');
        }
      }
    }
    expect(problems, isEmpty);
  });
}
