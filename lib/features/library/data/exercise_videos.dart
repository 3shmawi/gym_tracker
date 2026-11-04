import 'package:gym_tracker/core/media/youtube_link.dart';

/// The how-to video of each library exercise (YouTube, played in the
/// privacy-enhanced player). Approved by the owner on 2026-11-03 from
/// `docs/features/exercise_video_candidates.md`; every id was checked with
/// YouTube oEmbed (exists, embedding allowed) that day. A gym's own video
/// replaces it; an exercise without one shows pictures and steps only.
abstract final class ExerciseVideos {
  static const _byExercise = <String, YouTubeVideoRef>{
    // AR · ِAhmed Essam
    'flat_db_press': YouTubeVideoRef('mCEIUZySRPY'),
    // AR · Rashid_Alnajem
    'wide_lat_pulldown': YouTubeVideoRef('amgXq2ThD0c'),
    // AR · Saif PT
    'incline_machine_press': YouTubeVideoRef('OtIBUjccE-w'),
    // AR · Fitnessyard.com
    'close_grip_row': YouTubeVideoRef('Bk6tXcct3WI'),
    // AR · العبها صح مع همام
    'pec_deck': YouTubeVideoRef('aMnG6Lo8LEo'),
    // AR · Fitness Arabia
    'abs': YouTubeVideoRef('dWz8v9Vza_A'),
    // AR · Arabian Bodybuilding
    'reverse_pec_deck': YouTubeVideoRef('pYdzGA6B9U0'),
    // EN · HASfit
    'db_shrug': YouTubeVideoRef('cbEVfGaXcH0'),
    // EN · Live Lean TV Daily Exercises
    'cable_kickback': YouTubeVideoRef('ZvF4Oi_6Vtg'),
    // AR · العبها صح مع همام
    'hammer_curl': YouTubeVideoRef('05r7Nu8qc70'),
    // EN · Germain Craddock's EVA
    'rope_pushdown': YouTubeVideoRef('K--j4Qh9d2s'),
    // AR · يوسف الشمري فتنس
    'barbell_squat': YouTubeVideoRef('FMsBtgg4asI'),
    // AR · Coach Zaher8
    'leg_press': YouTubeVideoRef('KaLc79eROiI'),
    // AR · Fitness Arabia
    'db_lunge': YouTubeVideoRef('ty9aAjPVuN4'),
    // AR · Fitness Arabia
    'leg_extension': YouTubeVideoRef('d4LEzUALIOw'),
    // AR · Coach John - Fitness Trainer and Nutritionist
    'leg_curl': YouTubeVideoRef('DfmEb-5HvNQ'),
    // AR · Fitness Arabia
    'machine_calf_raise': YouTubeVideoRef('SG1-FJqIjRU'),
    // EN · Horton Barbell
    'barbell_wrist_curl': YouTubeVideoRef('ksfgK7DQnKc'),
    // EN · ATLASTHETICS
    'reverse_wrist_curl': YouTubeVideoRef('hCMC4Vh2g_s'),
    // EN · ScottHermanFitness
    'alternating_db_curl': YouTubeVideoRef('sAq_ocpRh_I'),
    // AR · Saif PT
    'db_front_raise': YouTubeVideoRef('SDm9pJJtLxo'),
    // EN · Adriana Albritton FitnAll
    'db_shoulder_press': YouTubeVideoRef('-5Ek9z76BUc'),
    // EN · Horton Barbell
    'straight_arm_pulldown': YouTubeVideoRef('70Ajji0V9vk'),
  };

  /// The library's video of [exerciseId], or null.
  static YouTubeVideoRef? of(String exerciseId) => _byExercise[exerciseId];

  /// Every exercise id that has a video (for tests).
  static Iterable<String> get exerciseIds => _byExercise.keys;
}
