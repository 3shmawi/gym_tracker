import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/media/cloudinary_url.dart';
import 'package:gym_tracker/core/media/media_cache.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';
import 'package:gym_tracker/features/library/data/exercise_videos.dart';
import 'package:gym_tracker/features/library/domain/entities/exercise_pictures.dart';
import 'package:gym_tracker/features/library/presentation/exercise_guide_view.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';
import 'package:gym_tracker/features/library/presentation/widgets/library_feedback.dart';
import 'package:gym_tracker/features/video/presentation/video_providers.dart';
import 'package:gym_tracker/features/video/presentation/widgets/exercise_video_card.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';

/// `/library/<exerciseId>[?day=<dayId>]`: the picture and steps of one
/// exercise. With a day it offers to add the exercise to it. Both ids are
/// untrusted: an unknown exercise says "not in the library", an unknown day
/// just hides the add button.
class ExerciseGuidePage extends ConsumerStatefulWidget {
  const new({required this.exerciseId, this.dayId, super.key});

  final String exerciseId;
  final String? dayId;

  @override
  ConsumerState<ExerciseGuidePage> createState() => _ExerciseGuidePageState();
}

class _ExerciseGuidePageState extends ConsumerState<ExerciseGuidePage> {
  bool _picturesReported = false;

  @override
  void initState() {
    super.initState();
    final muscle = ref
        .read(exerciseLibraryProvider)
        .byId(widget.exerciseId)
        ?.muscle
        .name;
    unawaited(
      Analytics.capture('library_exercise_viewed', {'muscle': ?muscle}),
    );
  }

  Future<void> _add(String dayId) async {
    final exercise = ref.read(exerciseLibraryProvider).byId(widget.exerciseId);
    if (exercise == null) return;
    final error = await ref
        .read(planEditorControllerProvider.notifier)
        .addLibraryExercise(dayId, exercise.defaults);
    if (!mounted) return;
    if (error != null) {
      showPlanEditError(context, error);
      return;
    }
    if (context.canPop()) context.pop();
  }

  /// `exercise_pictures_viewed` once per screen, when the source is known:
  /// how many pictures (bucketed) and whether the gym's or the bundled one.
  /// No id, name or URL.
  void _reportPictures(ExercisePictures pictures, int shown) {
    if (_picturesReported) return;
    _picturesReported = true;
    final source = pictures.source;
    if (source == PictureSource.placeholder) return;
    unawaited(
      Analytics.capture('exercise_pictures_viewed', {
        'count': ExercisePictures.countBucket(
          source == PictureSource.gym ? shown : 1,
        ),
        'source': source.name,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final exercise = ref.watch(exerciseLibraryProvider).byId(widget.exerciseId);
    final media = ref.watch(activeGymMediaProvider);
    final toImage = ref.watch(gymPictureImageProvider);
    // The gym's pictures that make a valid image, cover first.
    final gym = [
      for (final p in (media.value ?? GymMedia.empty).picturesFor(
        widget.exerciseId,
      ))
        if (toImage(p.publicId, PictureSize.large) case final image?)
          (
            ref: LibraryPictureRef(
              publicId: p.publicId,
              exerciseKey: p.exerciseKey,
              frame: p.frame,
            ),
            image: image,
          ),
    ];
    final pictures = ExercisePictures(
      gym: [for (final g in gym) g.ref],
      hasBundled: ExerciseImages.has(widget.exerciseId),
    );
    if (exercise != null && !media.isLoading) {
      _reportPictures(pictures, gym.length);
    }
    final offline = !(ref.watch(deviceOnlineProvider).value ?? true);
    // The how-to video: the library's (the gym's own comes in V-B).
    final video = ExerciseVideos.of(widget.exerciseId);
    final videoInfo = video == null
        ? null
        : ref.watch(videoInfoProvider(video.id));
    final dayId = widget.dayId;
    final lang = Localizations.localeOf(context).languageCode;
    final editor = dayId == null
        ? null
        : ref.watch(planEditorControllerProvider).value;
    final day = dayId == null ? null : editor?.plan.dayById(dayId);
    final canAdd = day != null && (editor?.permissions.editStructure ?? false);
    return ExerciseGuideView(
      exercise: exercise,
      onBack: () => context.go(AppRoutes.plan),
      dayName: canAdd ? day.name.of(lang) : null,
      alreadyInDay:
          day?.exercises.any((e) => e.id == widget.exerciseId) ?? false,
      onAdd: canAdd ? () => unawaited(_add(day.id)) : null,
      gymPictures: [for (final g in gym) g.image],
      movePair: pictures.isMovePair,
      offline: offline,
      onOpenCredits: () => showLicensePage(context: context),
      video: video == null
          ? null
          : ExerciseVideoCardData(
              thumbnail: CachedMediaImage(VideoInfo.thumbnail(video.id)),
              info: videoInfo?.value,
              loading: videoInfo?.isLoading ?? false,
              offline: offline,
            ),
      onPlayVideo: video == null
          ? null
          : () => unawaited(
              ref
                  .read(videoActionsProvider)
                  .play(
                    context,
                    video,
                    VideoSource.library,
                    info: videoInfo?.value,
                  ),
            ),
      onOpenVideoInYouTube: video == null
          ? null
          : () => unawaited(
              ref
                  .read(videoActionsProvider)
                  .openInYouTube(video, VideoSource.library),
            ),
    );
  }
}
