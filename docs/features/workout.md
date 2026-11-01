# Feature: workout

> Keep this page current — it is how a new developer or AI agent learns the feature.

## What it does
The member follows a plan of N days (the template is a 5-day split). The home
screen shows the workout waiting for them: day name, "Day 1 of 5", every
exercise with last time's sets and a suggested weight (↑ increase, → keep,
↓ decrease, or first time). The plan moves on only when a workout is
finished: if a day is skipped, the same workout waits and the screen says
since when.

Status: slice 2 of 3.
1. **Done:** plan, history, weight suggestions, next-workout screen, offline storage, choose the next day.
2. **Done:** active workout: one-tap logging, edit/delete a set, rest timer (+15 s, skip), supersets, finish with summary and records. Saved after every change.
3. Next: rest notification when the app is in the background, sync to Supabase (needs accounts), edit the plan and targets.

## User flows
1. First launch → "No plan yet" → **Start with the 5-day plan** → Day 1 (بنش وضهر).
2. Open the app → next workout with suggestions → **Start workout** →
   `/workout`: the dock is prefilled (today's last set, else the suggestion,
   else 0 kg and target reps) → **Log** (one tap) → rest timer → next set.
   Supersets alternate A → B with no rest between, rest after B. Tap a
   logged set to edit or delete it (delete needs a second tap).
   **Finish** (flag icon, or the dock when every set is done) → summary
   (sets, volume, records) → saved to history, plan advances, back home.
   Closing the screen keeps the workout; Start resumes it.
3. Skip a day → the same workout is shown with "waiting since <day>".
4. **Change day** → pick which plan day is next (e.g. joining mid-plan).
   The choice holds until a workout is finished, then the plan carries on
   from there.

## Rules
- **Next day** = the day after the last *finished* session, wrapping around
  (`GetNextWorkout`). No history → day 1.
- **Chosen day** (`saveChosenDay`) wins over the computed day; out-of-range
  values are ignored; finishing a workout clears it. No waiting banner then.
- **Waiting** = today is after the day following the last finished session.
- **Suggested weight** (`SuggestWeight`), from the latest session that has
  the exercise (day 4 uses day 1's sets for the same exercise):
  - every working set hit the target reps, with at least the target number of
    sets → heaviest weight + the exercise's weight step (50×12 ×3 → 52.5 ↑);
  - average reps within 2 of the target → same weight (22.5×12, 12, 11 → 22.5 →);
  - otherwise → one step lighter, never below 0 (↓);
  - no sets → first time, no number.
  Lighter warm-up sets don't count against the increase.

- **Rest** starts after each set with the exercise's rest time; none inside
  a superset round or after the last set of the day. Stored as an end time,
  so it is right after the app was in the background or killed.
- **Records** = heavier than any earlier set of that exercise (first times
  are not records).
- Inputs are clamped: weight 0–1000 kg (NaN/∞ → 0), reps 0–999.

## Progress (history per exercise)
How each exercise moved since the member started (design: board 3.3b,
"History").
- **Progress** (`/progress`, the chart button on the home bar): every plan
  exercise once, in plan order: first → latest heaviest weight, number of
  workouts, and the gain badge (↑ +7.5 / ↓ −2.5 / Same). Not done yet: says
  so. Tap a row for its history.
- **Exercise history** (`/progress/<exerciseId>`, also by tapping an
  exercise on the home screen): "Since <first date>", first → latest, the
  best set and the number of workouts; then every time, newest first
  ("Today", "Tue, Oct 27"), its sets and the change from the time before.
- Matched by exercise id, so an exercise on two plan days (or renamed)
  keeps one history. Sets with 0 reps are left out. Dates use Western
  digits in Arabic too.
- Unknown ids (old or crafted links) show "This exercise isn't in your
  plan"; never done: an empty state. History is capped at the last 200
  workouts (`LocalWorkoutRepository.maxHistory`).

## Architecture
- Layered: `lib/features/workout/`
  - `domain/`: `WorkoutPlan`/`WorkoutDay`/`Exercise` (names in both
    languages), `WorkoutSession`/`LoggedSet`, `NextWorkout`; use cases
    `GetNextWorkout`, `SuggestWeight`; `WorkoutRepository`.
  - `data/`: `LocalWorkoutRepository` (SharedPreferences JSON, offline;
    keeps the last 200 sessions; corrupt data → `ValidationFailure`, never a
    crash), `PlanTemplates.fiveDaySplit`.
  - `domain/`, workout in progress: `WorkoutDraft`, `WorkoutFlow` (set order
    and supersets, prefill, rest), `SummarizeWorkout` (volume, records).
  - `presentation/`: `ActiveWorkoutController` → `ActiveWorkoutPage` →
    `ActiveWorkoutView` (list with the current exercise scrolled to the top,
    `LogPanel` / `RestPanel` dock, edit and finish sheets); `NextWorkoutController` (AsyncNotifier, no automatic
    retry since `guard` retries), `NextWorkoutPage` → `NextWorkoutView`,
    `ExercisePreviewRow`, `WorkoutFormat` (numbers; LTR isolates inside
    Arabic so "22.5×12, 12, 11" is never reordered).
- State: Riverpod; `clockProvider` makes dates testable.
- Data sources: on-device only for now. Nothing leaves the phone except the
  analytics events below.
- Routes: `/` (home) shows `NextWorkoutPage`; `/workout` the workout in
  progress (with none: an empty state with a way home); `/progress` and
  `/progress/<exerciseId>`.

## Analytics events
| Event | When | Properties |
|---|---|---|
| `plan_created` | Member picks the template | `source: template`, `days` |
| `next_day_chosen` | Member picks the next day | `day` (1-based) |
| `workout_started` | A new workout starts | `day` (1-based) |
| `workout_finished` | Finish confirmed | `day`, `sets`, `planned_sets`, `minutes`, `records` |
| `progress_opened` | Progress screen opened | none |
| `exercise_history_opened` | An exercise's history opened | none (the id comes from a link) |

## Feature flags
None. (`active_workout` was removed when the workout screen shipped.)

## Tests
- Unit: `test/features/workout/domain/` (suggestion rules with the brief's
  real numbers, next-day and missed-day logic), `data/` (round-trip, history
  cap, corrupt / injection-like / huge stored data), controller and
  `WorkoutFormat`.
- Widget: `next_workout_view_test.dart`: content, missed-day banner,
  supersets, Start gating, empty / error / loading, Arabic; plus
  `screensUiTests` for 4 states × 32 variants with screenshots.
- Progress: `get_exercise_history_test.dart` (order, changes, 0-rep sets,
  hostile ids), `progress_controller_test.dart`, `progress_view_test.dart`
  and `exercise_history_view_test.dart` (`screensUiTests` for every state),
  `test/security/deep_link_test.dart` (`/progress`, crafted ids); the
  leg-day integration test ends on the squat's history.
- Integration: `integration_test/app_test.dart`, first launch → template →
  next workout → settings.

## Decisions & edge cases
- The template is the member's real plan (`plan_templates_test.dart` pins
  it). Targets are 3×12 except abs (3×15); squat rests 120 s. Change the
  targets when the member gives them.
- Exercise ids are stable strings; history is matched by id, so renaming an
  exercise keeps its history.
- Numbers use Western digits in both languages, like gym plates.

## Demo & post
**Hook (first 2 seconds):** Log a set in one tap, between breaths.
**Scenario (what the integration test shows, with beat() pauses):**
1. Fresh install: "No plan yet".
2. Tap **Start with the 5-day plan** → Day 1 of 5, Chest & Back.
3. Scroll the seven exercises, each with its target and suggestion.
4. Open settings.
5. Second test: choose day 3 (legs), start, add 20 kg, log, rest, +15 s,
   skip, log set 2 in one tap, finish → home shows day 4.
**Caption (English):** Pick a plan once. Every time you open the app, it shows today's workout and the weight to use. Skip a day and the workout waits for you.
**Caption (Egyptian Arabic):** اختار خطتك مرة واحدة، وكل ما تفتح التطبيق هيقولك تمرين النهارده والوزن اللي تشيله. لو فوّت يوم، التمرين بيستناك.
**Hashtags:** #flutter #buildinpublic #gym #fitness
