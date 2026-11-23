# Design: plank in Move games (a hold, in seconds) + big hints

> **Status: approved by the owner 2026-11-23.** Reviewed with EGM (design,
> implementation-readiness and zoom-out reviewers in parallel; their
> blockers are resolved below). The `/egm:` commands were not loaded in that
> session; the reviewers were the EGM plugin's agents.
> Builds on the approved Move games spec (`docs/designs/move_games.md`),
> which planned plank as "`HoldDetector`, reps = seconds" (§4.4).

## Owner's decisions (2026-11-23)
1. **Rounds:** fixed targets (30 / 45 / 60 s) **and** "as long as you can".
2. **Game:** the same tower (Stack): one block per 5 seconds held.
3. **Saved in seconds**, a real unit ("Plank 60 s"), not as reps.
4. **Big hints:** readable from the floor, 1.5–2 m from the phone. For every
   Move round, push-ups included.
5. **Hints spoken too** when the round's sound is "count out loud"; while a
   hint is spoken, the count is not (owner, 2026-11-23).

## Problem
- Move games count reps only: `RoundState.reps` grows by one per
  `RepCounted` while running (`round.dart:200-221`); a plank has no reps.
- Sets are `kg` / `plate` / `reps` (`ExerciseUnit`, `workout_plan.dart:33-48`);
  the server and the dashboard allow only those three
  (`0024_plan_rep_range.sql:66`, `dashboard/src/plans/model.ts:146`). A
  plank saved as reps reads "60 reps".
- Hints are an `AppBanner` in body text (`HintChip`, `move_parts.dart:97-114`):
  unreadable at 2 m.

## Goal
1. Move → **Plank**: a camera round counts **seconds held with a straight
   body**, on the device, with the tower.
2. Saved as a set of the library exercise **Plank** in **seconds**, shown as
   seconds in history and in a plan workout.
3. Hints in camera rounds are large enough to read from 2 m.

**Not in this version:** side plank, a second game or wobble animation, a longer round than 2 minutes (see open question 1), a level
rule for plank (plank seconds don't count toward the level), a progress
figure for holds (seconds show like reps-only exercises today: "Reps only"
→ "Hold"), editing the seconds unit on the captain's dashboard (it reads
and keeps it).

## 1. Seconds as a unit
- `ExerciseUnit.seconds`, JSON `"seconds"`, written only when used. A set is
  a `LoggedSet` with `weight: 0`, `reps` = seconds. No new field.
- `ExerciseUnit.hasWeight` (`kg`, `plate`) replaces the non-exhaustive
  `unit != ExerciseUnit.reps` checks, so seconds never gets a weight
  stepper or weight text: `log_panel.dart:39,151`,
  `active_workout_view.dart:465`, `exercise_preview_row.dart:121`,
  `workout_pill_host.dart:111`, `workout_format.dart:30,43,71`,
  `plan_day_view.dart:178`. Every `switch` over `ExerciseUnit` gets a
  `seconds` arm (the compiler finds them).
- `Exercise.step` (the getter, `workout_plan.dart:106`) → 0 for seconds;
  `SuggestWeight` treats it like reps-only (trend, weight 0).
- **Display:** a set "60 s" / "60 ث" (`unitSeconds`); progress shows
  "Hold" (`planUnitSeconds`) where reps-only shows "Reps only"; the plan
  editor's "Logged by" gains *Seconds (hold)*; the dock shows one stepper
  (±5 s) and "Log 60 s" (`workoutLogSeconds`). A rep range works the same
  for seconds (from–to seconds); nothing special.
- **Limits:** a plan target stays 1–100 (`PlanLimits`), a saved Move set up
  to 999 (`SaveMoveRound.maxReps`; sessions accept 0–1000,
  `0009_workout_sessions.sql:42`).
- **Unit source** (unchanged rule): history and progress take the unit from
  the plan's exercise, else the catalog (`get_exercise_history.dart:56-62`).
  Adding Plank from the library gives `unit: seconds`. A member who changes
  it relabels their past plank sets, as with any unit change today.
- **Server:** `0025_plan_unit_seconds.sql`: `private.plan_problem` accepts
  `"seconds"` (one value added at `0024:66`); same callers, no table, grant
  or policy change; pgTAP `plan_unit_seconds.test.sql` (seconds accepted,
  `"SECONDS"`, `"sec"`, `1` refused, other units unchanged).
- **Dashboard:** `Unit` gains `'seconds'`; `parsePlan` accepts it, `toBody`
  keeps it, the table shows "seconds"; the unit picker
  (`PlanDayView.tsx:34`) does **not** offer it, so a captain can't put a
  seconds exercise into the plan of a member on an old app. It deploys with
  the migration (same push).
- **Older apps** read `"seconds"` as kg (`ExerciseUnit.parse`); one that
  saves the plan writes it back as kg. Only a member on the new app can set
  seconds, so this needs the same member to use an old app on a second
  device. Accepted and documented.
- **Level:** `GetLevel` adds all Move reps of a day
  (`get_level.dart:65-67`); it now adds **push-up reps only**
  (`exerciseId == 'push_ups'`), so plank seconds never count as reps. Test:
  15 push-ups + 59 s plank → no Move workout that day.

## 2. Library: Plank
`plank`: *Plank* / *بلانك*, `unit: seconds`, 3 × 30 (seconds), rest 60,
muscle core, bodyweight, 3 steps. Picture: Everkinetic has only **Side
Plank** (`0113`), used as a **substitute** (marked, with a note). Dashboard
library copy regenerated (`scripts/library_from_dart.mjs`).

## 3. `PlankDetector`
`MoveExerciseId.plank('plank', catalogExerciseId: 'plank')`;
`MoveExercises.detectorFor(plank)` → `PlankDetector` (implements
`RepDetector`). Side view only.
- **Holding:** shoulders, hips and ankles seen, side view, the
  shoulder–hip–ankle line straight, shoulders above elbows/hands (on
  forearms or hands, not lying flat). Thresholds in `PlankTuning`, tuned on
  recordings (Move spec decision 9).
- **Counting:** the detector adds up held time in milliseconds (frame to
  frame, only while holding; never reset by a break) and emits the
  **existing** `RepCounted(total: seconds, took: 1 s, depth: 1)` each time
  the total crosses a whole second. No new event types. `RoundState` counts
  one per `RepCounted` **while running only**, so seconds held in placement
  and 3-2-1 don't count, a camera restart (a new detector) doesn't matter,
  and targets end through `kind.target` with no new round logic. `took`
  (1 s) is under `steadyRep`, so `score == reps`.
- **Breaking form:** not holding for 0.5 s (`HintGate`) → the existing
  `FormHint(straightBody)`; seconds stop until holding again; nothing is
  taken away. `RepState.issues` contains `straightBody` while broken.
- **`RepState` for placement** (`placement.dart:84-102`): `view: side` once
  found; `phase: ready` and `depth: 0` while holding, `phase: notVisible`
  when the body isn't seen, otherwise `phase: goingDown` and `depth: 1`
  (not ready). So "plank held a second" means holding a second.
- **Body lost** (1.5 s out of view) → `BodyLost` → the round pauses, as for
  push-ups; after it, 3-2-1 again (those seconds don't count).

## 4. Rounds
- `RoundKind` gains `h30`, `h45`, `h60` (`target` 30/45/60) and `hMax`
  (no target, no time), and `bool hold`. `MoveExercises.roundsFor(id)`:
  push-ups `[s30, s60, r10, r20]`, plank `[h30, h45, h60, hMax]`. The hub
  shows the chosen exercise's kinds.
- **Clock:** for hold kinds it shows **seconds held** (`reps`), counting up;
  the target (if any) beside it ("18 / 30 s").
- **`hMax` ends** when the member taps *End*, when form stays broken 5 s
  (they're down: tracked in `CameraRoundController` from `RepState.issues`,
  `brokenSince`, checked on every frame), or at `RoundKind.maxRound`
  (2 min, unchanged; see open question 1).
- **Best:** for `hMax` only, the longest hold (`MoveLocalRepository`,
  key per kind as today). Target kinds have no best (they always end at the
  target).
- **Placement** reuses the push-up checks; the guide says "Get into your
  plank (on forearms or hands)".
- **Results:** seconds held (and the best for `hMax`), *Save to my
  training*. `SaveMoveRound` saves one set of `plank`, `reps` = seconds
  (≥ 1). Unchanged code: it already saves `round.reps` of the exercise's
  catalog id.
- **Manual mode** (no camera): the existing manual round with the tap target
  hidden for hold kinds; `ManualRoundController` sets `reps` to
  `elapsed.inSeconds` on every tick, so targets end at the target seconds,
  `hMax` on *End*; Pause and End as today.
- **Voice** (spoken count): for hold kinds the controller speaks from
  `RepCounted` directly (not from game moments): every 5 s ("5, 10…"), and
  for a target the last 3 s ("3, 2, 1"). Tones: a note per block.

## 5. Game
`HoldStackRules` (`domain/games/`) keeps `MoveGameId.stack`: on a
`RepCounted` whose total is a multiple of 5 it passes
`RepCounted(depth: 1, took: steadyRep)` to `StackRules` (a centred, steady
block); every other event goes to `StackRules` as is (it ignores
`FormHint`). The tower's own score isn't shown for holds (the clock is).
`MoveExercises.gameFor(plank)` → `HoldStackRules`. No new moment kind, no
new animation.

## 6. Big hints (all camera rounds)
`HintChip` (`move_parts.dart`, stays in the Move feature) becomes a large
callout:
- full width at the top of the game area (over the sky, never over the top
  of the tower: the tower's view reserves the callout's height);
- `AppTextStyles.display` (32 at the design scale) bold, at most 2 lines, a
  40-px icon, solid `palette.warning` fill with `onWarning` text (new
  tokens if missing; contrast ≥ 7:1 in light and dark, checked by a test);
- one at a time, at least 2.5 s, live region as now.
The round clock uses the large number style too. In placement, the first
check still red is shown as the callout; the list stays below.
**Spoken hints** (decision 5), only when the sound mode is "count out
loud" and a voice exists for the language (`MoveVoice`, PR 5):
- a hint shown as a callout is also spoken once, the same text as the
  callout (`hintLabel`), in the app's language;
- the same hint is not spoken again for 6 s (a sag that comes and goes
  doesn't repeat it every second);
- **while a hint is being spoken, counts are not spoken**: a count that
  falls in that time is skipped, not queued (the screen still shows it);
  the next count after the hint is spoken normally. A count already being
  spoken when a hint arrives is cut off by the hint (`MoveVoice.stop`, then
  speak), since the hint matters more;
- tones mode and off: no speech, as today.
Tests: a fake `MoveVoice` records what is spoken: hint once, no count
during it, the next count after it, no repeat within 6 s, nothing in tones
mode.

Goldens: the longest hint in each language on the small phone, plus the
existing round goldens; a test that no callout text is cut at 1.3× text.

## 7. Rollout
Behind the existing `move_games` flag (off in prod, on in staging). One PR:
migration 0025 and the dashboard deploy on merge, before any store build
can send `"seconds"`. The privacy policy and store forms need no change
(same camera, same data).

## 8. Tests
- `PlankDetector`: holding, sagging, piking, lying flat, front view (no
  count), body lost, fractions across breaks (2.6 s + 2.6 s → 5 seconds),
  thresholds at their edges; recorded landmarks when available.
- Rounds: h30 ends at 30 counted seconds; seconds before running don't
  count; `hMax` ends after 5 s broken, on End, at 2 min; best only for
  `hMax`; manual hold.
- `HoldStackRules`: a block every 5 s, steady and centred.
- Unit: seconds JSON, `hasWeight` sites, dock, display, level (push-ups
  only), save.
- Widgets + goldens: hub (plank kinds), placement, round with the big
  callout (Arabic and English), results, manual hold, plan editor unit, dock.
- pgTAP 0025; dashboard: parse/keep seconds, picker without it.
- Integration (demo): Move → Plank → 30 s → hold (recorded landmarks) →
  a sag → the big "Straighten your body" → hold → done → save → history
  "Plank 30 s".

## Decisions on the last questions (owner, 2026-11-23)
1. "As long as you can" keeps the **2-minute** cap of every Move round.
2. `hMax` ends after **5 s** out of form.
