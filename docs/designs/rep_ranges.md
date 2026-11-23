# Design: rep ranges with double progression (sets to failure)

> **Status: approved by the owner 2026-11-23** (default range: option a).
> Reviewed with EGM in two rounds (round 1: one reviewer; round 2: design,
> implementation-readiness and zoom-out reviewers in parallel). The `/egm:`
> commands were not loaded in that session; the reviewers were the EGM
> plugin's agents.

## Problem
Field test 2026-11-22: the member's coach changed the program to **2 working
sets per exercise, each to muscular failure, no fixed reps**. The app only
knows a fixed target (`Exercise.targetReps`, e.g. 3×12):

- `SuggestWeight` (`domain/usecases/suggest_weight.dart:33-49`): 35×6, 35×6
  against 12 → **↓ lighter**, though the member trained right; against a
  target of 6 → **↑ heavier** as soon as both sets reach 6, though failure
  sets should climb in reps first.
- The dock (`widgets/log_panel.dart:124`) says "Target 12" and pre-fills 12
  (`workout_flow.dart:124`).

## Goal
A plan exercise can have a **rep range** ("6–10"). Then:
1. the plan, Today and the dock show the range;
2. each set is pre-filled with what the member did on that set last time;
3. the weight follows **double progression**: same weight while reps climb
   inside the range, one step heavier when every working set reaches the
   top, one step lighter when every working set is below the bottom.

"To failure" is how the member trains inside the range; the app does not
store it (round 2: a flag would change no behaviour and cost a key in three
codebases). A label can be added later if a range that is *not* to failure
ever needs telling apart.

**Non-goals:** a "to failure" flag, RPE/RIR, drop sets, rest-pause,
per-set targets, warm-up marking, a longer default rest, one-off "today
only" changes, rep records, **editing ranges in the captain's dashboard**
(it reads and keeps them; editing is a later feature).

## Model
`Exercise` (`entities/workout_plan.dart`) gains `repsTop` (`int?`), JSON key
`top`:
- `null` = fixed target, exactly as today. Set: `targetReps ≤ repsTop ≤ 100`,
  and `targetReps` is the **bottom** of the range.
- Written only when non-null (like `unit`, 0016): plans without a range stay
  byte-for-byte the same.
- `fromJson`: `json['top'] as int?`. A wrong type throws, exactly like a bad
  `reps` today, so a malformed plan is handled by the existing paths that
  read plans (server copy, backup restore); no new error path.
- `==`/`hashCode` include it. `copyWith` can't clear it (null = unchanged),
  so clearing goes through `EditPlan.setRange` (below), which builds the
  exercise with `repsTop: null`.
- `validatePlan` (`plan_rules.dart`) refuses `top < reps` and `top > 100`.
  JSON type cases (string, `1e9`, `-1`) are tested in the `Exercise` JSON
  tests, not in `validatePlan`, which only sees parsed plans.

### Editing rules (`EditPlan`, one place)
- `setTargets(reps: r)`: clamp `r` to `PlanLimits` (as today), then
  `top = max(top, r)` when a range is set.
- `setRange(dayId, exerciseId, {required int? top})`: `null` clears the
  range; otherwise clamp `top` to `[targetReps, PlanLimits.maxReps]`.
- Same rights as reps (`can_edit_targets`; the server's `plan_structure`
  leaves targets out, `0007:152-177`), same locked-day rule.
- Size: a plan already near 64 KB may refuse the edit with the existing
  "too large" message (≈ 12 bytes per exercise).

### Server: `supabase/migrations/0024_plan_rep_range.sql`
`private.plan_problem` (latest body in 0016; same signature and callers:
`save_plan`, `import_solo_data`, personal backup 0022, templates 0019 whose
CHECK stays valid):
- the key filter (`0016:55-60`) ignores `top` as well as `unit`;
- right after the `reps` check (`0016:71`):
  `if v_ex ? 'top' and not private.plan_int_ok(v_ex -> 'top', (v_ex ->> 'reps')::int, 100) then return 'top out of range'; end if;`
  (`plan_int_ok` requires a JSON number, so `"8"` is refused.)
- No table, grant or policy change. pgTAP
  `supabase/tests/plan_rep_range.test.sql`: valid; top = reps; top < reps;
  101; `"8"`; `true`; plan without `top` unchanged.
- Known, not in this feature: `plan_int_ok` (0007:84-86) accepts `6.0` for
  every integer field, which the app can't read (`as int`). One separate fix
  for all of them.

### Dashboard (read and keep only)
`parsePlan` (`dashboard/src/plans/model.ts:134-142`) refuses unknown keys, so
without a change a captain could not open a plan with a range. In
`model.ts`: the exercise type gains `top?: number`; `parsePlan` accepts it
(integer, `reps ≤ top ≤ 100`); `toBody` writes it back when present, so a
captain's edit never drops it; `planProblem` returns `'top out of range'`
like the server. `text.ts` prints `6–10` where it prints reps. No editing UI.
(`JSON.parse` turns `6.0` into `6`, so that case is the server's alone.)

## Behaviour

### Working sets (one helper)
New pure function `workingSets(List<LoggedSet> sets)` in
`domain/usecases/`: the sets with reps > 0 at the heaviest weight, in logged
order. `SuggestWeight` uses it instead of its inline code
(`suggest_weight.dart:23-31`, same result), and `WorkoutFlow` uses it for
pre-fill. "Set *n* last time" = the *n*-th working set.

Known limit, not changed here: today's sets are counted as logged
(`workout_flow.dart:95-108`), so a warm-up logged in the app uses one of the
planned sets, for fixed targets as well as ranges. Members who warm up
without logging are unaffected. Warm-up marking is a non-goal.

### Suggestion (`SuggestWeight`), range exercises only
- at least `targetSets` working sets and every one ≥ `repsTop` → **↑**
  heaviest + step;
- else the best working set ≥ bottom → **→** same weight;
- else → **↓** one step lighter, never below 0;
- no sets → first time.

| Range 6–10, 2 sets, step 2.5 | Suggestion |
|---|---|
| 35×6, 35×5 | → 35 |
| 35×10, 35×9 | → 35 |
| 35×10, 35×10 | ↑ 37.5 |
| 35×10, 35×10, 35×10 | ↑ 37.5 |
| 35×10 (one set only) | → 35 |
| 35×5, 35×4 | ↓ 32.5 |
| 20×12, 35×7, 35×6 | → 35 (20 kg is not a working set) |
| 37.5×6, 35×8 | → 37.5 (only 37.5×6 is a working set) |
| range 8–8: 35×8, 35×8 | ↑ 37.5 |
| reps only (pull-ups), 6–10: 0×10, 0×10 | ↑, weight 0 ("make it harder", as reps-only today) |

"Best set ≥ bottom" rather than "average within 2", because the second set
to failure is expected to be lower. Fixed targets keep today's rule.

### Dock pre-fill (`WorkoutFlow.next`), range exercises only
`next` gains `Map<String, WeightSuggestion> suggestions` (exercise id →
suggestion), passed by `ActiveWorkoutController` from the `previews` it
already has (`active_workout_controller.dart:97-99`). The suggestions come
from finished sessions only, so they stay fixed during the workout.
- **Weight**: today's previous set of the exercise if any (as today); else
  the suggestion's weight; else `startWeight` (as today).
- **Reps of set *n***: the bottom of the range when the weight differs from
  last time's working weight (after ↑ with a step > 0, or ↓); otherwise last
  time's working set *n*; otherwise (no such set, or no history) the bottom.
  Reps-only ↑ keeps weight 0, so it takes last time's set *n* (10, not 6).
- Fixed targets keep today's rules.

### Display
- Plan day rows and Today: `WorkoutFormat.target` prints `2×6–10` (numbers
  only, inside the existing left-to-right wrapper,
  `exercise_preview_row.dart:41-43`; `plan_day_view.dart:175`).
- Dock header (`LogPanel`, which takes `repsTop` next to `targetReps`):
  new key `workoutTargetRange` "Aim {from}–{to}" / "هدفك {from}–{to}"
  instead of `workoutTarget`.
- Plan editor (`plan_exercise_view.dart`): a **"Rep range"** switch
  (`planRepRange`) under the reps stepper. On → the reps stepper becomes
  "From" (`planRepsFrom`) and an "Up to" stepper (`planRepsUpTo`) appears,
  its minimum the current "From"; a helper line (`planRepRangeHelp`):
  "Keep the weight until every set reaches the top. Good for sets to
  failure." Off → `setRange(top: null)`. Keys in both ARB files.

### Analytics
`PlanEditorController.setRange(String dayId, String exerciseId, int? top)`
calls `EditPlan.setRange` and sends `plan_targets_changed` with
`field: range`, `on: top != null` (the existing field mapping,
`plan_editor_controller.dart:252-260`, gets an explicit case instead of
falling through to `weight_step`).

## Rollout (two PRs, no feature flag)
Supabase deploys only from `main` to production (`supabase.yml:11,38`);
staging app builds come from `develop`. The server refuses unknown keys.
1. **PR A → `main`**: migration 0024 + pgTAP + the dashboard's read-and-keep
   change. Before merging, check which Supabase project the staging app uses
   (`ENV_STAGING_JSON`); if it is a separate project, apply 0024 there too.
   After PR A, nobody writes `top` yet (the dashboard can't create one), so
   the Pages deploy and the Supabase deploy racing on the same push is
   harmless.
2. **PR B**: the app. Reading, suggesting and the editor ship together.

**As shipped (2026-11-23):** both steps went into one PR to `main`
(3shmawi/gym_tracker#134). The owner confirmed the staging app uses the
production Supabase project, and nothing reaches `develop` before `main`, so
the only gap the split protected against doesn't exist: merging to `main`
applies 0024 within minutes, while the app needs days of store review.

Older app versions read `top` and ignore it (`2×6`, old rule). Only the
member sets a range, on the new version; an older version on a second device
that saves the plan would drop it. Accepted and documented; no force update.

## Tests
- Unit: `workingSets`; `SuggestWeight` (every table row; fixed targets
  unchanged); `WorkoutFlow` pre-fill (weight sources, reps after ↑ / ↓ /
  →, reps-only ↑, no history, more sets than last time); `Exercise` JSON
  (round trip, key absent without a range, wrong types throw);
  `EditPlan.setTargets` / `setRange` (clear, clamp, `top` follows `reps`);
  `validatePlan`; controller event.
- Widget: plan exercise screen (range off / on, locked, no rights), dock
  header, Today and plan rows in Arabic; `screensUiTests` updated.
- Integration (demo style): plan editor → range 6–10 → workout → 35×8,
  35×6 → finish → Today shows → 35.
- pgTAP and dashboard `model.test.ts` (parse, keep on `toBody`,
  `planProblem`).

## Docs
`docs/features/workout.md` (rules, editor, event), `docs/features/dashboard.md`
(reads and keeps ranges), `docs/release.md` (PR A before PR B, staging
project), this spec as `docs/designs/rep_ranges.md`, linked from the
feature doc.

## Decision: default range
When "Rep range" is turned on, the current reps stay as the bottom and the
top is `min(reps + 4, 100)` (12 → 12–16). Nothing the member already set
changes (owner, 2026-11-23; a fixed 6–10 was the other option).
