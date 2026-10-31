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

`test/store/listing_test.dart` fails if a limit is exceeded or a placeholder
("Feature one", "keyword1", "اكتب هنا") is still there when you run the
upload workflow.

## Screenshots
Design them in Claude Design (one artboard per screenshot, phone 1290×2796
for iOS 6.9", 1080×1920+ for Android), export PNGs and put them in:
- `store/android/<locale>/images/phoneScreenshots/1.png, 2.png …`
- `store/ios/screenshots/<locale>/1_iphone69.png …`
The workflow uploads screenshots only when the folders contain images.
