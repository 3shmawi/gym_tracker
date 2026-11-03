# Feature: exercise pictures

A drawing for each library exercise, bundled in the app (works offline). An
exercise with no drawing, or one that fails to load, shows the library
placeholder (hatched tile with a dumbbell), at the same size.

## What the member sees
- Library rows: a 52 px picture. Exercise screen: the large picture (210 high).
- **No background.** The drawings are transparent masks; the app tints them
  with the theme's text colour, so one file works in dark and light.
- Screen readers: the large picture says "Illustration of {name}"; the small
  one in a row is skipped (the name is beside it).
- Settings → About → **Open-source licenses** opens the licenses page; the
  pictures' attributions are listed there.

## Coverage (checked 2026-11-03)
All 23 exercises have a picture. **4 are substitutes**: no free drawing of the
exercise itself exists, so the picture shows a similar exercise for the same
muscle (`substitute: true` and a `substituteNote` in the manifest):

| Exercise | The picture shows |
|---|---|
| `reverse_pec_deck` | seated rear lateral raise with cables (rear shoulder) |
| `cable_kickback` | triceps kickback with a dumbbell (same movement, other equipment) |
| `reverse_wrist_curl` | reverse dumbbell curl (forearm extensors, but an elbow curl) |
| `barbell_wrist_curl` | barbell curl (forearms work, but an elbow curl) |

Replace a substitute when a real drawing is found (remove its `substitute`
fields). The test `pictures of a similar exercise are marked, with a note`
lists the four ids: change it with this table.

## Where the pictures come from
Line drawings by **Everkinetic** (Greg Priday), from
[`everkinetic/data`](https://github.com/everkinetic/data) (17 pictures, commit
`446bb9a`; `src/exercises/<id>/…-tension.png` or `src/images-web/…`) and from
[wger](https://wger.de) (2: `pec_deck`, `db_shoulder_press`).
- The repo's `LICENSE.md` is **CC BY-SA 4.0**. wger lists the same drawings as
  **CC BY-SA 3.0**, author "Everkinetic", per image; the Wikimedia Commons file
  `Biceps curl with dumbbell 1.svg` says the same (3.0).
- We change every picture (transparent, resized), so the changed pictures are
  shared under **CC BY-SA 4.0**. CC BY-SA 3.0 section 4(b) allows "a later
  version of this License with the same License Elements"; the 4.0 repo licence
  needs 4.0. Duties: attribution on the licenses page (done, from the manifest)
  and the changed pictures stay under the same licence. This covers the
  pictures, not the app's code. (Not legal advice.)
- Not verified: the author's own site, `everkinetic.com`, could not be read
  (certificate error), so the licence rests on the repo, wger and Commons.
- Rejected after reading: wger's photos (48 have no author, 39 are marked
  AI-made, mixed styles); photos from Commons (backgrounds, mixed styles);
  paid packs (WorkoutLabs does not state recolouring or attribution terms;
  Studio Alternativi forbids use "in similar or any competing services");
  AI images (the vendors' terms pages could not be read).

## Licence rules (non-negotiable)
Only images usable in a commercial app on both stores. Never: unclear licence,
NC, ND, watermarks, undocumented origin. CC BY-SA is allowed with its duties.
`ExerciseImageManifest.allowedLicenses` lists what the tests accept.

## Add a picture for a new exercise
1. Find a source and read its licence **that day** (the image's own page, not
   only the site's). It must pass the rules above. If not, stop: the exercise
   keeps the placeholder.
2. Make the two files (needs ImageMagick with WebP):
   ```bash
   ./scripts/exercise_image.sh <exercise_id> <source image>
   ```
   It writes `assets/exercises/<id>.webp` (640 px) and `<id>_thumb.webp`
   (160 px): lines opaque black, paper transparent, tinted in the app.
   The source must be dark lines on a light background.
3. Add an entry to `assets/exercises/manifest.json`: `exercise`, `file`,
   `thumb`, `title`, `sourceUrl`, `sourceFile`, `license` (SPDX), `licenseUrl`,
   `author`, `dateChecked` (today), `licenseEvidence` (pages that show the
   licence of this image), `modified`, `modification`, `attribution` (shown on
   the licenses page: title, author, source, licence, "Changed: …"). If the
   picture shows a similar exercise, not this one: `substitute: true` and a
   `substituteNote`.
4. Add the id to `ExerciseImages.available`
   (`lib/features/library/data/exercise_images.dart`).
5. Run `flutter test` (`exercise_images_test.dart` fails when anything drifts)
   and `./scripts/ui_review.sh`, look at the screenshots, commit the goldens.

## Tests
- `test/features/library/data/exercise_images_test.dart`: the id set, the
  manifest and the files agree (and are WebP, thumb smaller); every entry is
  complete (dates, https links, evidence, attribution names title, author and
  licence); no licence outside the allowed list (NC, ND, unknown refused);
  hostile or broken manifests are refused; the licenses page lists every
  attribution and the licence links.
- `exercise_illustration_test.dart`: every library exercise shows its picture; an
  exercise without one shows the placeholder (`test/features/library/helpers/no_picture.dart`); no box behind the picture, tinted with the text colour.
- Guide and library screens: `screensUiTests` with the real pictures
  (`test/helpers/ui_check.dart` decodes images before layout checks and
  screenshots: before, goldens showed an empty box), plus `exercise_guide_no_picture`.

## Docs read (2026-11-03)
CC BY-SA 3.0 legal code (sections 3(b), 4(b), 4(c)); the licence evidence above
(repo `LICENSE.md`, wger API, Commons file metadata); Flutter 3.47.8 `Image`
(`color` + `colorBlendMode: srcIn`) and `LicenseRegistry`.
