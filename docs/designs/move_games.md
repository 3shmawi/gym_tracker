# Design: Move games (camera rep games, starting with push-ups)

> **Status: approved by the owner on 2026-11-12, with game concept
> A · Stack and the recommended choice in each decision** (see
> "Decisions" at the end).
> `CLAUDE.md` asks for an EGM-reviewed spec. The EGM plugin is installed, but
> its `/egm:` commands can be started only by a person
> (`disable-model-invocation`), not by the agent that wrote this. So this
> spec was written by hand with the same sections. The owner approved it
> without an EGM review.

Mockup (Move card, hub, "why" screen, placement with live feedback, three
game concepts in play, pause, results with "Save to my training", manual
counter, denied / unsupported / body-lost states; English and Arabic, light
and dark): https://claude.ai/artifact/V6dWNvw3rFaUKBtMoaeJ26
Approved with the spec (2026-11-12); the game is concept A · Stack.

## Goal
1. Short rounds (30–60 s) where the phone's front camera counts **real**
   push-ups on the device, and each rep drives an **original** game in
   Azm's look.
2. The reps are saved as an ordinary set of the library exercise
   "Push-ups", so they count in progress and backup like any workout.
3. Adding the next exercise (pull-ups, squats, jumping jacks, high knees,
   plank) means **a detector + a placement guide + game rules + a catalog
   entry**, with no rebuild.
4. Nothing about the camera leaves the phone. Anyone who can't or won't
   use the camera gets the same rounds with a manual counter.

### Not in this version
- No multiplayer, leaderboards, streaks or daily goals (see Safety).
- No video recording, no photos, no "share my clip".
- No form scoring beyond depth and tempo. The "keep your body straight"
  hint is advice only, never a penalty (landmarks are too noisy for it).
- No watch or TV input.

### Originality rule
The idea came from a viral push-up-controlled clone of a famous
tap-to-flap game. **Nothing of that game is used**: no bird, no flapping
between pipes, no obstacles that kill on touch, no "game over on first
mistake", no art, sounds, name, layout or look. A rep driving a game is a
mechanic, not anyone's property. Every concept below is built from Azm's
own Design System (green brand, glass, Inter/Cairo) and Azm's own logo
figure language, and **no concept has a fail state**: a round always ends
on time or on the target rep count, never on a mistake.

## What exists today (checked 2026-11-12, `main` at 4ed3cba)
- **Camera:** only the QR scanner (`lib/features/gym/presentation/scanner_*`)
  through `mobile_scanner` 7.5.0. Its pattern is reused: the camera widget
  is a provider (`scannerCameraBuilderProvider`) that tests replace;
  `CameraProblem.denied | unavailable`; "Open settings" through
  `app_settings` 9.0.1; the camera is asked for only when that screen
  opens. `mobile_scanner` cannot give frames to a pose model (it returns
  only barcodes and, optionally, a JPEG), so a second camera plugin is needed.
- **Permissions:** `NSCameraUsageDescription` in `Info.plist` and
  `ios/Runner/{en,ar}.lproj/InfoPlist.strings` ("…only to scan your gym's
  QR code…": **must change**); Android `CAMERA` with
  `uses-feature camera required=false`. `test/security/platform_config_test.dart`
  fails on any other sensor/storage permission and on a camera feature
  without `required=false`.
- **Exercises:** `ExerciseCatalog.all` (36 exercises, `LibraryExercise`:
  both names, muscle, equipment, 2–3 steps) and `ExerciseUnit.reps`
  ("Reps only: body weight, abs"). There is **no push-up** in the catalog.
  Pictures are Everkinetic line drawings (CC BY-SA 4.0,
  `docs/features/exercise_images.md`); the same source has `push-ups-1/2.png`
  and `pull-ups-1/2.png` (commit `446bb9a`).
- **History:** `WorkoutSession {dayId, finishedAt, sets, membershipId?,
  startedAt?}`, `LoggedSet {exerciseId, weight, reps}`. Three side effects
  matter here:
  1. `GetNextWorkout` picks the next plan day from the **last** session's
     `dayId`; an unknown `dayId` gives index −1 → **day 1**. A push-up
     round saved as its own session would reset the member's rotation.
  2. `WorkoutRepository.saveSession` **clears the chosen day**.
  3. `GetLevel`: a week is active with **3 finished workouts**, so three
     one-minute rounds would make an active week.
  Gym sessions upload with `day_id` (`^[A-Za-z0-9_-]{1,64}$`); the
  dashboard's progress view keeps a `day_id` only if it matches its plan id
  pattern. Logged reps are clamped to `0..999`
  (`ActiveWorkoutController.maxReps`); the server refuses `reps > 1000`.
- **Workout pill:** hidden on `/`, `/workout` and `/join*`
  (`workout_pill_host.dart`); every other screen shows it.
- **Flags:** `Flags.gymJoin`, `Flags.gymBrandColours`; PostHog flags with
  local overrides.
- **Audio:** none in the app (the rest alarm uses notifications). No
  wakelock package.
- **Open PRs:** only Dependabot `flutter_local_notifications` 23.0.0
  ([3shmawi/gym_tracker#66](https://github.com/3shmawi/gym_tracker/pull/66)).
  Nothing overlaps.

## Decisions

### 1. Where it lives in the app
- **Entry points** (flag on): a compact **"Move" card on Today**, below the
  level card ("Push-up game · 1 min"), and a **"Move"** row in the home menu
  sheet. No new tab: the app has no tab bar, and Move is an extra, not the
  core loop. The card is hidden while a workout is in progress (the home
  button says "Continue workout" then; one call to action at a time). The
  menu row stays.
- **Routes** (`AppRoutes`, registered in `app_router.dart`, documented in
  `docs/deep_links.md`):

| Path | `name:` | What | Camera |
|---|---|---|---|
| `/move` | `move` | Hub: exercises (push-ups now), your best per round, "How it works" | never |
| `/move/:exercise` | `move_setup` | Setup: form tip (first time) → "why" screen → permission → placement guide | only after the member taps **Start camera** |
| `/move/:exercise/play` | `move_play` | The round (game + HUD), pause, results | yes, but **only when opened from setup in the app** |
| `/move/:exercise/count` | `move_count` | Manual counter round (no camera) | never |

- **Deep links never open the camera.** `/move/:exercise/play` requires a
  `MoveLaunch` object in `GoRouterState.extra`, which only the setup screen
  creates (a link cannot carry `extra`). Without it the route redirects to
  `/move/:exercise`. An unknown `:exercise` redirects to `/move`. Flag off:
  every `/move*` path redirects home. `/move/:exercise` shows the "why"
  screen and waits for a tap. It never asks for the permission on its own.
- **The workout pill is hidden on `/move*`** (added to the hidden-paths
  check in `workout_pill_host.dart`). A workout in progress keeps its
  draft and rest timer; leaving Move shows the pill again.
- The results screen is not a route (it shows round data, which a link
  must not be able to fake); it is a state of `move_play` / `move_count`.

### 2. The push-up game: three original concepts (pick one)
All three share the same round rules (section 3) and the same HUD (glass
timer, rep count, pause). They differ only in what a rep builds. Each is
drawn in the mockup.

| | **A · Stack** (recommended) | B · Summit | C · Charge |
|---|---|---|---|
| A rep… | drops one glass block onto a tower | moves a green glass climber up one ledge of a terraced hill | adds one ring of light to a glass orb; every 5 rings it releases a pulse that lights one star of a constellation |
| Good form shows as | a **full, centred** block (deep rep), a soft green rim (steady tempo) | a higher step for a deep rep | a brighter ring for a deep, steady rep |
| Half rep | a ghost outline appears and fades ("go lower"); no block | the climber crouches, doesn't step | the ring flickers and fades |
| Too fast | no block; "slow down" chip | no step | no ring |
| Score | floors (reps) + steady bonus | metres climbed | stars lit |
| Reduce Motion | blocks appear in place (150 ms fade), no sway | the climber appears on the next ledge | rings appear, no pulse |
| Fits later exercises | any rep → a block | pull-ups = climbing fits; squats less | any rep |
| Build cost (Flame) | lowest: rectangles + one easing | medium: figure + scrolling hill | medium: shader-like rings |

**Recommendation: A · Stack.** It rewards form in a way you can see
(depth = a solid centred block, half reps leave nothing), it works for every
future exercise without new art, it reads well from 2 m away (one tall
shape), it is the cheapest to draw and test, and it is the furthest from
the game that inspired the idea (no flight, no obstacles, no fail state).
In Arabic the game is **«البُرج»**, in English **"Stack"**. The final names
are copy, decided with the concept.

### 3. Round rules (pure Dart, `domain/games/`)
- **Round kinds:** `timed(30 s)`, `timed(60 s)` (default), `target(10)`,
  `target(20)` reps. A round ends on time or on the target, never on a
  mistake. A 3-2-1 countdown (spoken by the screen reader, shown big)
  starts it once the body is in position.
- **Tempo:** a counted rep needs at least **0.7 s** from top to top (the
  detector's `minRepDuration`). A rep of ≥ **1.4 s** earns the **steady
  bonus** (+1). No other difficulty levels in v1: the difficulty is the
  member's own strength.
- **Score** = reps + steady bonuses. **Saved reps = reps only** (bonuses
  are game points, not training).
- **Personal best** per exercise and round kind, kept on the phone
  (`MoveRecordsRepository`, shared preferences, tiny). Shown on the hub and
  the results; never pushed ("Beat your best!" banners are not used).
- **Pause:** a pause button (48×48, glass), app going to background, the
  body leaving the frame for > 1.5 s, or a phone call: the round timer
  stops. Resume always counts down 3-2-1 again.
- `GameRules` is an interface: `GameState onEvent(RepEvent)`,
  `GameState onTick(Duration)`. `StackRules` implements it. Flame only
  **draws** a `GameState`; all logic is unit-tested without Flame.

### 4. Rep detection (the core, pure Dart)

#### 4.1 Types (`domain/`)
```dart
/// The 13 joints the detectors use (ML Kit / BlazePose ids in the data layer).
enum PoseJoint { nose, leftShoulder, rightShoulder, leftElbow, rightElbow,
  leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee,
  leftAnkle, rightAnkle }

/// One joint, normalised to the image: x, y in 0..1 (y down), already
/// un-mirrored and upright. [likelihood] is ML Kit's in-frame likelihood.
class Landmark { final double x, y, likelihood; }

/// One processed camera frame. [at] is the frame's own timestamp, so
/// replaying a recording is deterministic. [joints] may miss joints.
class PoseFrame { final Duration at; final Map<PoseJoint, Landmark> joints;
  final double aspect; /* width / height of the image */ }

abstract interface class PoseSource {
  Stream<PoseFrame> get frames;            // ≤ 15 per second
  Stream<PoseSourceStatus> get status;     // starting, running, slow, failed(problem)
  Future<void> start();                    // asks for the camera (once)
  Future<void> stop();                     // releases camera + model
}

abstract interface class RepDetector {
  MoveExerciseId get exercise;
  /// Feeds one frame; returns the live state and any events it produced.
  RepUpdate onFrame(PoseFrame frame);
  void reset();
}

class RepUpdate { final RepState state; final List<RepEvent> events; }

class RepState {
  final RepPhase phase;    // notVisible, ready, goingDown, bottom, goingUp
  final double depth;      // 0 = top, 1 = full depth (for the live UI)
  final int reps;
  final PoseView? view;    // side, front (null until known)
}

sealed class RepEvent {}
final class RepCounted extends RepEvent { int total; Duration took; double depth; }
final class HalfRep extends RepEvent { double depth; }        // not counted
final class TooFast extends RepEvent { Duration took; }        // not counted
final class BodyLost extends RepEvent {}                       // → pause
final class BodyFound extends RepEvent {}
final class FormHint extends RepEvent { FormHintKind kind; }  // straightBody, moveBack, moveCloser, moreLight
```
Only detectors and rules know about joints. Screens see `RepState` and
`RepEvent`; the game sees only events.

#### 4.2 Shared machinery (`RepCycle`)
Every exercise is "a signal that goes from rest to a peak and back", so
the state machine is shared and each detector only provides the **signal**
and its checks:

- **Signal** `s(frame) → 0..1` (0 = rest position, 1 = full rep), or null
  when the needed joints are not visible.
- **Smoothing:** a one-euro filter on `s` (min cutoff 1.0 Hz, beta 0.05;
  starting values), and a frame whose `s` jumps by > 0.5 from the last one
  in < 100 ms is dropped as a glitch.
- **Hysteresis:** `ready → goingDown` when `s > 0.25`; `bottom` when
  `s ≥ 0.80`; `goingUp` after `bottom` when `s < 0.70`; **a rep is counted**
  when `s ≤ 0.20` again after `bottom`.
- **Half rep:** back to `s ≤ 0.20` with a peak in `0.40..0.80` → `HalfRep`.
  Peaks under 0.40 are ignored (breathing, shifting).
- **Too fast:** top-to-top under `minRepDuration` (0.7 s) → `TooFast`,
  not counted.
- **Visibility:** if the signal is null for > 1.5 s → `BodyLost`
  (`notVisible`); the round pauses. Back for 0.5 s → `BodyFound`.
- All thresholds are named constants in one `RepTuning` object per
  detector, so tests and tuning change one place.

#### 4.3 `PushUpDetector`
- **View:** decided over the first 10 visible frames and re-checked every
  2 s: `shoulderWidth / torsoLength < 0.35` → **side**, else **front**
  (both ratios of body parts, so body size does not matter).
- **Side view** (recommended placement): the **near arm** is the side whose
  shoulder, elbow and wrist have the higher mean likelihood (≥ 0.5).
  `s = (165° − elbowAngle) / (165° − 90°)` clamped to 0..1: straight arms
  = 0, elbow at 90° = 1 (full depth). Both shoulders must be in frame; the
  far arm may be hidden by the body. Works facing left or right. Hint
  `straightBody` when shoulder-hip-ankle < 150° for 1 s (advice only).
- **Front view** (phone on the floor in front of the head): the elbow angle
  is foreshortened, so the signal is the **shoulders' height above the
  wrists**, divided by shoulder width:
  `h = (wristY − shoulderY) / shoulderWidth`. The top `h₀` is learned while
  the member holds the plank during the placement step (and refreshed by
  the max of the last 3 tops). `s = (h₀ − h) / (0.6 · h₀)` clamped. **Both
  arms** (shoulder, elbow, wrist) must be visible.
- **Distance hints:** subject height (nose to ankles, or shoulders to wrists
  in front view) < 25 % of the image → `moveCloser`; any needed joint at the
  image edge (< 3 %) → `moveBack`; mean likelihood < 0.5 with joints present
  for 2 s → `moreLight`. ML Kit wants the person at least 256×256 px in the
  frame; at 480p that is about half the frame height.
- **Knee push-ups** count too (the detector only uses the arms and the
  torso). The catalog entry stays "Push-ups"; a variant is not asked in v1.
- **Thresholds are starting values.** PR 1 tunes them on recordings
  (section 13) and freezes them in tests.

**Phone placement guide (push-ups):** phone **on the floor, leaning on
something, screen facing you, about 1.5–2 m to your side**, at chest height
on the floor, landscape or portrait. The whole body from head to feet in
the frame. Front view (phone ~1 m in front of your head) is supported as a
fallback when there is no room at the side.

#### 4.4 How later exercises plug in
`MoveExercise` is a registry entry; nothing else is per exercise:
```dart
class MoveExercise {
  final MoveExerciseId id;            // 'push_ups', later 'pull_ups', …
  final String catalogExerciseId;     // the library exercise saved to history
  final RepDetector Function() detector;
  final PlacementGuide placement;     // picture + 3 lines + required joints
  final List<RoundKind> rounds;
  final MoveGameId defaultGame;       // 'stack'
}
```
- **Pull-ups:** `PullUpDetector` on the same `RepCycle`: signal from the
  **chin (nose) height relative to the wrists** (above the bar = 1) and the
  elbow angle (straight arms at the bottom = 0); front view only; the phone
  stands on the floor **2.5–3 m in front of the bar**, tilted up, bar and
  whole body in view; "body lost" is common when people step under the bar,
  so the countdown starts only after 1 s of a dead hang. Placement guide
  changes; the Stack game is reused as is (a rep is a block). A second game
  (e.g. B · Summit as a climb) is optional. Catalog: add `pull_ups`
  (Everkinetic `pull-ups-1/2.png`, `unit: reps`, muscle back, equipment
  bar).
- **Squats:** hip height relative to knee + knee angle; side or front.
- **Jumping jacks:** wrists above the head and ankles apart → 1; together →
  0.
- **High knees:** each knee above hip height alternately (one rep per knee).
- **Plank:** not a rep: `HoldDetector` (same interface; "reps" = seconds
  held with a straight body). The `RepState.reps` field is reused as
  seconds; rules for a hold game are a separate `GameRules`.
- **Nothing in the push-up design blocks these:** joints are already
  the full set; the camera is the front one, but `PoseSource` takes a
  `CameraFacing` so a later exercise could use the back camera; placement,
  rounds and the catalog link are per exercise.

### 5. Setup flow (`/move/:exercise`)
1. **Form tip** (first time per exercise, then from a "?" button): three
   short lines and the exercise picture ("Hands under shoulders, body in one
   line, chest close to the floor, then all the way up. Slow is better than
   fast. Stop if anything hurts.").
2. **"Why" screen** (only if the camera was never granted to Move on this
   phone): what the camera does, "**nothing is recorded, saved or sent**",
   buttons **Start camera** and **Count by hand instead**. Tapping Start
   camera triggers the system prompt. The camera plugin cannot read the
   permission state without asking, so the app keeps a local
   `move.cameraGranted` flag after a first successful start. With the flag
   set, this screen is skipped.
3. **Denied:** explanation, **Open settings** (`app_settings`, as the
   scanner) and **Count by hand**. iOS "restricted" (Screen Time) shows the
   same screen without Open settings. On Android "don't ask again" the
   system no longer prompts, so the screen is the same.
4. **Unsupported** (no front camera, the pose model fails to load, or the
   phone is too slow: section 9): "Camera games don't work on this phone"
   + **Count by hand**. The hub still shows Move; nothing is hidden.
5. **Placement guide:** the live camera preview (full screen, mirrored like
   a mirror) with the detected joints drawn as small green dots and thin
   lines on top of the member's real image, a picture of where to put the
   phone, and **live checks** that turn green
   one by one: "Whole body in view", "Both arms visible" (front) / "Side
   view found", "Good light", "Get into plank position". When all are
   green for 1 s the 3-2-1 starts by itself (no tap needed: the member is on
   the floor). Hints from the detector (`moveBack`, `moveCloser`,
   `moreLight`) show as one chip at a time and are spoken by the screen
   reader.
6. **During the round** the preview shrinks to a 96×128 glass corner chip
   (top start) with the dots, so the member can still see if they drift.
   Long-press hides it.
7. **Body leaves the frame** > 1.5 s → paused ("Come back into view"); back
   → 3-2-1 → continue. Pausing never loses counted reps.
8. **App to background / screen locked / call** → round paused, camera and
   model released at once (the `camera` plugin leaves lifecycle handling to
   the app: dispose on `inactive`, re-create on resume). On return:
   the pause screen with **Resume** (3-2-1) and **End round**.
9. The screen stays awake during a round (iOS idle timer off, Android
   `FLAG_KEEP_SCREEN_ON`) through a ~20-line platform channel in
   `core/screen_awake/`; no wakelock package for one flag. It is turned off
   again on pause, end, or leaving the screen.

### 6. Manual counter (`/move/:exercise/count`)
The same round kinds, results and saving, with no camera:
- The lower ~60 % of the screen is one big tap target ("Tap after each
  rep"), a large live number above it, a smaller "−1" button (48×48+) for
  mistakes, the round timer and pause in the bar.
- Each tap: light haptic, the number updates, and the count is announced
  (live region) so screen-reader users hear it. With a screen reader on,
  the whole target is one button "Add one rep, 7 so far".
- The game is not shown in manual mode (the game rewards camera-checked
  form; a tap counter would reward tapping). The result says "counted by
  hand"; reps are saved the same way.
- It is reachable from the hub, the why screen, the denied and unsupported
  screens, and the pause screen ("Switch to counting by hand" keeps the
  reps so far).

### 7. Accessibility
- **Screen reader:** the camera round is usable: the HUD is real Flutter
  widgets (not drawn in Flame), the rep count is a live region ("7 reps"),
  placement checks and hints are announced, the game canvas is one image
  with a label ("Stack: 7 floors"). The manual counter is the recommended
  path and is offered first when a screen reader is on.
- **Spoken count for everyone** (useful when you are on the floor 2 m away)
  is **not** in v1: it needs a TTS dependency or recorded numbers in two
  languages (decision 7). v1 plays a short sound per rep and a different
  one per 5.
- **Large text:** HUD and screens pass `screensUiTests` at 1.3; the
  results card scrolls.
- **Contrast:** HUD text sits on glass with the busiest camera preview
  behind it in tests; lite mode (Reduce Transparency) draws solid surfaces.
- **Reduce Motion:** no falling, sway, pulses or particles; things appear
  in place with a 150 ms fade. The 3-2-1 is a number change, not a zoom.
- **RTL:** the HUD and every screen mirror; the game world does not (a
  tower is symmetric; the corner preview moves to the start edge).
- **Both languages:** every string in `app_en.arb` and `app_ar.arb`;
  numbers stay Western digits as in the rest of the app.
- **Haptics:** manual counter taps only (in camera mode the phone is on the
  floor; vibration would move it).

### 8. Saving to training history
- **Catalog:** add **Push-ups** to `ExerciseCatalog.all`: id `push_ups`,
  `LocalizedName(ar: 'ضغط', en: 'Push-ups')`, muscle chest, equipment body
  weight (a new `Equipment.bodyweight` value if none fits), `unit: reps`,
  3 steps in both languages; picture from Everkinetic `push-ups-1/2.png`
  (commit `446bb9a`, CC BY-SA 4.0, attribution on the licenses page, the
  same pipeline as the other 36: `docs/features/exercise_images.md`).
- **Offer:** the results screen shows the reps and **Save to my training**
  (primary) / **Not now**. Rounds with 0 reps have no save button.
  Saving is never automatic (a round can be play-testing or a child
  playing).
- **What is saved: its own session**, not added to today's workout:
  `WorkoutSession(dayId: 'move', finishedAt: now, startedAt: roundStart,
  sets: [LoggedSet(exerciseId: 'push_ups', weight: 0, reps: n)])`, `n`
  clamped to `0..999` (the same as the workout logger). Two rounds in one
  sitting (within 30 min) are **merged into one session** with two sets,
  so history does not fill with one-set sessions.
  - Why not "add to today's workout in progress": the active workout shows
    only the plan day's exercises, so a push-up set would be invisible
    there, and it would mix a game with the planned session. It can be
    added later.
- **Side effects fixed in the same PR:**
  1. `GetNextWorkout` uses the last session **whose `dayId` is in the
     plan**; `move` sessions never move the rotation.
  2. A new `WorkoutRepository.saveExtraSession(session)` that does **not**
     clear the chosen day (or a `keepChosenDay` flag; one place).
  3. `trainedToday` ignores `move` sessions (a push-up round doesn't mean
     "today's plan is done").
  4. **Level:** `move` sessions count, but **at most one per day**, and
     only with ≥ 20 reps that day. Three one-minute rounds then cannot make
     an active week alone (decision 4).
  5. **Progress / exercise history:** push-ups show like any exercise
     (reps only, no weight), from both Move and normal workouts.
  6. **Backup / gym:** the session is saved in the current workspace like
     any workout. In a gym it uploads with the membership (the captain sees
     extra training). The dashboard labels `day_id = 'move'` as "Move"
     instead of a missing plan day (a small dashboard change + test, in
     PR 2; decision 5).
- **Exercise id stability:** `push_ups` and `move` are reserved ids, never
  reused (`exercise_catalog_test.dart` already checks id uniqueness).

### 9. Performance and devices

**Choice of pose model: Google ML Kit Pose Detection** through
`google_mlkit_pose_detection` 1.0.2, **base model, stream mode**.

| Option | Verdict |
|---|---|
| ML Kit Pose (`google_mlkit_pose_detection` 1.0.2, MIT, published 2026-11-10; ML Kit `pose-detection` 18.0.0-beta5) | **Chosen.** On-device, 33 landmarks + in-frame likelihood, stream mode tracks one person, Android + iOS, the most used Flutter plugin. ~30 fps on Pixel 4, ~45 fps on iPhone X (base). Beta API. |
| MediaPipe Pose Landmarker via `flutter_mp_pose_landmarker` 0.1.8 / `flutter_pose_detection` 0.4.1 / `vision_ai_pose` | Rejected for now: 0.x, one maintainer each, low platform scores, one needs R8 off, one installs from GitHub. Official MediaPipe has no Flutter plugin. Revisit if size (below) is not acceptable, as our own thin plugin. |
| Server-side / cloud pose | Rejected: frames would leave the phone. |

- **Camera:** `camera` 0.12.2 (published 2026-10-27; CameraX on Android
  0.7.6+1, AVFoundation on iOS 0.11.1), **front camera,
  `ResolutionPreset.medium` (≈ 640×480 / 720×480)**: ML Kit asks for at
  least 480×360 and a 256×256 subject; higher costs battery for nothing.
  Formats: NV21 (Android), BGRA8888 (iOS), `enableAudio: false`.
- **Throttle:** one frame in the model at a time; frames arriving while it
  is busy are **dropped** (Google's own advice); processing is capped at
  **15 fps**. The detector works from **8 fps** (a 0.7 s rep still has ≥ 5
  frames).
- **Device check, at run time, not by model list:** during placement the
  source measures the processed fps over 3 s. Median **< 8 fps** → the
  "unsupported: too slow" state with the manual counter. 8–12 fps → works,
  the corner preview is turned off to save GPU.
- **Minimum OS:** the app's own: **iOS 15** (ML Kit plugin also 15.0) and
  **Android 8 / API 26** (ML Kit needs 23; the camera plugin 24). 64-bit
  only on iOS (ML Kit has no armv7). Not supported: the iOS simulator for
  real inference (ML Kit needs a device), so CI and the demo use the
  recorded source (section 13).
- **Low-end Android to measure early (PR 1):** a staging-only diagnostic
  screen (flag `move_games_debug`) shows fps, frame time and the live
  signal. The owner runs it on the cheapest Android at hand (target class:
  Helio G36 / Unisoc T606, 3–4 GB RAM) and on the oldest iPhone at hand.
  Results go in `docs/performance.md`. If the cheap Android can't reach
  8 fps at 480p, try 352×288 before narrowing support.
- **Battery / heat:** rounds are ≤ 2 min, camera and model are released
  on pause and at the end, no preview processing outside a round or
  placement. Budget: a 60 s round ≤ 1 % battery on a mid-range phone
  (measured in PR 1).
- **App size (the biggest cost):** the plugin links **both** ML Kit models.
  Google's figures: Android base **+10.1 MB**, accurate **+13.3 MB**;
  iOS base **up to +29.6 MB**, accurate **up to +33.2 MB**. Plan:
  - Android: exclude `pose-detection-accurate` in Gradle
    (`configurations.all { exclude … }`, plus the R8 keep/dontwarn rules)
    → about +10 MB per download (Play splits by ABI).
  - iOS: the model files come as resource bundles that the app copies in
    by hand (the plugin's README: SwiftPM can't bundle them). Copy only
    `MLKitPoseDetectionFastResources`, `…CommonResources` and
    `MLKitXenoResources`, **not** `…AccurateResources`. A script downloads
    them from the pinned `d-date/google-mlkit-swiftpm` **9.0.2** release
    and **checks SHA-256 sums committed in the repo** before Xcode uses
    them (third-party repackaging of Google's binaries: pinned + verified,
    `docs/security.md`).
  - PR 1 measures the real growth with `flutter build appbundle
    --analyze-size` / `ipa --analyze-size` and writes it here. If iOS grows
    by more than ~25 MB, the owner decides between accepting it and our own
    thin MediaPipe plugin (decision 2).
- **Flame:** `flame` 1.38.2 (2026-08-27, needs Flutter ≥ 3.41; the project
  is on 3.47.8). Only the core package; no `flame_audio` unless decision 6
  says so.

### 10. Safety
- The form tip before the first round (section 5.1) and from "?" any time.
- "Slow is better than fast": too-fast reps don't count, and the steady
  bonus rewards slow reps; there is no bonus for speed.
- Half reps don't count and leave nothing in the game.
- **No streaks, no daily targets, no notifications** about Move. The
  personal best is shown, never pushed. The round is at most 2 minutes;
  after a round, results suggest "Rest a minute before another round".
- "Stop if anything hurts" is on the form tip and the pause screen.
- The game never has a fail state that would push someone to rush.

### 11. Privacy

**Frames:** processed in memory on the phone, frame by frame, and
discarded. Nothing is recorded, written to disk, sent, or kept: not the
image, not the landmarks. Only the number of reps the member chooses to
save is stored, as an ordinary set. The preview is only drawn on screen.
Landmarks never go into analytics, Sentry breadcrumbs or logs (a test
checks the move code for `print`, `debugPrint`, `Monitoring.addBreadcrumb`
with landmark data, and file writes).

**ML Kit metrics (must be disclosed):** Google's ML Kit terms (last
modified 2025-05-14) say images and results stay on the device, **but the
APIs send usage metrics to Google**: device information (manufacturer,
model, OS, available ML accelerators), app package and version, a
per-installation identifier, performance metrics (latency), API
configuration (image format, resolution), input/output size, event types
and error codes; pose detection also uses Firebase installations and
remote config for that. "You are responsible for informing users."
Google states it does not transfer this data to third parties. There is no
documented opt-out.

**`website/privacy.html`**: replace the Camera bullet under "Gym accounts"
with a new section after "Notifications":

English:
> **Move games (camera)**
> Move games use your phone's front camera to count your reps. The camera
> image is analysed on your phone, frame by frame, and thrown away at once:
> it is never recorded, saved or sent, and neither are the body positions
> worked out from it. Only the number of reps you choose to save is kept,
> like any set you log. The camera is used only while a Move game is open,
> after you tap "Start camera". You can always count by hand instead.
> The body-position detection is Google ML Kit, which runs on your phone.
> ML Kit sends Google technical usage data (device model and OS, app
> version, a random per-install identifier, speed and error codes), never
> the image or the result. The QR scanner also uses the camera only on your
> phone, to read the gym's code.

Arabic:
> **ألعاب الحركة (الكاميرا)**
> ألعاب الحركة بتستخدم الكاميرا الأمامية بتاعة موبايلك عشان تعدّ العدّات.
> صورة الكاميرا بتتحلل على موبايلك صورة بصورة وبتتمسح في نفس اللحظة: عمرها
> ما بتتسجل ولا بتتحفظ ولا بتتبعت، ولا أوضاع الجسم اللي بتتحسب منها. اللي
> بيتحفظ بس هو عدد العدّات اللي انت تختار تحفظه، زي أي مجموعة بتسجلها.
> الكاميرا بتشتغل بس وانت فاتح لعبة حركة، بعد ما تدوس «شغّل الكاميرا».
> وتقدر دايمًا تعدّ بإيدك بدلها.
> التعرّف على وضع الجسم بيتم بـ Google ML Kit، وبيشتغل على موبايلك. ML Kit
> بيبعت لجوجل بيانات استخدام تقنية (موديل الجهاز ونظام التشغيل، إصدار
> التطبيق، رقم عشوائي خاص بالتثبيت، السرعة وأكواد الأخطاء)، وعمره ما بيبعت
> الصورة أو النتيجة. ماسح الـ QR كمان بيستخدم الكاميرا على موبايلك بس، عشان
> يقرا كود الجيم.

**Camera permission text** (`Info.plist` + `InfoPlist.strings`; Apple
wants the purpose stated clearly):
- en: "Azm uses the camera to scan your gym's QR code and, in Move games,
  to count your reps on your phone. Nothing is recorded, saved or sent."
- ar: "عزم بيستخدم الكاميرا عشان يقرا كود الـ QR بتاع الجيم، وفي ألعاب
  الحركة عشان يعدّ عدّاتك على موبايلك. مفيش حاجة بتتسجل أو بتتحفظ أو
  بتتبعت."

**Android manifest:** the `camera_android_camerax` plugin merges
`RECORD_AUDIO`, `WRITE_EXTERNAL_STORAGE` (≤ API 28) and
`uses-feature android.hardware.camera.any` (required) into the app.
The app manifest removes both permissions (`tools:node="remove"`) and
overrides the feature to `required="false"` (`tools:replace`), so the app
still installs on phones without a camera and never asks for the
microphone. `platform_config_test.dart` checks the **merged** manifest of
a release build for this (today it reads the source manifest; extend it).

**Store forms** (`store/privacy_forms.md`, `docs/release.md`):
- Apple App Privacy: on-device processing is not "collected". ML Kit's
  metrics fall under **Diagnostics → Performance Data / Other Diagnostic
  Data** (already declared for Sentry: add ML Kit as a source). Whether
  ML Kit's per-install id also needs **Identifiers → Device ID** (declared
  today for PostHog) is to be checked against Apple's definitions in PR 4
  and recorded there. Camera: nothing to declare (not collected).
- Google Play Data safety: data processed only on the device is not
  collected. SDK data counts as the app's: **App info and performance →
  Diagnostics** (already declared) and **Device or other IDs** (already
  declared) get ML Kit added as a source. Photos/videos stay **not
  collected**.

**Analytics** (PostHog, no images, no landmarks, no personal data, buckets
instead of exact numbers):

| Event | Properties |
|---|---|
| `move_opened` | `source`: `home_card` / `menu` / `link` |
| `move_camera_answered` | `result`: `granted` / `denied` / `restricted` (once per ask) |
| `move_unsupported` | `reason`: `no_camera` / `too_slow` / `model_failed` |
| `move_game_started` | `exercise`, `game`, `mode`: `camera` / `manual`, `round`: `s30` / `s60` / `r10` / `r20` |
| `move_game_finished` | `exercise`, `game`, `mode`, `round`, `reps_bucket`: `0` / `1_5` / `6_10` / `11_20` / `21_40` / `41_plus`, `duration_bucket`: `lt_30s` / `30_60s` / `60_120s` / `gt_120s`, `ended`: `completed` / `quit` / `background`, `fps_bucket`: `lt_8` / `8_15` / `15_plus` (camera only) |
| `move_round_saved` | `exercise`, `mode` |

### 12. Architecture
```
lib/features/move/
  domain/
    entities/      pose_frame.dart, rep_event.dart, rep_state.dart,
                   move_exercise.dart, round_kind.dart, round_result.dart
    detectors/     rep_cycle.dart (shared machine + smoothing), geometry.dart,
                   push_up_detector.dart, rep_tuning.dart
    games/         game_rules.dart, stack_rules.dart (the chosen concept)
    repositories/  pose_source.dart, move_records_repository.dart
    usecases/      save_move_round.dart, run_round.dart (detector → rules → state)
    move_exercises.dart   the registry (push-ups only)
  data/
    mlkit_pose_source.dart    camera + ML Kit → PoseFrame (rotation, mirroring,
                              normalising, throttling, fps measure)
    landmark_mapping.dart     ML Kit PoseLandmarkType → PoseJoint
    local_move_records.dart
  presentation/
    move_hub_page/view, move_setup_page/view (tip, why, denied, unsupported,
    placement), move_play_page/view (HUD + GameWidget + pause + results),
    manual_counter_page/view, round_controller.dart (Notifier),
    move_providers.dart (poseSourceProvider: replaced in tests),
    game/stack_game.dart (FlameGame: draws GameState only),
    game/move_game_theme.dart (colours from context.palette)
```
- Domain is pure Dart (no Flutter, no Flame, no ML Kit). Presentation
  depends on domain only; `MlKitPoseSource` is wired in
  `core/di/dependencies.dart`.
- **Flame inside the app's UI:** `GameWidget` is the body of an
  `AppScaffold` page. The HUD, pause and results are Flutter widgets on top
  (Flame overlays or a `Stack`) built from `app_ui.dart`, so glass, RTL,
  fonts, l10n and `screensUiTests` work unchanged. The Flame world draws
  **no text** (no font or RTL issues in the canvas). Colours come from a
  `MoveGameTheme` built from `context.palette` (brand, brandTint, glass
  rims, text levels) and passed to the game; a theme or gym-colour change
  rebuilds it. Glass blocks are drawn with plain gradients and a rim (no
  shader), so lite mode and goldens are stable.
- **State:** `RoundController` (Riverpod `Notifier`) owns the round:
  `PoseSource` frames → `RepDetector` → `GameRules` → `RoundState`
  (phase, time left, reps, score, last event, game state). The Flame game
  and the HUD both read it.
- **Feature flag:** `Flags.moveGames = 'move_games'`, off by default; the
  hub, the card, the menu row and the routes check it. `move_games_debug`
  (staging only) enables the diagnostic screen.
- **Monitoring:** pose source errors go to `Monitoring.captureException`
  with the problem kind only.

### 13. Tests
- **Recorded sequences (no video in the repo):** the owner (and ideally a
  second person of a different size) films a few short push-up sets on
  their own phone: side left, side right, front, half reps, too fast,
  walking out of frame, bad light. A tool (`tool/pose_record/`, Python,
  MediaPipe Pose, the same 33-landmark topology as ML Kit) turns each video
  into landmark JSON **on the owner's computer**; only the JSON (joints +
  timestamps, no image) is committed under
  `test/fixtures/move/push_ups/`, with what each file should count. The
  videos are never committed. A staging-only "save landmarks" button on
  the diagnostic screen is the on-device alternative.
- **Synthetic sequences:** a test helper draws a stick figure through a
  push-up (arm length, tempo, depth, view angle, left/right, noise,
  dropped frames, jitter, body size ×0.6–×1.4) so every edge case is
  covered without recordings.
- **Unit:** `RepCycle`, `PushUpDetector` (good reps, half reps, too fast,
  body leaving, noisy landmarks, left/right/front, different sizes, garbage
  data: NaN, ±infinity, out-of-range coordinates, empty frames, frames out
  of order, a 10-minute stream), `StackRules`, `SaveMoveRound` (clamping,
  merge within 30 min, the rotation/chosen-day/level fixes), the
  controller with a fake `PoseSource`.
- **Widget:** every screen and state with `screensUiTests` (hub, tip, why,
  denied, unsupported, placement with each check state, countdown, playing,
  paused, body lost, results, manual counter), the game canvas with a fake
  source; goldens reviewed with `./scripts/ui_review.sh`.
- **Integration (demo):** a `RecordedPoseSource` replays a push-up set:
  open Move → placement turns green → play a 30 s round → results → Save →
  see push-ups in the exercise's history. Written with `beat(tester)`; it
  is the "Demo & post" video. On the simulator there is no camera, so the
  recorded landmarks are drawn as a **body**, not a stick figure: limbs,
  torso, head, hands and feet in the line-drawing style of the exercise
  pictures (outlined, light fill, shorts), with the dots on top. The
  same `PoseBodyPainter` draws the diagnostic screen. Asked by the owner
  on 2026-11-12 after seeing the mockup's stick figure.
- **Security:** `/move/push_ups/play` from a link never starts the camera
  (`deep_link_test.dart`); hostile `:exercise` values; permission denied /
  restricted / revoked mid-round; the merged Android manifest; no landmark
  data in logs or analytics; the model bundles' checksums.

### 14. Rollout and PR split
Each PR is safe alone; the flag stays off in prod until the owner turns it
on.

| PR | Contents | Visible? |
|---|---|---|
| 1 | Domain types, `RepCycle`, `PushUpDetector`, synthetic + recorded fixtures, `MlKitPoseSource` + `camera` + ML Kit (size trimming, manifest fixes, bundle checksums), the staging-only diagnostic screen, size and fps measured and written here | No (debug flag, staging only) |
| 2 | Catalog **Push-ups** (+ picture), hub, setup flow (tip, why, denied, unsupported, placement), **manual counter**, results, `SaveMoveRound` + the history fixes (rotation, chosen day, level, dashboard label), routes + deep-link tests, permission strings | Behind `move_games` |
| 3 | The chosen game (rules + Flame), HUD, pause, sounds (decision 6), integration demo | Behind `move_games` |
| 4 | Privacy page (both languages), store forms, `docs/features/move_games.md`, `docs/design.md`, `docs/security.md`, `docs/release.md`; flag on for staging | Staging |
| 5 (later) | Pull-ups (detector, placement, catalog), spoken count if chosen | — |

### 15. Docs to update with the code
`docs/features/move_games.md` (new, from `./scripts/new_feature.sh`;
rules, analytics events, Demo & post), `docs/README.md`,
`docs/features/exercise_library.md` and `exercise_images.md` (push-ups),
`docs/features/workout.md` (move sessions, rotation, level),
`docs/deep_links.md`, `docs/design.md` (mockup link, new components),
`docs/security.md` (camera, ML Kit, bundle checksums, merged manifest),
`docs/performance.md` (fps, battery, size), `docs/release.md` (pinned
versions, store forms), `store/privacy_forms.md`, `website/privacy.html`.

## As built: where it differs from this spec
PR 1 (2026-11-12):
- **Android size is +17.7 MB, not ~10 MB** (measured on a release build:
  ML Kit's native library 10.3 MB + models 5.8 MB + code; Google's 10.1 MB
  figure is too low). Universal APKs carry the library for 3 CPU types
  (+35 MB). `docs/performance.md` → Move games.
- **iOS is not wired yet.** The ML Kit model bundles (from the plugin's
  third-party SwiftPM mirror) and `-ObjC -all_load` need a Mac to set up and
  test; until then `MlKitPoseSource` reports "model unavailable" on iOS
  instead of calling ML Kit. A follow-up PR, before PR 2 ships to iOS.
- **Front view top:** the highest shoulder height of the last 6 s, not "the
  max of the last 3 tops" (same effect, no circular dependency on the
  cycle). The calibration needs no separate plank step.
- **ML Kit also brings WorkManager** (and its permissions); the merged
  manifest is cut down as described in `docs/security.md` → Move games.
- **The QR scanner already sends ML Kit metrics** (ML Kit barcode
  scanning): the privacy text in §11 is needed for today's app too, not
  only for Move games.
- The diagnostic screen is `/move/check` ("Pose check", Settings → About),
  not a separate debug flag screen elsewhere; recorded fixtures wait for
  the owner's videos (decision 9), synthetic sets cover every case meanwhile.

PR 2 (2026-11-12):
- **Two rounds are two sessions**, not one session with two sets: since
  #90 a session's id is a hash of its content and the phone's database
  never edits a workout, so "merge within 30 min" (§8) would mean
  deleting history. Each round is its own `move` session.
- The Move card sits **under the level card** on Today (below the fold on
  a phone); the menu row is the quick way in.
- Placement checks follow the detector's live `issues` (added to
  `RepState`), not its throttled hints.
- Until the game (PR 3), the running screen shows the time, a big rep
  count, the depth bar and the body in the corner.
- The integration demo runs headless too (`move_e2e_test.dart`), with a
  recorded synthetic set; real recordings still wait for decision 9.

PR 3 (2026-11-12):
- **The HUD is plain Flutter widgets in a `Stack`** around the
  `GameWidget`, not Flame overlays (Flame's docs allow either). The body
  preview and the rep count moved to a row above the game, so the tower
  never hides behind them; the depth bar is under it.
- **The engine pauses itself** when nothing moves (`pauseEngine` after an
  update with no animation, `resumeEngine` on a new state): no work while
  the member holds a plank, and widget tests and goldens settle.
- `GameRules` is `start()` + `onEvent(state, event, at)`, with no
  `onTick`: Stack has no rule in time. `MoveExercises.gameFor` picks the
  game per exercise; analytics name it (`game`: `stack` / `none`).
- **Sounds:** our own tones (`scripts/move_sounds.py`, CC0), two short
  WAVs (26 KB together) played from `flame_audio` pools. iOS uses the
  **ambient** audio session and Android asks for **no audio focus**, so the
  member's music keeps playing; Flame's default (`playback` +
  `mixWithOthers`) would ignore the silent switch. A **mute button** is in
  the round's bar (remembered); the spec had no mute, but a sound you
  can't turn off in a gym is a reason to stop playing.
- "Slow down" and "go lower" are notices above the tower for 2.5 s; they
  take the place of a form hint while shown (one message at a time).

PR 4 (2026-11-13):
- The privacy text is the §11 text, with the Arabic in the page's formal
  Arabic, and adds: the microphone is never used (the game's sounds are
  made on the phone), what ML Kit's data is used for (diagnostics, not
  shared with third parties, per Google), a link to the ML Kit terms, and
  that Move analytics are ranges only. The Camera bullet under "Gym
  accounts" stays and points to the new section.
- **Apple Device ID (the open question in §11):** Apple defines *Device ID*
  as a device-level id; ML Kit's per-installation id isn't one. It is listed
  under the *Device ID* row we already declare anyway (not linked,
  Analytics), the safer reading. Apple also gets *Other Diagnostic Data*
  and *Analytics* on *Performance Data*. Google Play needs no new type.
- The **terms** got "Training safely" (not in the spec): not medical
  advice, stop if anything hurts, phone stable and space clear, counts can
  be wrong.
- "Flag on for staging" is a PostHog setting, not code: the steps and the
  checklist before prod are in `docs/release.md` → "Move games flags".

PR 5, spoken count (2026-11-13):
- The sound button cycles count out loud → tones → off (the spec had only
  "spoken count later"). Counting out loud is the default; it replaces the
  tones while on, and falls back to tones on a phone with no offline voice
  for the language.
- The digits are passed as they are ("7"); an Arabic voice is expected to
  read them in Arabic («سبعة»), to be checked on a phone. Egyptian Arabic
  first when installed, any Arabic voice else.
- The privacy policy didn't change: it already says the game's sounds are
  made on the phone, and only offline voices are used.
iOS set-up (2026-11-13):
- The ML Kit bundles are committed (5.6 MB, base model only), not
  downloaded at build time: every build path (CI, release, Codemagic, a
  Mac) gets the same files with no network and no workflow change. They
  come from Google's archives, and their checksums are pinned.
- On the iOS Simulator the source reports "model unavailable" (the model
  needs the device's GPU), so the simulator offers the manual counter.
- Still to do on a real iPhone: the pose check, frames per second, and the
  IPA size (decision 2).

## Official docs checked (2026-11-12)
- pub.dev API: `flame` 1.38.2 (2026-08-27, Flutter ≥ 3.41; 1.38.0 had
  breaking input-event changes only), `camera` 0.12.2 (2026-10-27, Flutter
  ≥ 3.44; Android SDK 24+, iOS 13+; the app handles lifecycle itself),
  `camera_android_camerax` 0.7.6+1 (its merged manifest read from the
  archive), `camera_avfoundation` 0.11.1, `google_mlkit_pose_detection`
  1.0.2 + `google_mlkit_commons` 1.0.2 (2026-11-10, MIT, iOS 15.0, Android
  minSdk 21, links `pose-detection` and `pose-detection-accurate`
  18.0.0-beta5; iOS through `d-date/google-mlkit-swiftpm` 9.0.2 with four
  resource bundles copied by hand; "not maintained by Google"; inference
  needs a real device), `flame_audio` 2.12.2, `audioplayers` 6.8.1,
  `flutter_tts` 4.2.5, `permission_handler` 13.0.2 (not needed).
- **OSV** (api.osv.dev, 2026-11-12): no advisories for `flame` 1.38.2,
  `camera` 0.12.2, `camera_android_camerax`, `camera_avfoundation`,
  `google_mlkit_pose_detection` 1.0.2, `google_mlkit_commons` 1.0.2,
  `flame_audio` 2.12.2, `audioplayers` 6.8.1, `flutter_tts` 4.2.5.
- Google ML Kit Pose Detection overview, Android and iOS guides (33
  landmarks, in-frame likelihood, one person, face must be visible, base
  ~30 fps Pixel 4 / ~45 fps iPhone X, ≥ 480×360 input, ≥ 256×256 subject,
  drop frames while busy, sizes quoted in section 9).
- ML Kit terms (last modified 2025-05-14) and ML Kit Android data
  disclosure (2025-05-14): metrics sent to Google, quoted in section 11.
- Apple App Privacy Details: on-device-only processing is not "collected";
  third-party SDK data must be declared; Diagnostics categories.
- Google Play Data safety help: data processed only on the device isn't
  collected; SDK transmissions count as the app's.
- MediaPipe Flutter wrappers on pub.dev (section 9 table).
- **For PR 3 (2026-11-12):** pub.dev API again: `flame` 1.38.2,
  `flame_audio` 2.12.2 (2026-07-19), `audioplayers` 6.8.1 (2026-06-27,
  Flutter ≥ 3.44), `flame_test` 2.3.1 (not used); still the latest. OSV:
  no advisories for `flame` 1.38.2, `flame_audio` 2.12.2, `audioplayers`
  6.8.1, `audioplayers_android` 5.3.0, `audioplayers_darwin` 6.5.0,
  `audioplayers_linux` 4.3.0, `audioplayers_platform_interface` 7.2.0,
  `audioplayers_web` 5.3.0, `audioplayers_windows` 4.4.1, `ordered_set`
  8.0.1. Flame docs (docs.flame-engine.org/latest): *Overlays* (widgets
  can sit over the game without the Overlays API), *The game class*
  (`pauseEngine`/`resumeEngine`; transparent `backgroundColor()`),
  *flame_audio → General audio / AudioPool*. Sources read in the pub
  cache: `GameLoop`/`GameRenderBox` (a paused game still paints its last
  frame), `AudioContextConfig` (`respectSilence` would ask for audio focus
  on Android) and `audioplayers_android`'s manifest (no permissions).
- **For PR 4 (2026-11-13):** ML Kit Android data disclosure (last modified
  2025-05-14: bundled features send per-installation ids, not device ids;
  not transferred to third parties), ML Kit iOS data disclosure, Apple App
  privacy details (definitions of Device ID, Performance Data, Other
  Diagnostic Data), the ML Kit terms page (link checked). `mobile_scanner`
  7.5.0's Gradle file: bundled ML Kit barcode model unless
  `useUnbundled` is set (it isn't).
- **For PR 5 (2026-11-13):** pub.dev `flutter_tts` 4.2.5 (2026-01-05,
  latest; OSV: no advisories); its README (Android `<queries>` for
  `TTS_SERVICE`, iOS audio category), and its Android and iOS sources:
  `speak(focus: false)` takes no audio focus, voices report
  `network_required` and `features` (`notInstalled`), queue mode flush;
  iOS uses the app's shared audio session.
- **For the iOS set-up (2026-11-13):** `google_mlkit_pose_detection`
  1.0.2 README "Requirements → iOS" (iOS 15, Xcode 15.3, Swift 5.9, `-ObjC
  -all_load`, four bundles, inference needs a device), the plugin's iOS
  `Package.swift` (links both pose products; the model is picked at run
  time), `google_mlkit_commons` 1.0.2 (iOS ignores the rotation metadata),
  `camera_avfoundation` 0.11.1 (front frames rotated to the device
  orientation and mirrored), `d-date/google-mlkit-swiftpm` 9.0.2 README and
  `Package.swift`, the CocoaPods specs of `MLKitPoseDetection`,
  `MLKitPoseDetectionCommon` and `MLKitXenoCommon` 1.0.0-beta16.
- **Not re-read in this session, to read before the PR that uses them:**
  Apple's `NSCameraUsageDescription` page (the page didn't load its text;
  App Review 5.1.1(ii) on purpose strings), the `camera` plugin's image
  stream format docs.

## Decisions (approved 2026-11-12: concept A · Stack, and the recommended choice in each)
1. **Game concept:** A · Stack, B · Summit or C · Charge.
   *Recommended: A · Stack.*
2. **Pose model and app size:** ML Kit through
   `google_mlkit_pose_detection`, with the accurate model trimmed
   (≈ +10 MB Android, iOS to be measured, likely +20–30 MB).
   *Recommended: yes; if iOS grows by > 25 MB, decide again with numbers.*
3. **Save as its own "Move" session**, not added to today's workout.
   *Recommended: yes.*
4. **Level:** Move rounds count at most once a day and only with ≥ 20 reps
   that day. *Recommended: yes* (you asked for "counts in level like any
   workout"; this stops three 1-minute rounds from making an active week).
5. **Gym members:** Move sessions upload to the gym and the dashboard shows
   them as "Move". *Recommended: yes* (alternative: keep them solo-only).
6. **Sounds:** own short sounds (made by us, CC0, licence recorded) through
   `flame_audio`. *Recommended: yes, in PR 3.*
7. **Spoken count** ("one, two, three…" in Arabic and English) for when
   you're on the floor: later, with `flutter_tts`.
   *Recommended: later (PR 5).*
8. **Entry point:** a Move card on Today (hidden during a workout) + a row
   in the home menu. *Recommended: yes.*
9. **Recordings:** you film 4–6 short push-up sets (side left/right,
   front, half reps, too fast, walking away); only landmark JSON is
   committed. *Recommended: yes, before PR 1 is finished.*
10. **Devices:** iOS 15+ / Android 8+, with a run-time speed check
    (< 8 fps → manual counter), measured on your cheapest Android in PR 1.
    *Recommended: yes.*
11. Run the EGM review yourself before approving, or approve without it.
