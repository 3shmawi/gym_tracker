import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file: compares goldens with a 0.5% tolerance
/// (anti-aliasing noise only).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (goldenFileComparator is LocalFileComparator) {
    goldenFileComparator = _TolerantComparator(
      (goldenFileComparator as LocalFileComparator).basedir.resolve('x.dart'),
    );
  }
  await testMain();
}

/// Loads the real fonts (Inter, Cairo, Material icons) so golden
/// screenshots show real text instead of the test font's boxes.
///
/// Only golden tests call this: Flutter's contrast check is built for the
/// test font and misreads anti-aliased real glyphs. Once loaded, fonts stay
/// for the rest of the file, so goldens run last (`screenUiTests` does).
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<void> load(String family, Iterable<File> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  for (final family in ['Inter', 'Cairo']) {
    final dir = Directory('assets/fonts/$family');
    if (!dir.existsSync()) continue;
    await load(
      family,
      dir.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')),
    );
  }

  // Material icons ship with the Flutter SDK, next to the test tool.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await load('MaterialIcons', [icons]);
  }
}

bool _fontsLoaded = false;

class _TolerantComparator extends LocalFileComparator {
  new(super.testFile);

  static const _tolerance = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
