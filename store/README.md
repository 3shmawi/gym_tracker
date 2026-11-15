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
| ios `copyright.txt` | App Store "Copyright", one line: `<year> <owner>` (no ©) |
| ios `review_information/notes.txt` | App Review notes (how to try the app); required, see docs/release.md |

`test/store/listing_test.dart` fails if a limit is exceeded or a placeholder
("Feature one", "keyword1", "اكتب هنا") is still there when you run the
upload workflow.

## Screenshots and graphics
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
