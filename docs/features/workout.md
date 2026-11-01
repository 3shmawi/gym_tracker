# Feature: workout

> Keep this page current — it is how a new developer or AI agent learns the feature.

## What it does
The member follows a plan of N days (the template is a 5-day split). The home
screen shows the workout waiting for them: day name, "Day 1 of 5", every
exercise with last time's sets and a suggested weight (↑ increase, → keep,
↓ decrease, or first time). The plan moves on only when a workout is
finished: if a day is skipped, the same workout waits and the screen says
since when.

Status: slice 1 of 3.
1. **Done:** plan, history, weight suggestions, next-workout screen, offline storage.
2. Next: active workout (log sets with the stepper dock, rest timer, supersets, finish).
3. Then: sync to Supabase (needs accounts), edit the plan.

## User flows
1. First launch → "No plan yet" → **Start with the 5-day plan** → Day 1 (بنش وضهر).
2. Open the app → next workout with suggestions → **Start workout** (behind
   the `active_workout` flag until slice 2).
3. Skip a day → the same workout is shown with "waiting since <day>".

## Rules
- **Next day** = the day after the last *finished* session, wrapping around
  (`GetNextWorkout`). No history → day 1.
- **Waiting** = today is after the day following the last finished session.
- **Suggested weight** (`SuggestWeight`), from the latest session that has
  the exercise (day 4 uses day 1's sets for the same exercise):
  - every working set hit the target reps, with at least the target number of
    sets → heaviest weight + the exercise's weight step (50×12 ×3 → 52.5 ↑);
  - average reps within 2 of the target → same weight (22.5×12, 12, 11 → 22.5 →);
  - otherwise → one step lighter, never below 0 (↓);
  - no sets → first time, no number.
  Lighter warm-up sets don't count against the increase.

## Architecture
- Layered: `lib/features/workout/`
  - `domain/`: `WorkoutPlan`/`WorkoutDay`/`Exercise` (names in both
    languages), `WorkoutSession`/`LoggedSet`, `NextWorkout`; use cases
    `GetNextWorkout`, `SuggestWeight`; `WorkoutRepository`.
  - `data/`: `LocalWorkoutRepository` (SharedPreferences JSON, offline;
    keeps the last 200 sessions; corrupt data → `ValidationFailure`, never a
    crash), `PlanTemplates.fiveDaySplit`.
  - `presentation/`: `NextWorkoutController` (AsyncNotifier, no automatic
    retry since `guard` retries), `NextWorkoutPage` → `NextWorkoutView`,
    `ExercisePreviewRow`, `WorkoutFormat` (numbers; LTR isolates inside
    Arabic so "22.5×12, 12, 11" is never reordered).
- State: Riverpod; `clockProvider` makes dates testable.
- Data sources: on-device only for now. Nothing leaves the phone except the
  analytics events below.
- Routes: `/` (home) shows `NextWorkoutPage`.

## Analytics events
| Event | When | Properties |
|---|---|---|
| `plan_created` | Member picks the template | `source: template`, `days` |
| `workout_started` | Start workout tapped (flag on) | `day` (1-based) |

## Feature flags
- `Flags.activeWorkout` (`active_workout`): shows **Start workout**. Off
  until the active-workout screen ships (slice 2).

## Tests
- Unit: `test/features/workout/domain/` (suggestion rules with the brief's
  real numbers, next-day and missed-day logic), `data/` (round-trip, history
  cap, corrupt / injection-like / huge stored data), controller and
  `WorkoutFormat`.
- Widget: `next_workout_view_test.dart`: content, missed-day banner,
  supersets, Start gating, empty / error / loading, Arabic; plus
  `screensUiTests` for 4 states × 32 variants with screenshots.
- Integration: `integration_test/app_test.dart`, first launch → template →
  next workout → settings.

## Decisions & edge cases
- Template days 1, 2 and 4, 5 use the exercises from the design brief.
  Day 2's shoulder exercises and all of day 3 (legs) are common defaults:
  **check them with the member's real plan**.
- Exercise ids are stable strings; history is matched by id, so renaming an
  exercise keeps its history.
- Numbers use Western digits in both languages, like gym plates.

## Demo & post
**Hook (first 2 seconds):** The app already knows what you lift today.
**Scenario (what the integration test shows, with beat() pauses):**
1. Fresh install: "No plan yet".
2. Tap **Start with the 5-day plan** → Day 1 of 5, Chest & Back.
3. Scroll the seven exercises, each with its target and suggestion.
4. Open settings.
**Caption (English):** Pick a plan once. Every time you open the app, it shows today's workout and the weight to use. Skip a day and the workout waits for you.
**Caption (Egyptian Arabic):** اختار خطتك مرة واحدة، وكل ما تفتح التطبيق هيقولك تمرين النهارده والوزن اللي تشيله. لو فوّت يوم، التمرين بيستناك.
**Hashtags:** #flutter #buildinpublic #gym #fitness
