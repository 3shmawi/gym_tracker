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

**PR 2 (behind `move_games`, off in prod):**
- The **Move** entry: a card on Today (under the level, hidden during a
  workout) and a row in the home menu.
- The hub, the form tip, "why the camera", the camera round (placement
  with live checks, 3-2-1, the round, pause, body lost, results) and the
  **manual counter** (the same rounds, no camera).
- **Saving** a round to training history as a set of the new library
  exercise **Push-ups**; the history fixes below.
- The captain's dashboard names a Move round and knows Push-ups.

Next: PR 3 (the Stack game in the running screen, sounds), PR 4 (privacy
page, store forms, flag on for staging), then iOS model set-up.

## User flows
**Camera round:** Today → *Move* card (or menu → *Move · rep games*) →
pick a round (30 s, 60 s, 10 reps, 20 reps) → *Play with the camera* →
the form tip (first time only) → "why the camera" (until the camera was
allowed once) → *Start camera* (the system asks the first time) →
placement: put the phone on the floor at your side, the checks turn green
(body in view, view found, light, plank held a second) → 3-2-1 by itself →
the round (time, reps, depth, the body in the corner, one hint at a time)
→ results (reps, steady reps, half reps, time, new best) → *Save to my
training* (never automatic) → *See progress*.

**Manual counter:** the hub (or any camera dead end) → *Count by hand* →
*Start* → 3-2-1 → tap the big target after each rep, *Remove one* for a
mistake → results → save, the same way.

**Paused:** the pause button, the body out of the picture for 1.5 s, or the
app leaving the front (the camera is released at once). Back in the
picture after a body-lost pause, 3-2-1 starts again by itself; otherwise
*Resume (3, 2, 1)*. *Switch to counting by hand* or *End round* keep the
reps done.

**Can't use the camera:** refused → *Open settings* or *Count by hand*;
no front camera, model can't run, or slower than 8 frames/s after 4 s →
"Camera games don't work on this phone" → *Count by hand*.

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

## Rules
- **Rounds:** `s30`, `s60` (default), `r10`, `r20`; no round lasts more
  than 2 minutes. A rep counts only while running; 3-2-1 before every
  start and resume. Steady rep = ≥ 1.4 s top to top (shown, not saved).
- **Saving:** its own session, `day_id` `move`, one set of `push_ups`,
  weight 0, reps clamped to 0..999 (like a logged set); a round with 0
  reps can't be saved; the chosen day is kept. Every round is its own
  session (sessions are immutable, see Decisions).
- **History:** Move sessions never move the plan on and never mark today
  as trained; for the level they count as one workout on a day with at
  least 20 reps in all (`GetLevel.moveRepsForLevel`); push-ups from rounds
  show in Progress even when push-ups is not in the plan; in a gym they
  upload like any workout, and the dashboard names them.
- **Best score** per exercise and round kind, on the phone (`move.best.*`
  in shared preferences, 1..999 only).
- **Screen on** during the camera round (`azm/screen_awake`), off at the
  end, on pause by background and when the screen closes.

## Analytics events
No images, landmarks or personal data, ever; counts and durations are
buckets (`MoveAnalytics`). The pose check sends none.

| Event | When | Properties |
|---|---|---|
| `move_opened` | the hub opens | `source`: `card`, `menu`, `link` |
| `move_camera_answered` | the camera was asked for (first time, or refused) | `result`: `granted`, `denied` |
| `move_unsupported` | the camera can't be used | `reason`: `no_camera`, `model_failed`, `too_slow` |
| `move_game_started` | a round starts (after 3-2-1 or Start) | `exercise`, `mode` (`camera`/`manual`), `round` |
| `move_game_finished` | a round ends | `exercise`, `mode`, `round`, `reps_bucket`, `duration_bucket`, `ended` (`completed`/`quit`), `fps_bucket` (camera only) |
| `move_round_saved` | *Save to my training* | `exercise`, `mode` |

## Feature flags
- `move_games_debug`: the pose check. **Never in prod builds**, whatever
  the flag says (`moveCheckAllowed()`).
- `move_games`: the Move card, the menu row and every `/move` screen;
  off, `/move` links open home.

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
- Rounds and saving: `test/features/move/domain/round_test.dart`,
  `save_move_round_test.dart`, `placement_test.dart`,
  `presentation/round_controllers_test.dart` (placement → round → results
  → saved; refused; too slow; background; body lost; 0 reps; saving once).
- Screens: `presentation/move_screens_test.dart` (`screensUiTests` for 19
  states: hub, tip, why, placement, 3-2-1, running side and front, paused,
  body lost, results, saved, refused, too slow, manual ready / running /
  paused / results).
- History: `get_next_workout_test`, `get_level_test`,
  `get_exercise_history_test` (Move groups).
- Security: `deep_link_test.dart` → `/move (Move games)`: a link to
  `/move/push_ups/play` lands on the tip, never the camera; hostile
  exercises and rounds; flag off → home.
- Demo: `integration_test/flows/move_flow.dart`, run on the simulator
  (`app_test.dart`) and headless (`test/features/move/move_e2e_test.dart`):
  a recorded synthetic set, ten push-ups counted by the real detector,
  saved, shown in history.

## Decisions & edge cases
- Approved spec: [`docs/designs/move_games.md`](../designs/move_games.md)
  (Stack game; the recommended choice in each decision).
- **Two rounds are two sessions**, not merged: a session's id is a hash of
  its content and the phone's database never edits a workout (spec §8
  said "merged within 30 min"; not possible without editing history).
- A link can open the hub, the tip, "why the camera" and the manual
  counter; only the app can open the camera round (`MoveLaunch`).
- Placement uses the detector's live `issues`, not its hints: a hint is
  given once in a while, so a check driven by hints turned green while
  the feet were still out of the picture.
- With a screen reader on, *Count by hand* comes first on the hub; the
  big target is one button that says the count.
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
<!-- The video is recorded on demand (the `demo` label); this is PR 2's
     version (the counter, before the Stack game). -->
**Hook (first 2 seconds):** a phone on the floor counting push-ups out
loud on screen: "7… 8… 9… 10".
**Scenario:** home → Move → 10 reps → the form tip → why the camera →
the checks turn green → 3-2-1 → ten push-ups → results → Save → push-ups
in the exercise's history.
**Caption (English):** Your phone counts your push-ups now. The camera
watches on the phone only (nothing recorded, nothing sent), half reps
don't count, and the round goes straight into your training log.
**Caption (Egyptian Arabic):** موبايلك بقى بيعدّ عدّات الضغط. الكاميرا
بتتابعك على الموبايل بس (مفيش تسجيل ولا حاجة بتتبعت)، نص العدّة مبتتحسبش،
والجولة بتتحفظ على طول في تمرينك.
**Hashtags:** #flutter #buildinpublic #fitness #pushups #عزم
