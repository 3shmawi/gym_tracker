# Feature: workout

> Keep this page current — it is how a new developer or AI agent learns the feature.

## What it does
The member follows a plan of N days (the template is a 5-day split). The home
screen shows the workout waiting for them: day name, "Day 1 of 5", every
exercise with last time's sets and a suggested weight (↑ increase, → keep,
↓ decrease, or first time). The plan moves on only when a workout is
finished: if a day is skipped, the same workout waits and the screen says
since when.

Status: slice 3 started (rest notification), plus levels.
1. **Done:** plan, history, weight suggestions, next-workout screen, offline storage, choose the next day.
2. **Done:** active workout: one-tap logging, edit/delete a set, rest timer (+15 s, skip), supersets, finish with summary and records. Saved after every change.
3. **Done:** "Rest over" notification when the phone is locked or the app is in the background.
4. **Done:** edit the whole plan in the app (days, exercises, targets, supersets).
   Next: sync to Supabase (needs accounts). With a gym account the home bar
   also shows the workspace switcher (`docs/features/gym_account_app.md`); Today
   still shows the on-device plan until plan sync (delivery step 4).

## User flows
1. First launch → "No plan yet" → **Start with the 5-day plan** → Day 1 (بنش وضهر),
   or **Build your plan** → the plan editor with an empty plan (below).
2. Open the app → next workout with suggestions → **Start workout** →
   `/workout`: the dock is prefilled (today's last set; else last time's second set,
   e.g. 15, 20, 25 → 20, or its only set; else 0 kg; target reps) → **Log** (one tap) → rest timer → next set.
   Supersets alternate A → B with no rest between, rest after B. Tap a
   logged set to edit or delete it (delete needs a second tap).
   **Finish** (flag icon, or the dock when every set is done) → summary
   (sets, volume, records) → saved to history, plan advances, back home.
   Closing the screen keeps the workout; Start resumes it.
3. Skip a day → the same workout is shown with "waiting since <day>".
4. **Change day** → pick which plan day is next (e.g. joining mid-plan).
   The choice holds until a workout is finished, then the plan carries on
   from there.

5. **Edit the plan** (`/plan`: the list button on the home bar, or
   Settings → Workout → Your plan; design boards 5.0–5.9). See "Plan editor".

## Rules
- **Days have stable ids** (`WorkoutDay.id`). Finished workouts, the workout
  in progress and the chosen day store the day's **id**, not its position,
  so reordering or deleting days never points them at the wrong day.
- **Next day** = the day after the last *finished* session's day in the
  current order, wrapping around (`GetNextWorkout`). No history, or that day
  was deleted → day 1 (an edit pins the right day first, below).
- **Chosen day** (`saveChosenDay`, a `ChosenDay`) wins over the computed
  day; unknown ids are ignored; finishing a workout clears it. Picked by the
  member: no waiting banner. Pinned by a plan edit (`byEdit`): the banner
  still shows.
- **Waiting** = today is after the day following the last finished session.
- **Suggested weight** (`SuggestWeight`), from the latest session that has
  the exercise (day 4 uses day 1's sets for the same exercise):
  - every working set hit the target reps, with at least the target number of
    sets → heaviest weight + the exercise's weight step (50×12 ×3 → 52.5 ↑);
  - average reps within 2 of the target → same weight (22.5×12, 12, 11 → 22.5 →);
  - otherwise → one step lighter, never below 0 (↓);
  - no sets → first time, no number.
  Lighter warm-up sets don't count against the increase.

- **Start weight** (`WorkoutFlow.startWeight`): an exercise's first set
  today starts at last time's *second* set (15, 20, 25 → 20; one set → that
  one; 0-rep sets ignored), so the member adjusts from a working weight
  instead of from 0. The home screen still shows the suggestion (↑ / → / ↓)
  next to each exercise; the dock doesn't jump to it.
- **A second workout the same day** is allowed, never blocked: after a
  workout was finished today, Start first asks "You already trained today"
  (Start another / Cancel). Resuming a workout in progress doesn't ask. The
  plan moves on as usual.
- **Rest** starts after each set with the exercise's rest time; none inside
  a superset round or after the last set of the day. Stored as an end time,
  so it is right after the app was in the background or killed.
- **Rest over notification** (`RestAlarmSync` → `RestAlarm`): while a
  rest runs and the app is **not in front** (locked, background, app
  switcher), a local notification waits for the rest's end time:
  "Rest over" / "Barbell Back Squat · set 2" (the set after the rest, in
  the app's language). In front, nothing is scheduled: the screen counts
  down and buzzes itself. It is removed when the member comes back, and
  rescheduled or removed on +15 s, skip, log, edit, delete, finish and
  close. The first update after a launch always cancels, so a notification
  left by a killed app never rings over the screen.
  - **Permission** is asked once, at the member's **first rest**, never at
    launch (Apple: ask "in a context that helps people understand why").
    Remembered in `rest_alarm.asked`; later rests don't ask again.
  - **Android 14+**: exact alarms ("Alarms & reminders") are off for new
    installs, and an inexact alarm can be 10 minutes to an hour late. So
    when notifications are allowed but exact alarms aren't, a sheet
    explains and opens the setting (**Open settings** / **Not now**).
    Without it no notification is scheduled (a late "Rest over" is worse
    than none). Android 12–13 grant it by default.
  - **Tap** the notification: if the app was killed, it opens on
    `/workout`; otherwise it is already there. The payload is never read.
  - Closing the workout screen mid-rest removes the notification (until the
    design's "timer pill from anywhere", board 3.3b, exists; then keep it
    while the pill shows).
- **Records** = heavier than any earlier set of that exercise (first times
  are not records).
- Inputs are clamped: weight 0–1000 kg (NaN/∞ → 0), reps 0–999.

## Plan editor
Days: add, rename (Arabic + English), delete, reorder. Exercises in a day:
add, rename, delete, reorder, superset with the next one. Targets: sets,
reps, rest (s), weight step (kg). Everything is saved on the phone after
each change ("Saves as you go"); there is no Save button.
- **Screens:** `/plan` (days; "Next" and "In progress" badges),
  `/plan/<dayId>` (exercises; supersets as A/B with the rail and the pair's
  rest), `/plan/<dayId>/<exerciseId>` (names, steppers, weight step chips,
  superset switch, delete). ⋯ on a row: rename, superset, move up/down,
  delete. Drag handles reorder; "Move up / down" do the same for screen
  readers. Deletes ask first; history is never deleted.
- **The waiting workout stays the same after any edit** (`KeepNextWorkout`):
  adding, renaming or reordering days doesn't change "next". If the waiting
  day itself is deleted, the next day after it (old order) that still exists
  waits. Done by pinning a `ChosenDay(byEdit: true)` only when the history
  alone would point elsewhere; the member's own choice is kept while its day
  exists.
- **The day of a workout in progress is locked**: no rename, delete or
  exercise/target change (banner + lock icons, "Continue the workout"). It
  can still move: the draft points at it by id. Other days stay editable.
- **New ids are new**: `day-<time36>` / `ex-<time36>`, checked against every
  id in the plan, the history and ids already issued (`newPlanId`,
  `takenIds`). A deleted exercise's id is never reused, so a new exercise
  never inherits old history. Renaming keeps the id, so history stays.
- **Limits** (`PlanLimits`, checked by `EditPlan` and again by
  `LocalWorkoutRepository.savePlan`, which refuses with `ValidationFailure`):
  1–14 days, ≤ 30 exercises a day, names 1–40 characters in each language,
  sets 1–10, reps 1–100, rest 0–600 s in 15 s steps, weight step a finite
  number > 0 and ≤ 50 (choices 0.5 / 1 / 1.25 / 2 / 2.5 / 5; another stored
  value shows as its own chip). Steppers clamp to the limits.
- **Names** (`PlanNames`): one language is enough (it fills the other);
  trimmed, new lines and runs of spaces become one space, control and
  bidi-override characters removed. Injection-like text (`'; DROP TABLE`,
  `<script>`) is stored as plain JSON text, never interpreted.
- **Supersets:** "with the next one"; the last exercise of a day never keeps
  it (deleting/moving its partner ends it). The first of a pair has no rest
  of its own (its rest stepper is off: "After the pair").
- **A day with no exercises** is allowed in the plan. If it is the waiting
  day, home shows "No exercises in this day yet" and **Add exercises**
  (opens that day) instead of Start.
- **A new plan** ("Build your plan") is saved when its first day is added
  (`plan_created`, `source: editor`); the new day opens right away.
- **Old data** (saved before day ids) migrates by position when read: plan
  days get `day-1` … `day-n` (`legacyDayId`), sessions/drafts' `day` index
  and the old int chosen day map to the same ids. The template uses those
  ids too. Nothing is rewritten until the next save.
- On-device only; Supabase sync comes with accounts.

## Progress (history per exercise)
How each exercise moved since the member started (design: board 3.3b,
"History").
- **Progress** (`/progress`, the chart button on the home bar): every plan
  exercise once, in plan order: first → latest heaviest weight, number of
  workouts, and the gain badge (↑ +7.5 / ↓ −2.5 / Same). Not done yet: says
  so. Tap a row for its history.
- **Exercise history** (`/progress/<exerciseId>`, also by tapping an
  exercise on the home screen): the workout it belongs to as a chip
  ("Chest & Back · Days 1, 4" — a day the plan repeats shows once, Arabic
  uses "،" so the numbers read in order); "Since <first date>", first → latest, the
  best set and the number of workouts; then every time, newest first
  ("Today", "Tue, Oct 27"), its sets and the change from the time before.
- Matched by exercise id, so an exercise on two plan days (or renamed)
  keeps one history. Sets with 0 reps are left out. Dates use Western
  digits in Arabic too.
- Unknown ids (old or crafted links) show "This exercise isn't in your
  plan"; never done: an empty state. History is capped at the last 200
  workouts (`LocalWorkoutRepository.maxHistory`).
## Levels
Shown on the home screen in a card under today's exercises: the level
figure (`AzmLevelFigure`), "Your level · Beginner", the weeks in a row and
what the next level needs. Worked out by itself from the history
(`GetLevel`); the member never picks it.
- A **week** runs Saturday → Friday and is **active** with 3+ finished
  workouts.
- **Up:** 4 active weeks in a row → intermediate (at least 12 workouts);
  8 more → pro (about 3 months in all).
- **Down:** a break (one or more finished weeks in a row that aren't
  active) drops one level: pro → intermediate → beginner. The week in
  progress never counts as a break.
- **Comeback:** a level reached before comes back in half the weeks
  (2 for intermediate, 4 for pro); the card says so.
- The best level ever reached is stored (`workout.level`), so the comeback
  stays fast after old history is trimmed. Unknown or hostile stored values
  read as beginner.
- The numbers are `GetLevel`'s constructor defaults (`workoutsPerWeek`,
  `intermediateWeeks`, `proWeeks`): change them there and in this list.

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
  - Rest notification: `domain/services/rest_alarm.dart` (`RestAlarm`,
    `RestAlarmNotice`, `RestAlarmAccess`), `data/services/notification_rest_alarm.dart`
    on `core/notifications/local_notifications.dart` (the plugin wrapper),
    `presentation/rest_alarm_sync.dart` (when to schedule; owned by
    `ActiveWorkoutPage`, which watches the app lifecycle),
    `widgets/rest_on_time_sheet.dart`. Wired in `Dependencies.restAlarm`;
    `bootstrap.dart` opens `/workout` when the notification launched the app.
  - `presentation/`: `ActiveWorkoutController` → `ActiveWorkoutPage` →
    `ActiveWorkoutView` (list with the current exercise scrolled to the top,
    `LogPanel` / `RestPanel` dock, edit and finish sheets); `NextWorkoutController` (AsyncNotifier, no automatic
    retry since `guard` retries), `NextWorkoutPage` → `NextWorkoutView`,
    `ExercisePreviewRow`, `WorkoutFormat` (numbers; LTR isolates inside
    Arabic so "22.5×12, 12, 11" is never reordered).
- State: Riverpod; `clockProvider` makes dates testable.
- Data sources: on-device only for now. Nothing leaves the phone except the
  analytics events below. The rest notification is local (no push token).
- Plan editor: `domain/usecases/plan_rules.dart` (`PlanLimits`,
  `PlanNames`, `validatePlan`, `newPlanId`), `edit_plan.dart` (`EditPlan`:
  every change as a pure function; `KeepNextWorkout`; `takenIds`),
  `entities/chosen_day.dart`. `PlanEditorController` (auto-disposed
  AsyncNotifier shared by the three screens: plan, waiting day, locked day,
  save failure + retry) → `PlanPage`/`PlanView`, `PlanDayPage`/`PlanDayView`,
  `PlanExercisePage`/`PlanExerciseView`; `widgets/plan_widgets.dart` (row,
  superset rail, name / delete / ⋯ sheets, reorderable card). Shared
  controls added to `app_controls.dart`: `AppTextField`, `AppSwitchRow`,
  `AppChoiceChip`, `AppDangerButton`.

## Rest notification setup
Package: `flutter_local_notifications` **22.3.3** + `timezone` **0.11.2**
(pub.dev and changelogs checked 2026-11-01; 22.3.2 fixed iOS 27 exceptions
when permission is denied). Docs read the same day: Apple "Asking
permission to use notifications"; Android "Schedule alarms" and "Behavior
changes: Android 14 — schedule exact alarms are denied by default"; the
plugin README.
- **Android:** `SCHEDULE_EXACT_ALARM` only (user-granted). Not
  `USE_EXACT_ALARM`: Google Play allows it only for alarm-clock and calendar
  apps. `POST_NOTIFICATIONS` (Android 13+ prompt) and `VIBRATE` come from the
  plugin. One receiver, `ScheduledNotificationReceiver`, not exported; no
  boot receiver (a rest doesn't survive a reboot). Core library desugaring
  on (`desugar_jdk_libs` 2.1.4, as the plugin). Small icon:
  `drawable-*/ic_stat_rest.png` (white logo silhouette from
  `assets/branding/icon_foreground.png`), kept from R8 by `res/raw/keep.xml`.
  Channel `rest_timer` ("Rest timer" / "مؤقت الراحة"), high importance,
  schedule mode `exactAllowWhileIdle`. Some OEMs (Xiaomi, Huawei…) kill
  background alarms: see dontkillmyapp.com.
- **iOS:** no capability or Info.plist key needed. `AppDelegate` sets the
  `UNUserNotificationCenter` delegate. Alert + sound, interruption level
  `active` (time-sensitive would need a new entitlement and profile).
- **Both flavors** share this (main manifest, one AppDelegate).
- **On a phone** (CI can't: the simulator would stop on the permission
  prompt, so tests fake `RestAlarm`): start a workout, log a set, allow,
  lock the phone → "Rest over" at 0:00 with sound; unlock early → nothing
  rings; Android 14: Not now → nothing rings; turn on Alarms & reminders →
  it rings.
- Routes: `/` (home) shows `NextWorkoutPage`; `/workout` the workout in
  progress (with none: an empty state with a way home); `/progress` and
  `/progress/<exerciseId>`; `/plan`, `/plan/<dayId>`,
  `/plan/<dayId>/<exerciseId>`.

## Analytics events
| Event | When | Properties |
|---|---|---|
| `plan_created` | Member picks the template | `source: template`, `days` |
| `next_day_chosen` | Member picks the next day | `day` (1-based) |
| `workout_started` | A new workout starts | `day` (1-based) |
| `workout_finished` | Finish confirmed | `day`, `sets`, `planned_sets`, `minutes`, `records` |
| `progress_opened` | Progress screen opened | none |
| `exercise_history_opened` | An exercise's history opened | none (the id comes from a link) |
| `level_reached` | A new best level (once per level) | `level` (`intermediate` / `pro`) |
| `rest_alarm_answered` | The first rest's permission question was answered | `allowed` (notifications on), `on_time` (and exact alarms on) |

Every event also carries `app` (`gym_tracker`) and `environment`
(`staging` / `prod`). Screen views (`$screen`) use the route names: `home`,
`workout`, `progress`, `exercise_history`, `settings`. PostHog dashboard:
**Azm – workouts** (filtered to bundle `com.mohager.azm`).

| `plan_opened` | Plan editor opened | none |
| `plan_created` | First save of a plan built in the editor | `source: editor`, `days` |
| `plan_day_added` / `plan_day_renamed` / `plan_day_deleted` / `plan_day_moved` | A day changed | `days` (count after) |
| `plan_exercise_added` / `plan_exercise_renamed` / `plan_exercise_deleted` / `plan_exercise_moved` | An exercise changed | `days` |
| `plan_superset_changed` | Superset switched | `on`, `days` |
| `plan_targets_changed` | A target changed | `field` (`sets` / `reps` / `rest` / `weight_step`), `days` |

No names, ids or values typed by the member are sent.

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
  next workout → settings; leg day; a month of training → Intermediate;
  rest notification (lock and unlock during a rest, +15 s, skip, close).
- Rest notification: `rest_alarm_sync_test.dart` (front/background,
  +15 s, skip, edit, close, killed app, errors), `active_workout_page_test.dart`
  (real screen and lifecycle: first-rest ask, text in English and Arabic,
  finish/close, the Android 14 sheet), `notification_rest_alarm_test.dart`
  (asked once, hostile stored value), `core/notifications/local_notifications_test.dart`
  (the plugin's channel on Android and iOS: no prompt at start-up, exact
  mode, skipped without exact alarms or in the past),
  `widgets/rest_on_time_sheet_test.dart` (`screenUiTests`), and
  `test/security/` (manifest permissions, notification tap → `/workout` only).
- Levels: `get_level_test.dart` (up, down, comeback, Saturday weeks, UTC),
  repository (round trip, hostile stored values), controller (best level
  saved), `next_workout_view_test.dart` (card texts in English and Arabic),
  `widgets/level_card_test.dart` (`screenUiTests` for every level state),
  `test/core/ui/azm_level_*_test.dart` (figure vs. the design).

- Plan editor: `plan_rules_test.dart` (names, hostile and huge input,
  limits, ids), `edit_plan_test.dart` (every edit, lock, last day,
  supersets, clamping, `KeepNextWorkout`: reorder, delete the waiting / last
  finished day, the member's choice, the banner, migrated history),
  repository (round trip with ids, hostile names, refused invalid plans,
  migration of plan / sessions / draft / old int chosen day, hostile stored
  chosen day), `plan_editor_controller_test.dart` (build from nothing, ids
  never reused, rename keeps history, next stays after reorder/delete, the
  locked day, failed save + retry, load error), widget tests
  `plan_view_test.dart`, `plan_day_view_test.dart`,
  `plan_exercise_view_test.dart` (every state + sheets in
  `screensUiTests`), home (plan button, Build your plan, empty day) and
  settings, `test/security/deep_link_test.dart` (`/plan` links: crafted ids,
  extra segments, links can't change data), `plan_editor_e2e_test.dart` and
  the integration demo (shared `integration_test/flows/build_plan_flow.dart`).

## Decisions & edge cases
- The template is the member's real plan (`plan_templates_test.dart` pins
  it). Targets are 3×12 except abs (3×15); squat rests 120 s. Change the
  targets when the member gives them.
- Exercise ids are stable strings; history is matched by id, so renaming an
  exercise keeps its history. Renaming changes only that day's copy of an
  exercise that is on two days (day 1 and day 4); their history is shared.
- Day ids instead of blocking edits: reordering is free, only the day of a
  workout in progress is locked, and the waiting workout never jumps.
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

**Rest notification (fourth test):** start legs, log the squat, the rest
starts; lock the phone → "Rest over · Barbell Back Squat · set 2" waits
for 2:00; unlock → gone; +15 s moves it; skip removes it; close the
workout mid-rest → nothing rings.
**Caption (English):** Lock your phone between sets. Azm tells you when the rest is over, and which set is next.
**Caption (Egyptian Arabic):** اقفل موبايلك بين المجموعات، وعزم هيقولك لما الراحة تخلص والمجموعة الجاية إيه.

**Levels (third test):** a month of training → the home screen shows the
intermediate figure.
**Caption (English):** Train 3 times a week and your level climbs. Take a break and it drops, but coming back is twice as fast.
**Caption (Egyptian Arabic):** اتمرّن 3 مرات في الأسبوع ومستواك يطلع. لو وقفت بينزل، بس الرجوع أسرع بالنص.

**Plan editor (fourth test):** "Build your plan" → add "صدر وتراي / Chest & Triceps" →
add Bench Press and Rope Pushdown → open Bench Press, 4 sets, 5 kg step →
back home: the new day is waiting → Start: "Set 1 of 4".
**Hook:** Your plan, your exercises, in under a minute.
**Caption (English):** Build your own plan in the app: days, exercises, sets, reps, rest. Reorder anything, and the workout waiting for you stays put.
**Caption (Egyptian Arabic):** اعمل خطتك بنفسك من التطبيق: الأيام والتمارين والمجموعات والعدات والراحة. رتّب زي ما تحب، والتمرين اللي مستنيك مش هيتغير.
**Hashtags:** #flutter #buildinpublic #gym #fitness #riverpod
