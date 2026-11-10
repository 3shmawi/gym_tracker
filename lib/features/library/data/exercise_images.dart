import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The pictures bundled for library exercises (`assets/exercises/`).
///
/// Each picture is a transparent mask in two sizes, tinted with the theme's
/// text colour at run time, so it has no background and works in dark and
/// light. An exercise with no picture here shows the library placeholder.
/// How to add one: `docs/features/exercise_images.md`.
abstract final class ExerciseImages {
  static const directory = 'assets/exercises';
  static const manifestAsset = '$directory/manifest.json';

  /// The exercises that have a picture. Must match the manifest and the files
  /// (`exercise_images_test.dart` fails when they drift).
  static const available = <String>{
    'abs',
    'alternating_db_curl',
    'barbell_squat',
    'barbell_wrist_curl',
    'cable_bar_curl',
    'cable_kickback',
    'close_grip_row',
    'db_front_raise',
    'db_lateral_raise',
    'db_lunge',
    'db_overhead_extension',
    'db_shoulder_press',
    'db_shrug',
    'face_pull',
    'flat_db_press',
    'flat_machine_press',
    'hammer_close_grip_row',
    'hammer_curl',
    'high_cable_crossover',
    'incline_barbell_press',
    'incline_machine_press',
    'lat_pulldown_machine',
    'leg_curl',
    'leg_extension',
    'leg_press',
    'machine_calf_raise',
    'machine_shoulder_press',
    'pec_deck',
    'preacher_curl',
    'reverse_pec_deck',
    'reverse_wrist_curl',
    'rope_pushdown',
    'smith_shrug',
    'straight_arm_pulldown',
    'wide_lat_pulldown',
    'wide_t_bar_row',
  };

  static bool has(String exerciseId) => available.contains(exerciseId);

  /// The 640 px picture (the exercise screen).
  static String large(String exerciseId) => '$directory/$exerciseId.webp';

  /// The 160 px picture (list rows).
  static String thumb(String exerciseId) =>
      '$directory/${exerciseId}_thumb.webp';

  /// What the licenses page says once for the picture library a gym can
  /// choose from (538 Everkinetic drawings on Cloudinary): every picture has
  /// the same author and licence; each row keeps its own `attribution` in the
  /// database (docs/features/exercise_image_library.md).
  static const pictureLibraryLicense =
      'Exercise pictures chosen by your gym: drawings by Everkinetic '
      '(Greg Priday), from https://github.com/everkinetic/data '
      '(commit 446bb9a).\n\n'
      'License: Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0), '
      'https://creativecommons.org/licenses/by-sa/4.0/\n\n'
      'Changed: made transparent (the dark lines kept, the paper removed), '
      'resized to at most 1024 px and renamed; the app draws them in its text '
      'colour. The changed pictures are shared under the same licence.';

  /// Shows the pictures' attributions on the app's licenses page.
  static void registerLicenses() {
    LicenseRegistry.addLicense(() async* {
      yield const LicenseEntryWithLineBreaks([
        'Exercise picture library (Everkinetic)',
      ], pictureLibraryLicense);
    });
    LicenseRegistry.addLicense(() async* {
      final json = await rootBundle.loadString(manifestAsset);
      final manifest = ExerciseImageManifest.parse(json);
      yield LicenseEntryWithLineBreaks(const [
        'Exercise illustrations',
      ], manifest.licenseText());
    });
  }
}

/// One picture's record: where it came from and under which licence.
@immutable
class ExerciseImageEntry {
  const new({
    required this.exercise,
    required this.file,
    required this.thumb,
    required this.title,
    required this.sourceUrl,
    required this.sourceFile,
    required this.license,
    required this.licenseUrl,
    required this.author,
    required this.dateChecked,
    required this.licenseEvidence,
    required this.modified,
    required this.modification,
    required this.attribution,
    this.substitute = false,
    this.substituteNote = '',
  });

  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('A manifest entry must be an object');
    }
    String text(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('Manifest entry: "$key" must be text');
      }
      return value;
    }

    final evidence = json['licenseEvidence'];
    final modified = json['modified'];
    if (evidence is! List<Object?> || modified is! bool) {
      throw const FormatException(
        'Manifest entry: bad "licenseEvidence" or "modified"',
      );
    }
    final substitute = json['substitute'] ?? false;
    final note = json['substituteNote'] ?? '';
    if (substitute is! bool || note is! String) {
      throw const FormatException('Manifest entry: bad "substitute" fields');
    }
    return ExerciseImageEntry(
      exercise: text('exercise'),
      file: text('file'),
      thumb: text('thumb'),
      title: text('title'),
      sourceUrl: text('sourceUrl'),
      sourceFile: text('sourceFile'),
      license: text('license'),
      licenseUrl: text('licenseUrl'),
      author: text('author'),
      dateChecked: text('dateChecked'),
      licenseEvidence: [for (final e in evidence) e.toString()],
      modified: modified,
      modification: text('modification'),
      attribution: text('attribution'),
      substitute: substitute,
      substituteNote: note,
    );
  }

  final String exercise;
  final String file;
  final String thumb;
  final String title;
  final String sourceUrl;
  final String sourceFile;

  /// SPDX id of the licence the source is under.
  final String license;
  final String licenseUrl;
  final String author;

  /// `YYYY-MM-DD` of the day the licence was read.
  final String dateChecked;

  /// Pages that show the licence of this very image.
  final List<String> licenseEvidence;
  final bool modified;
  final String modification;

  /// The text shown on the licenses page.
  final String attribution;

  /// The picture shows a similar exercise for the same muscle, not this very
  /// one (the note says which).
  final bool substitute;
  final String substituteNote;
}

/// `assets/exercises/manifest.json`: every bundled picture and its licence.
@immutable
class ExerciseImageManifest {
  const new({
    required this.adaptedLicense,
    required this.adaptedLicenseUrl,
    required this.images,
  });

  factory parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, Object?>) {
      throw const FormatException('The manifest must be an object');
    }
    final images = json['images'];
    final adapted = json['adaptedLicense'];
    final adaptedUrl = json['adaptedLicenseUrl'];
    if (images is! List<Object?> ||
        adapted is! String ||
        adaptedUrl is! String) {
      throw const FormatException('The manifest is missing fields');
    }
    return ExerciseImageManifest(
      adaptedLicense: adapted,
      adaptedLicenseUrl: adaptedUrl,
      images: [for (final i in images) ExerciseImageEntry.fromJson(i)],
    );
  }

  /// Licences we may use in a commercial app on both stores. Everything else
  /// (NC, ND, unknown, "all rights reserved") is refused by the tests.
  static const allowedLicenses = <String>{
    'CC0-1.0',
    'CC-BY-4.0',
    'CC-BY-SA-3.0',
    'CC-BY-SA-4.0',
  };

  /// The licence the changed pictures are shared under (ShareAlike).
  final String adaptedLicense;
  final String adaptedLicenseUrl;
  final List<ExerciseImageEntry> images;

  ExerciseImageEntry? of(String exerciseId) =>
      images.where((i) => i.exercise == exerciseId).firstOrNull;

  /// What the licenses page shows: the notice, each attribution and the
  /// licence links.
  String licenseText() {
    final licenses = {for (final i in images) i.licenseUrl: i.license};
    final notice =
        'The exercise pictures are line drawings by Everkinetic, used under '
        'Creative Commons licenses. We changed them (made transparent and '
        'resized), and the changed pictures are shared under '
        '$adaptedLicense: $adaptedLicenseUrl';
    return [
      notice,
      '',
      for (final i in images) '- ${i.attribution}',
      '',
      'Licenses:',
      for (final e in licenses.entries) '${e.value}: ${e.key}',
    ].join('\n');
  }
}
