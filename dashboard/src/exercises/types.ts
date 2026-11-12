// Exercise media (D2): what the dashboard reads and writes for a gym.
// Tables: exercise_images (0013, public read), gym_exercise_images (0015),
// gym_exercise_videos (0017). docs/features/dashboard.md → "D2 Exercise media".

export type Muscle = 'chest' | 'back' | 'shoulders' | 'arms' | 'legs' | 'core';

/** One exercise of the app's library (src/exercises/library.ts). */
export interface LibraryExercise {
  /** snake_case library id, as stored in gym_exercise_images.exercise_id. */
  readonly id: string;
  readonly en: string;
  readonly ar: string;
  readonly muscle: Muscle;
  /** The library has its own how-to video (members see it when the gym has none). */
  readonly libraryVideo: boolean;
  /** Starting targets when it is added to a plan (the app's catalog). */
  readonly sets: number;
  readonly reps: number;
  /** Seconds. */
  readonly rest: number;
  /** Weight step, kg. */
  readonly step: number;
}

/** What the Exercises tab and page need of any exercise, the library's or one a captain wrote into a plan. */
export interface ExerciseLike {
  readonly id: string;
  readonly en: string;
  readonly ar: string;
  /** null for an exercise written into a plan: it has no muscle group. */
  readonly muscle: Muscle | null;
  readonly libraryVideo: boolean;
  /** Written in a member's plan, not part of the app's library. */
  readonly custom: boolean;
}

/** A gym's own video for an exercise: the id only, never a URL. */
export interface VideoRef {
  readonly id: string;
  readonly start: number | null;
  readonly end: number | null;
}

/** A picture of the shared library, as the picker shows it. */
export interface CatalogPicture {
  /** exercises/ek-0055-tension */
  readonly publicId: string;
  /** ek-0055: the two frames of one move share it. */
  readonly exerciseKey: string;
  /** tension = start of the move, relaxation = end. */
  readonly frame: 'tension' | 'relaxation';
  readonly title: string;
}

/** Everything a gym chose: picture ids in order (cover first) and the video, per exercise id. */
export interface GymMedia {
  readonly pictures: ReadonlyMap<string, readonly string[]>;
  readonly videos: ReadonlyMap<string, VideoRef>;
}
