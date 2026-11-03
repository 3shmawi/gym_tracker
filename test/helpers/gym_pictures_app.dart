import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/cloudinary_url.dart';
import 'package:gym_tracker/core/media/media_cache.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for Cloudinary and the phone's picture cache, for the gym
/// pictures demo: online it "downloads" (a bundled drawing per public id)
/// and keeps the bytes; offline it serves only what it kept, like
/// `MediaCache.fetch`.
class FakePictureCloud {
  bool online = true;
  final Map<Uri, Uint8List> _kept = {};
  int downloads = 0;

  static const _drawings = {
    'exercises/ek-0055-tension': 'flat_db_press',
    'exercises/ek-0055-relaxation': 'incline_machine_press',
    'exercises/ek-0043-tension': 'pec_deck',
    'exercises/ek-0043-relaxation': 'reverse_pec_deck',
  };

  Future<Uint8List> fetch(Uri url) async {
    final kept = _kept[url];
    if (!online) {
      if (kept != null) return kept;
      throw StateError('offline, nothing cached');
    }
    final id = url.pathSegments.skip(4).join('/').replaceAll('.png', '');
    final drawing = _drawings[id];
    if (drawing == null) throw StateError('404');
    final data = await rootBundle.load('assets/exercises/$drawing.webp');
    downloads++;
    return _kept[url] = data.buffer.asUint8List();
  }

  ImageProvider? image(String publicId, PictureSize size) {
    final url = CloudinaryUrl.picture(
      cloudName: 'azm',
      publicId: publicId,
      size: size,
    );
    return url == null ? null : CachedMediaImage(url, fetch: fetch);
  }
}

/// Flat Dumbbell Press with the two frames of one move, Incline Machine
/// Press with four unrelated pictures (what a captain chose).
final GymMedia demoGymMedia = GymMedia.fromPictures([
  const GymExercisePicture(
    exerciseId: 'flat_db_press',
    publicId: 'exercises/ek-0055-tension',
    position: 1,
  ),
  const GymExercisePicture(
    exerciseId: 'flat_db_press',
    publicId: 'exercises/ek-0055-relaxation',
    position: 2,
  ),
  for (final (i, id) in [
    'exercises/ek-0043-tension',
    'exercises/ek-0055-tension',
    'exercises/ek-0043-relaxation',
    'exercises/ek-0055-relaxation',
  ].indexed)
    GymExercisePicture(
      exerciseId: 'incline_machine_press',
      publicId: id,
      position: i + 1,
    ),
]);

/// The app's router with the 5-day plan, the gym's pictures from
/// [cloud] and the device online state from its `online`.
Future<void> pumpGymPicturesApp(
  WidgetTester tester,
  FakePictureCloud cloud, {
  String at = '/library?day=day-1',
}) async {
  SharedPreferences.setMockInitialValues({
    LocalWorkoutRepository.planKey: jsonEncode(
      PlanTemplates.fiveDaySplit.toJson(),
    ),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(
          LocalWorkoutRepository(prefs),
        ),
        activeGymMediaProvider.overrideWith((ref) async => demoGymMedia),
        gymPictureImageProvider.overrideWithValue(cloud.image),
        deviceOnlineProvider.overrideWith((ref) => Stream.value(cloud.online)),
      ],
      child: AppUi.testWrap(
        AppScreenScale(
          builder: (context) => MaterialApp.router(
            routerConfig: appRouter,
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  appRouter.go(at);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
