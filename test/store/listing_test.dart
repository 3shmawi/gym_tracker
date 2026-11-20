import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
<<<<<<< yours
    'release_notes.txt': 4000,
    'default.txt': 500,
    // App Store Connect → App Review Information → Notes. Leave ~600 for
    // the demo code (and a link, if the recording cannot be attached).
    'notes.txt': 3400,
=======
    'notes.txt': 4000,
    'release_notes.txt': 4000,
    'default.txt': 500,
>>>>>>> kit a50ee3f
  };
  const placeholders = ['Feature one', 'keyword1', 'اكتب هنا', 'كلمة1', 'TODO'];
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
<<<<<<< yours
=======

  test('store images have the sizes the stores take, without alpha', () {
    final images = Directory('store').existsSync()
        ? Directory('store')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.png'))
              .where((f) => !f.path.contains('/tools/'))
              .toList()
        : <File>[];
    final problems = [
      for (final file in images)
        if (_imageProblem(file) case final problem?) '${file.path}: $problem',
    ];
    expect(problems, isEmpty);
  });
}

/// Sizes from Apple's "Screenshot specifications" and Google Play's "Add
/// preview assets" (checked 2026-11-15). PNG header: width and height are
/// bytes 16–23, the colour type byte 25 (2 = RGB, 6 = RGB + alpha).
String? _imageProblem(File file) {
  final bytes = file.readAsBytesSync();
  if (bytes.length < 26) return 'not a PNG';
  final data = ByteData.sublistView(bytes);
  final w = data.getUint32(16);
  final h = data.getUint32(20);
  final alpha = bytes[25] != 2;
  final name = file.uri.pathSegments.last;
  bool sizeIn(List<List<int>> sizes) =>
      sizes.any((s) => (s[0] == w && s[1] == h) || (s[0] == h && s[1] == w));

  if (name == 'icon.png') {
    return w == 512 && h == 512 ? null : '$w×$h, needs 512×512';
  }
  if (alpha) return 'has an alpha channel (both stores refuse it)';
  if (name.startsWith('header_')) {
    return w == 3840 && h == 1646 ? null : '$w×$h, needs 3840×1646';
  }
  if (name.startsWith('search_')) {
    return w * 2 == h * 3 && w >= 1920 && w <= 3840
        ? null
        : '$w×$h, needs 3:2 from 1920×1280 to 3840×2560';
  }
  if (name == 'featureGraphic.png') {
    return w == 1024 && h == 500 ? null : '$w×$h, needs 1024×500';
  }
  if (name.endsWith('_iphone69.png')) {
    return sizeIn(const [
          [1320, 2868],
          [1290, 2796],
          [1260, 2736],
        ])
        ? null
        : '$w×$h is not an iPhone 6.9" size';
  }
  if (name.endsWith('_ipad13.png')) {
    return sizeIn(const [
          [2064, 2752],
          [2048, 2732],
        ])
        ? null
        : '$w×$h is not an iPad 13" size';
  }
  final long = w > h ? w : h;
  final short = w > h ? h : w;
  if (short < 320 || long > 3840) return '$w×$h, sides must be 320–3840';
  if (long > short * 2) {
    return '$w×$h, the long side is more than twice the short';
  }
  return null;
>>>>>>> kit a50ee3f
}
