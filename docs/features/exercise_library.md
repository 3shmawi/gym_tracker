# Feature: exercise library

A shared list of exercises the plan editor can pick from. Each has a stable
id, names in Arabic and English, a muscle group, the equipment it needs and
2–3 short steps. Free text stays as the fallback. For trainees (and solo
members); captains work in the dashboard (decision doc §20).

Design: https://claude.ai/artifact/26EDAr572B4Qr8eBLB4D75 (top row, approved
Nov 2026). Illustrations are placeholders until session 8.

## What it does
- **Plan editor → "Add an exercise"** opens a sheet: *Pick from the library*
  or *Write your own*.
- **`/library?day=<dayId>`**: search (Arabic or English), muscle chips, an
  equipment filter, rows with picture, names, muscle, equipment and *Add* /
  *Added*. "Can't find it? Write your own" is always there; with no result it
  is the main action and keeps what was typed.
- **`/library/<exerciseId>[?day=<dayId>]`**: the exercise screen: picture,
  names, muscle, equipment, the steps, and (from the picker) *Add to {day}*
  with its starting targets. Also reachable from a plan exercise's
  "How to do this exercise" link (only for library exercises).
- Adding puts the exercise at the end of the day **with the library's id and
  starting targets** (the same as `PlanTemplates`). The same exercise may be in
  several days, not twice in one (`PlanEditError.duplicate`).
- Rights: adding needs the right to change the plan's structure
  (`PlanPermissions.editStructure`); without it the picker says the captain
  manages the exercises. Reading an exercise is always allowed. Same rules as
  the editor (locked day, full day, `save_plan` for gyms).

## Stable ids: why history stays matched
History is matched to an exercise by id. The catalog is seeded with **every
exercise of `PlanTemplates`, same id, names and targets**
(`exercise_catalog_test.dart` fails if they drift). Adding "Pec Deck" from the
library to a new day gives it the id `pec_deck`, so its progress and last
weight continue. Rules for the catalog: an id is `snake_case`, **never changed
and never reused for another exercise**; to add one, append an entry in
`lib/features/library/data/exercise_catalog.dart` (both names, muscle,
equipment, 2–3 steps ≤ 140 characters each) — the test checks the shape.
Exercises the member writes keep getting `ex-<time>` ids.

## Architecture (layered)
```
lib/features/library/
  domain/entities/library_exercise.dart   LibraryExercise, MuscleGroup, Equipment
  domain/repositories/exercise_library.dart  ExerciseLibrary (all, byId)
  domain/usecases/search_exercises.dart   SearchExercises (normalizes, filters)
  data/exercise_catalog.dart              the content (23 exercises)
  data/catalog_exercise_library.dart      ExerciseLibrary over the catalog
  presentation/                           LibraryView/Page, ExerciseGuideView/Page,
                                          add-exercise sheet, illustration
```
`ExerciseLibrary` is the seam for moving the list to the server later (one
list for every gym) without touching screens. `EditPlan.addLibraryExercise` and
`PlanEditorController.addLibraryExercise` do the add.

## Search
`SearchExercises.normalize`: lower case, no Arabic diacritics or tatweel, alef
variants → ا, ى → ي, ة → ه, control and bidi characters removed, spaces
collapsed; at most 60 characters count. Every word must appear in the English
or Arabic name; names starting with the first word come first. The text is
only compared: never stored, never sent to analytics.

## States
The library is bundled, so there is no loading, error or offline state of its
own (it works offline; the global offline banner still shows). Other states:
no results, an exercise already in the day, an unknown exercise ("isn't in the
library"), an unknown day, a gym that keeps the exercises to the captain, a
locked or full day (toast).

## Analytics events
| Event | When | Properties |
|---|---|---|
| `library_opened` | The picker opens | none |
| `library_exercise_viewed` | An exercise screen opens | `muscle` (`chest`/`back`/`shoulders`/`arms`/`legs`/`core`) |
| `library_custom_chosen` | "Write your own" from the picker | none |
| `plan_exercise_added` | An exercise was added (existing event) | `days`, `source` (`library` / `custom`) |
| `plan_change_refused` | The gym's rights refused it (existing event) | `kind` |

No search text, names or ids typed by the member are sent
(`test/security/exercise_library_test.dart`).

## Docs read (2026-11-03)
- **go_router 18.1.2** (`pubspec.lock`), its source in the pub cache: nested
  routes and `state.uri.queryParameters`. Finding: go_router itself throws a
  `FormatException` for any link whose **query** has invalid percent-encoding
  (`?day=%FF`), inside `GoRouteInformationProvider._valueHasChanged`, before our
  code runs, and for every route. This was solved by `LinkGuard`
  (`lib/core/router/link_guard.dart`, installed in `bootstrap.dart` before the
  router exists): such links are dropped before go_router and Flutter see them.
- **Flutter 3.47.8** `Semantics` / `ExcludeSemantics`: decorative pictures are
  excluded (the name beside them already says what it is).
- Unicode: Arabic letter variants are unified by our own small table (see
  Search); no package was added.

## Tests
- Unit: catalog integrity and sync with `PlanTemplates`, `SearchExercises`
  (spellings, ranking, filters, hostile text), `EditPlan.addLibraryExercise`.
- Widget: `LibraryView`, `ExerciseGuideView`, the add sheet (`screensUiTests`,
  32 variants + goldens each: library, filtered, added, equipment, no results,
  sheet, guide, guide with add, added, long steps, not found).
- Flows on the real router: add, same exercise in another day, read then add,
  "write your own" with the typed text, a day in progress, a gym without the
  right, crafted ids and days.
- Security: new routes in `test/security/deep_link_test.dart`; the library
  stays offline and sends fixed words only (`exercise_library_test.dart`).
- Integration: `integration_test/flows/build_plan_flow.dart` writes one
  exercise by hand and picks one from the library.

## Not done here
- Real illustrations (session 8): `LibraryExercise.illustrationKey` is the id.
- A link to the steps from the workout screen.
- Captain tools (copy a plan, templates, one change for one member): the
  dashboard, decision doc §20 (needs `plan_templates` and `plans.template_id`).
- A server-side catalog; more exercises (the seed is the 23 in the templates).

## Demo & post
Hook: "Can't remember how to do it? It's in the app."
Scenario (integration test `build_plan_flow`): build a plan → add an exercise
by writing it → *Add an exercise* → *Pick from the library* → *Arms* → search
"rope" → *Add* → back on the day, both exercises are there → edit targets → start.
Captions: EN "Pick the exercise from the library, with steps. Or write your own." ·
AR "اختار التمرين من المكتبة ومعاه الخطوات. أو اكتبه بنفسك."
Hashtags: #Azm #GymApp #Flutter #BuildInPublic
