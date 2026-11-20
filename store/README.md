# Store listings (as code)

Edit the text files, open a PR, then run **Actions → Store listing**
(manual) to upload them. Google Play uses `store/android/<locale>/`, the App
Store uses `store/ios/<locale>/` — fastlane `supply` / `deliver` layouts.

| File | Limit |
|---|---|
| android `title.txt` | 30 chars |
| android `short_description.txt` | 80 chars |
| android `full_description.txt` | 4000 chars |
| ios `name.txt`, `subtitle.txt` | 30 chars each |
| ios `keywords.txt` | 100 chars, comma-separated |
| ios `promotional_text.txt` | 170 chars |
| ios `description.txt` | 4000 chars |
| ios `release_notes.txt` ("What's New") | 4000 chars |
| android `changelogs/default.txt` ("What's new") | 500 chars |
<<<<<<< yours
| ios `copyright.txt` | App Store "Copyright", one line: `<year> <owner>` (no ©) |
| ios `review_information/notes.txt` | 3400 chars (Apple: 4000; the rest is for the demo code added in App Store Connect; the recording is an attachment). App Review notes: the six answers Apple asked for under Guideline 2.1 (recording, purpose, how to use, services, regions, regulated content); required, see docs/release.md |
=======
| ios `copyright.txt` | App Store "Copyright", one line: `<year> <owner>` (no ©); update the year when it changes |
| ios `review_information/notes.txt` | App Review notes (how to try the app); required, see docs/release.md |
>>>>>>> kit a50ee3f

`test/store/listing_test.dart` fails if a limit is exceeded or a placeholder
("Feature one", "keyword1", "اكتب هنا") is still there when you run the
upload workflow.

## Screenshots and graphics
<<<<<<< yours
Made from the app's real screens (the widget-test renders, dark mode), in
Arabic and English. Sizes checked 2026-11-15 against Apple's "Screenshot
specifications" and Google Play's "Add preview assets" help pages, and
fastlane 2.241.2's display-type table.

| Store | Files | Size |
|---|---|---|
| App Store, iPhone 6.9" | `ios/screenshots/<locale>/N_iphone69.png` (9) | 1320×2868 |
| App Store, iPad 13" (required: the app runs on iPad) | `ios/screenshots/<locale>/N_ipad13.png` (9) | 2064×2752 |
| Google Play, phone | `android/<locale>/images/phoneScreenshots/N.png` (8) | 1080×1920 |
| Google Play, 7" tablet | `android/<locale>/images/sevenInchScreenshots/N.png` (8) | 1080×1920 |
| Google Play, 10" tablet | `android/<locale>/images/tenInchScreenshots/N.png` (8) | 1440×2560 |
| Google Play, feature graphic (the header) | `android/<locale>/images/featureGraphic.png` | 1024×500 |
| Google Play, hi-res icon | `android/<locale>/images/icon.png` | 512×512 |

All are RGB PNGs (no alpha, which Apple refuses). The App Store shows the
first three screenshots in search results, so 1–3 are the core story: next
workout, one-tap logging, rest timer. The App Store icon comes from the build.

To make them again (after a UI change):
1. Render the screens: in `test/helpers/ui_check.dart` add the devices
   `storephone: Size(440, 956)` and `storetablet: Size(820, 1180)`, make
   `uiGoldenVariants` those two devices × `ar`/`en` × dark, then run
   `flutter test --update-goldens --tags golden` on the screens' test files.
   Copy each `goldens/<screen>/store*_dark.png` to `store/tools/raw/<screen>__<file>`,
   then delete the new goldens and undo the helper change.
2. `cd store/tools && node make.js && node feature.js` (Playwright; fonts
   from `website/assets/fonts` in `fonts/`, `assets/branding/icon.png` in
   `img/`), then convert the PNGs to RGB. The headlines are in `make.js`.

Alt text (Google Play asks for it, 140 characters at most) is typed in Play
Console; fastlane does not upload it.

## Privacy forms
What to answer in Google Play **Data safety** and Apple **App Privacy**: [`privacy_forms.md`](privacy_forms.md).

## Play Console App content
The answers for Play Console → App content (privacy policy, app access, ads,
content rating, target audience, data safety, government, financial
features, health, category and contact) live in
[`play_app_content.json`](play_app_content.json). These forms have no API:
open `store/tools/app_content.html` (copy button per answer, ✓ per step).
From disk the browser asks for the JSON file; or serve the folder
(`python3 -m http.server -d store`, then `/tools/app_content.html`).

## What's new
`store/ios/<locale>/release_notes.txt` (App Store "What's New in This Version")
and `store/android/<locale>/changelogs/default.txt` (Play "What's new") are
uploaded by **Store listing**, in Arabic and English. Update both before
each store release. On Play the notes go on the latest release of the track
release.yml uploads to (`PLAY_TRACK`, default `internal`), replacing the
English notes release.yml wrote from the commits; run Store listing after the
release build is on Play. Apple shows no "What's New" for an app's first
version.
=======
Made from the app's **real screens** (widget-test renders, dark mode), framed
with a headline, in Arabic and English. Sizes checked 2026-11-15 against
Apple's "Screenshot specifications", Google Play's "Add preview assets" and
fastlane 2.241.2's display types; `test/store/listing_test.dart` checks them.

| Store | Files | Size |
|---|---|---|
| App Store, iPhone 6.9" | `ios/screenshots/<locale>/N_iphone69.png` (up to 10) | 1320×2868 |
| App Store, iPad 13" (required when the app runs on iPad) | `ios/screenshots/<locale>/N_ipad13.png` (up to 10) | 2064×2752 |
| Google Play, phone | `android/<locale>/images/phoneScreenshots/N.png` (up to 8) | 1080×1920 |
| Google Play, 7" tablet | `android/<locale>/images/sevenInchScreenshots/N.png` | 1080×1920 |
| Google Play, 10" tablet | `android/<locale>/images/tenInchScreenshots/N.png` | 1440×2560 |
| Google Play, feature graphic (the listing's header) | `android/<locale>/images/featureGraphic.png` | 1024×500 |
| Google Play, hi-res icon | `android/<locale>/images/icon.png` | 512×512 |

No image may have an alpha channel (except the Play icon). The App Store
shows the first three screenshots in search results: put the core story
there. The App Store icon comes from the build.

**Make them (or again after a UI change):**
1. List the screens in `test/store/store_screens.dart`, built with sample
   data like their widget tests. Only features that are live for every user
   in prod (check the feature flags).
2. Render them:
   `flutter test test/store/store_screenshots_test.dart --update-goldens --dart-define=STORE_SHOTS=true`
   → `store/tools/raw/` (git-ignored).
3. Write the headlines in `store/tools/shots.json` (order = store order;
   Arabic and English; no `TODO` left) and the feature graphic's texts.
4. `cd store/tools && npm install && npx playwright install chromium && node make.js`
   writes every image above into `store/`. Look at them before committing.
5. Fill the store texts (limits above), open a PR, merge, run **Store
   listing**, then Play Console → Publishing overview → Send changes for
   review.

Alt text for the Play images (140 characters at most) is typed in Play
Console; fastlane doesn't upload it.

## App Store header and search results (iOS 27+)
Apple's creative assets for the product page header and search results are
optional and not uploaded by fastlane. Fill `"hero"` in
`store/tools/shots.json` (four screens and one short phrase per language),
then `cd store/tools && node hero.js` writes
`store/ios/app_store_assets/header_<locale>.png` (3840×1646) and
`search_<locale>.png` (3840×2560), with the text inside Apple's art safe area.
Upload them in App Store Connect → the version → Header / Search Results →
Upload, per language, and check Preview. Specs: Apple "Creative assets
specifications" (checked 2026-11-15).

## What's new
`store/ios/<locale>/release_notes.txt` (App Store "What's New in This
Version") and `store/android/<locale>/changelogs/default.txt` (Play "What's
new") are uploaded by **Store listing**, in Arabic and English. Update both
before each store release. On Play the notes go on the latest release of the
track release.yml uploads to (`PLAY_TRACK`, default `internal`), replacing
the English notes release.yml writes from the commits; run Store listing
after the release build is on Play. Apple shows no "What's New" for an app's
first version.

## Play Console App content
The Play Console "App content" forms (privacy policy, app access, ads,
content rating, target audience, data safety, government, financial
features, health, category and contact) have no API. Their answers live in
[`play_app_content.json`](play_app_content.json), filled from the code.
Open `store/tools/app_content.html` to copy them in: one card per Play
Console screen, a copy button per answer and a checkmark per step. From disk
the browser asks for the JSON file; or serve the folder
(`python3 -m http.server -d store`, then `/tools/app_content.html`).
>>>>>>> kit a50ee3f
