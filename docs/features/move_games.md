# Feature: Move games

> Keep this page current — it is how a new developer or AI agent learns the feature.
> Spec (approved 2026-11-12, game concept A · Stack): [`../designs/move_games.md`](../designs/move_games.md).
> Mockup: https://claude.ai/artifact/V6dWNvw3rFaUKBtMoaeJ26

## What it does
Short camera-controlled exercise games. The phone's front camera watches
the member, an on-device pose model (Google ML Kit) finds their joints,
and a rep detector counts **real** push-ups; each rep drives an original
game ("Stack": every full rep places a block on a tower). Nothing about the
camera leaves the phone; only the reps the member chooses to save are kept.

**Built so far (PR 1, nothing visible in the store app):**
- The rep detection core, pure Dart: `RepDetector`, the shared `RepCycle`
  state machine and `PushUpDetector` (side view left or right, front view).
- `PoseSource` and its two implementations: `MlKitPoseSource` (front
  camera + ML Kit, Android) and `RecordedPoseSource` (replays landmark
  recordings: tests, the coming demo, the simulator).
- The **pose check**, a screen for testers only (staging/dev builds with
  the `move_games_debug` flag): start the camera, see the body the model
  sees, the frames per second and what the detector decides. It is how
  phones are measured before the games ship.

Next: PR 2 (catalog "Push-ups", hub, setup flow, manual counter, saving to
history), PR 3 (the Stack game), PR 4 (privacy, store forms, staging).

## User flows
**Pose check (testers):** Settings → About → *Pose check (testing)* →
*Start camera* (the system asks for the camera the first time) → put the
phone on the floor at your side, 1.5–2 m away → do push-ups. The screen
shows the reps, speed (frames/s), view (side/front), position, depth and the
last event or hint. *Stop* or leaving the app releases the camera.

## Architecture
- `lib/features/move/` (layered):
  - `domain/entities/`: `PoseFrame` (13 joints as fractions of the upright
    image + likelihood), `RepEvent` (counted, half rep, too fast, body
    lost/found, hints), `RepState`, `MoveExerciseId`.
  - `domain/detectors/`: `RepCycle` + `RepTuning` (shared by every future
    exercise), `PushUpDetector` + `PushUpTuning`, `OneEuroFilter`,
    `HintGate`, `geometry.dart`.
  - `domain/repositories/pose_source.dart`: the camera is behind this.
  - `domain/move_exercises.dart`: the registry (an exercise = a detector,
    later a placement guide and a catalog entry).
  - `data/datasources/`: `MlKitPoseSource`, `landmark_mapping.dart` (ML Kit
    → `PoseFrame`, Android rotation), `PoseRecording` (the JSON format),
    `RecordedPoseSource`.
  - `presentation/`: `MoveCheckPage` → `MoveCheckView`,
    `MoveCheckController` (Riverpod `Notifier`), `PoseBodyPainter` (draws
    landmarks as an outlined body in the exercise pictures' style, not a
    stick figure).
- Composition root: `Dependencies.poseSource` (a factory: one source per
  screen); presentation reads it through `poseSourceFactoryProvider`.
- Routes: `/move/check` (`move_check`), testers only. Opening it never
  starts the camera.

### How a push-up is counted
1. **Signal (0 = top, 1 = full depth).** Side view: the elbow angle of the
   arm the camera sees best (165° → 0, 90° → 1). Front view: how far the
   shoulders dropped towards the wrists, in shoulder widths, against the
   highest point of the last 6 s (a 60 % drop → 1). The view is the
   majority of the last 15 frames (shoulder width ÷ torso length < 0.35 →
   side; hips hidden → front).
2. **Cycle (hysteresis).** Top (≤ 0.20) → going down (> 0.25) → bottom
   (≥ 0.80) → going up (< 0.70) → back at the top: **one rep**, if it took
   ≥ 0.7 s top to top (else *too fast*). Back at the top without reaching
   the bottom, after going past 0.40: *half rep*. Smaller dips are ignored.
   The top must be seen before the first rep.
3. **Visibility.** Needed joints missing for 1.5 s → *body lost* (a rep in
   progress is dropped); visible again for 0.5 s → *body found*.
4. **Noise.** A 1€ filter smooths the signal; one wild frame is dropped.
   Frames out of order, NaN, infinities and absurd coordinates are ignored.
5. **Hints** (advice only, at most every 5 s): move back (a needed joint at
   the edge), move closer (body < 25 % of the picture), more light (every
   joint unsure), keep your body straight (side view, hips bent < 150°).

All numbers are in `RepTuning` / `PushUpTuning`: starting values, tested on
synthetic sets, to be tuned on recordings (below).

## Platforms and devices
- **Android 8+ (API 26, the app's minimum):** the live source works.
- **iOS:** the code and package are in, but `MlKitPoseSource` reports
  "model unavailable" on iOS (`iosModelInstalled = false`): ML Kit needs its
  model bundles copied into the Runner target and `-ObjC -all_load`
  linker flags (the plugin's README), which must be set up and tested on a
  Mac. Until then the pose check shows "The pose model can't run on this
  phone yet." ML Kit inference never runs on the iOS Simulator.
- Speed: measured with the pose check (`docs/performance.md` → Move games).

## Recordings (test fixtures)
`PoseRecording` stores **joints and times only, never an image**:
`{"version": 1, "aspect": 0.75, "frames": [{"t": ms, "j": {"leftShoulder":
[x, y, likelihood], …}}]}`. Decoding never throws (bad frames are skipped,
30,000 frames at most). Recorded fixtures from the owner's own videos go
in `test/fixtures/move/push_ups/` with the count each should give; the
videos themselves are never committed. Until then the detector is tested on
synthetic sets (`test/features/move/helpers/synthetic_pose.dart`: side
left/right and front, 8–30 fps, body size ×0.4–×1.4, noise, dropped
frames, gaps, half and rushed reps, sagging hips).

## Analytics events
None yet: the pose check is for testers and sends no events. The game's
events (`move_opened`, `move_camera_answered`, `move_unsupported`,
`move_game_started`, `move_game_finished`, `move_round_saved`) come with
PR 2 and 3 (spec §11). No images, landmarks or personal data, ever.

## Feature flags
- `move_games_debug`: the pose check. **Never in prod builds**, whatever
  the flag says (`moveCheckAllowed()`).
- `move_games`: the games (PR 2+).

## Tests
- Unit: `test/features/move/domain/detectors/` (`RepCycle`,
  `PushUpDetector`: views, speeds, sizes, noise, drops, half/rushed reps,
  leaving the picture, hints, garbage, a 10-minute set),
  `test/features/move/data/datasources/` (mapping, rotation, recordings,
  hostile JSON, replay), `move_check_controller_test.dart`.
- Widget: `move_check_view_test.dart` (states, the page never starts the
  camera by itself, leaving the app releases it, the body painter on
  garbage; `screensUiTests` for idle, side, front, denied, model failed).
- Security: `test/security/deep_link_test.dart` (`/move/check` from a link
  never reaches the page in prod or with the flag off, never makes a
  camera source), `platform_config_test.dart` (removed library
  permissions, optional camera, the accurate model left out).
- Integration: comes with the game (PR 3), as the demo below.

## Decisions & edge cases
- Approved spec: [`docs/designs/move_games.md`](../designs/move_games.md)
  (Stack game; the recommended choice in each decision).
- The camera is released when the app leaves the foreground (the camera
  plugin leaves lifecycle to the app), on Stop and when the screen closes;
  the camera goes off before the listeners are dropped.
- Only ML Kit's **base** model ships; the accurate one is excluded in
  Gradle (R8 is told its classes are missing on purpose).
- Measured app growth (Android, arm64, release, 2026-11-12): **+17.7 MB**
  installed (ML Kit native library 10.3 MB, models 5.8 MB, code); the
  spec's 10 MB was Google's figure and too low. Universal APKs (the staging
  pre-release) carry the native library for three CPU types: +35 MB.

## Demo & post
<!-- Filled when the game is done (PR 3). -->
**Hook (first 2 seconds):**
**Scenario:**
**Caption (English):**
**Caption (Egyptian Arabic):**
**Hashtags:** #flutter #buildinpublic
