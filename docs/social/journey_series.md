# «من الصفر لحد النهارده»: the Azm build-in-public series (plan)

Status: **approved by the owner on 2026-11-16** (as planned; handle
**Mohager**; Egyptian Arabic only, the English caption is for the post text;
the AI coding agent gets one line, in episode 11). Rendered with
`tool/journey_video/` (scenes and timings: `tool/journey_video/episodes.js`).
Facts come from `docs/social/journey_timeline.md`; every beat names its
source. A beat marked **[needs owner]** stays out until the owner answers:
- 01 · beat 1 (when and why the idea came): not answered, so the video
  shows only the product line from `CLAUDE.md`.
- 10 · beat 4 (live on the stores?): not answered, so the video says
  «جاهز للستور» and nothing about being live.

## Durations (as rendered)
| # | Episode | Length |
|---|---|---|
| 00 | Trailer | 35 s |
| 01 | اليوم صفر | 36.5 s |
| 02 | أول شاشة | 41 s |
| 03 | الموبايل الحقيقي | 37.5 s |
| 04 | من لوحدك لجيم | 33.5 s |
| 05 | اتعلّم التمرين صح | 34 s |
| 06 | داشبورد الكابتن | 37.5 s |
| 07 | متخسرش تمرينك | 37.5 s |
| 08 | الكاميرا بتعدّ | 37 s |
| 09 | الجودة | 36 s |
| 10 | على الستور | 36.5 s |
| 11 | وصلنا لحد فين | 35 s |

## Format (all episodes)
- 1080×1920, 30 fps, 33–41 s, Egyptian Arabic on screen, generated music
  (variation per episode on one theme), −14 to −16 LUFS.
- Same intro (2 s, series logo), header «حلقة n من 11» with 11 segments (the
  current one fills during the episode) and its dates, same outro (CTA + handle).
- Safe zone: no key text in the top 220 px or bottom 380 px; text ≥ 36 px.
- Visual sources: real store shots (`store/android/ar/images/phoneScreenshots/`),
  golden screenshots (`test/**/goldens/`), real code from the named commit,
  real numbers. Nothing is drawn as if it were a screen; demo data in the goldens (gym names, colours) is labelled «تجريبي».
- Hashtags on every post: `#BuildInPublic #Flutter #عزم #Azm #برمجة #جيم`.
  Each episode adds 2–3 of its own.

## Schedule
3 a week, Sunday / Tuesday / Thursday at 20:00 Cairo time (after-work
evening), trailer on the Saturday before.

| # | Date | Episode |
|---|---|---|
| 00 | Sat 2026-11-21 | Trailer |
| 01 | Sun 11-22 | اليوم صفر |
| 02 | Tue 11-24 | أول شاشة |
| 03 | Thu 11-26 | الموبايل الحقيقي |
| 04 | Sun 11-29 | من لوحدك لجيم |
| 05 | Tue 12-01 | اتعلّم التمرين صح |
| 06 | Thu 12-03 | داشبورد الكابتن |
| 07 | Sun 12-06 | متخسرش تمرينك |
| 08 | Tue 12-08 | الكاميرا بتعدّ |
| 09 | Thu 12-10 | الجودة |
| 10 | Sun 12-13 | على الستور |
| 11 | Tue 12-15 | وصلنا لحد فين |

---

## 00 · Trailer: «16 يوم»
- **Hook:** «آخر مرة شِلت كام؟» → «في 16 يوم بنيت تطبيق يفتكرلك.»
- **Beats:**
  1. Counters: 16 يوم · 130 commit · 117 PR · 72 إصدار (timeline → Numbers).
  2. A fast flick through the 8 store shots (`store/`).
  3. «من أول سطر لحد الستور.. حلقة حلقة.»
- **CTA:** «تابع عشان متفوتكش الحلقة الأولى.»
- **AR:** في 16 يوم بنيت عزم: تطبيق جيم بيفتكرلك آخر وزن شِلته ويجهزلك تمرينك الجاي. هحكيلكم الرحلة كلها حلقة حلقة، بالأرقام الحقيقية والغلطات كمان.
- **EN:** In 16 days I built Azm, a gym app that remembers your last weight and has your next workout ready. I'm sharing the whole journey, episode by episode: real numbers, real mistakes.
- **Tags:** `#عزم_من_الصفر #IndieDev`

## 01 · اليوم صفر
- **Hook:** «فكرة وفولدر فاضي.. وبعد يوم: 310 ملف.»
- **Beats:**
  1. The idea and why **[needs owner]** (open question 1).
  2. 31 Oct: bootstrap from flutter-project-kit, 310 files (`247391e`).
  3. The stack as a diagram: Flutter · Supabase · Riverpod · Sentry · PostHog · عربي + إنجليزي (`docs/decisions/0001-initial-stack.md`).
  4. «القاعدة: كل حاجة بتتكتب في الدوكس قبل الكود» (`CLAUDE.md`).
- **CTA:** «الحلقة الجاية: أول شاشة.»
- **AR:** اليوم صفر. فكرة، وقرار في نفس اليوم على كل الأدوات: Flutter وSupabase وعربي وإنجليزي من أول يوم.
- **EN:** Day zero: an idea, and the whole stack decided on day one. Flutter, Supabase, Arabic and English from the start.
- **Tags:** `#Supabase #Riverpod`

## 02 · أول شاشة
- **Hook:** «التطبيق شكله حلو.. لحد ما فتحته على تابلت.»
- **Beats:**
  1. Problem: «آخر مرة شِلت كام؟» → the next-workout screen with ↑ زوّد / → ثبّت / ↓ قلّل (#1, store shot 1).
  2. One tap logs the set (store shot 2) + rest timer (store shot 3).
  3. Lesson: text grew 2.2× on tablets → scale clamped 0.9–1.15 (`b19a406`, code typed on screen).
  4. Result: every screen tested on 32 variants (devices × عربي/English × light/dark × large text). Counter 32.
  5. Same day: levels, progress, `v0.1.0` (#5, #7).
- **CTA:** «إيه اللي حصل لما جرّبته على آيفون حقيقي؟ الحلقة الجاية.»
- **AR:** أول feature: التمرين الجاي جاهز، وسجّل المجموعة بضغطة واحدة. والدرس: الشاشة اللي حلوة على موبايلك ممكن تبوظ على تابلت، فبقت كل شاشة بتتجرب على 32 شكل.
- **EN:** First feature: your next workout, ready; log a set in one tap. The lesson: a screen that looks right on your phone can break on a tablet, so every screen is now tested in 32 variants.
- **Tags:** `#FlutterDev #UI`

## 03 · الموبايل الحقيقي
- **Hook:** «الأبلكيشن بيقفل لوحده لما تعمل scroll.»
- **Beats:**
  1. The crash: iOS killed the app scrolling history (#15, Sentry issue id only).
  2. Why: one glass card as tall as the whole history captured the screen behind it (diagram).
  3. Fix: a flat card for long lists (code from `f1cdd93`).
  4. Measured: glass blur cost 4–19× the raster time → cards keep the look with blur 0 (`cb855d0`, `docs/performance.md`). Counter «×19».
  5. Plus: «Rest over» notification with the phone locked (#12).
- **CTA:** «بعد كده: التطبيق بقى للجيمات.»
- **AR:** أول مشكلة من موبايل حقيقي: الأبلكيشن بيقفل وإنت بتعمل scroll. السبب كارت زجاج طوله قد الهيستوري كله. الحل كارت عادي، والـ blur اتشال من الكروت بعد ما قسناه.
- **EN:** First bug from a real phone: the app closed while scrolling. The cause: one glass card as tall as the whole history. Fixed, then measured: blur cost up to 19× the render time.
- **Tags:** `#Performance #iOS`

## 04 · من لوحدك لجيم
- **Hook:** «الكابتن عايز يعرف المتدرب شال كام.. من غير ما يسأله.»
- **Beats:**
  1. Decision: solo stays with no account; a captain adds trainees; join by QR, single use, 7 days, 6-character code (`docs/decisions/gym_accounts.md`, #19).
  2. Built: tables with RLS, `redeem_invite`, join screen (#20, #21, #27); diagram phone → QR → link → app.
  3. Bug: joining timed out (captcha web view blocked; a redirect dropped the code) (#60).
  4. Result: store shot 7 «أهلا بيك في …» + «الكابتن حدّث خطتك» (#29).
- **CTA:** «إزاي المتدرب يتعلم التمرين صح؟ الحلقة الجاية.»
- **AR:** عزم بقى للجيمات: الكابتن يضيف المتدرب، والمتدرب يعمل scan للـ QR ويدخل. والتمرين اللي اتسجل لوحدك بيفضل بتاعك.
- **EN:** Azm goes to gyms: the captain adds a trainee, the trainee scans a QR and is in. Training logged solo stays yours.
- **Tags:** `#QRCode #RLS`

## 05 · اتعلّم التمرين صح
- **Hook:** «ليه الفيديو مبيشتغلش وإنت برة الأبلكيشن؟ ده قرار.»
- **Beats:**
  1. Exercise library + drawings (#31, #33; store shot 6; Everkinetic credit on screen).
  2. YouTube how-to videos, and the gym's own video (#40, #46).
  3. Decision: no picture-in-picture, because YouTube's policy forbids a background player (`docs/decisions/video_outside_app.md`).
  4. Instead: a floating mini player inside the app (#48, #50).
- **CTA:** «الحلقة الجاية: الكابتن ياخد داشبورد.»
- **AR:** مكتبة تمارين برسومات وفيديو لكل تمرين. وقرار مهم: مفيش فيديو في الخلفية، عشان قواعد يوتيوب بتمنعه، فعملنا ميني بلاير جوه التطبيق.
- **EN:** An exercise library with drawings and a video for each move. And a call we made on purpose: no background video, because YouTube's rules forbid it, so there's an in-app mini player instead.
- **Tags:** `#YouTubeAPI #ProductDecisions`

## 06 · داشبورد الكابتن
- **Hook:** «التطبيق للمتدرب.. والكابتن؟ ليه موقع لوحده.»
- **Beats:**
  1. Decision: no captain tools in the app; everything in a web dashboard (`gym_accounts.md` §1, changed 2026-11-03).
  2. Seven steps D0 → D6 on a timeline: sign-in, members + QR cards, media, plans, templates, progress, gym colour (#53 → #82).
  3. Gym colour: the app follows the gym's colour (#81; goldens `gym_colour_*`, labelled «ألوان تجريبية»).
  4. 234 dashboard tests (no real dashboard screenshots in the repo, so none are drawn).
- **CTA:** «لو موبايلك ضاع.. تمرينك راح؟ الحلقة الجاية.»
- **AR:** الكابتن خد داشبورد على الويب: يضيف متدربين، يطبع كروت QR، يعمل خطة مرة واحدة لكل الناس، ويشوف تقدمهم. والتطبيق بياخد لون الجيم.
- **EN:** Captains got a web dashboard: add trainees, print QR cards, build a plan once for everyone, follow their progress. And the app takes the gym's colour.
- **Tags:** `#WebDev #Dashboard`

## 07 · متخسرش تمرينك
- **Hook:** «كان بيحفظ آخر 200 تمرين بس.»
- **Beats:**
  1. Before: one JSON list, cut at 200 (`docs/designs/never_lose_history.md`).
  2. Built: a SQLite database on the phone with the whole history (#90).
  3. Backup + restore on a new phone, email code, no password (#91–#97; goldens `backup_*`).
  4. Bug caught before users: a captain's restore pulled their trainees' workouts, because permissions add up (#113). Diagram of two policies adding up.
- **CTA:** «الحلقة الجاية: الكاميرا بتعدّ الضغط.»
- **AR:** التطبيق كان بيحفظ آخر 200 تمرين بس. دلوقتي كل الهيستوري على الموبايل، وباك أب، وترجعه على موبايل جديد. ومشكلة صغيرة كانت هتخلي الكابتن يشوف تمارين المتدربين في الهيستوري بتاعه.
- **EN:** The app kept only the last 200 workouts. Now the whole history lives on the phone, backs up, and comes back on a new phone. Plus the permissions bug that would have mixed a captain's history with their trainees'.
- **Tags:** `#SQLite #Backup`

## 08 · الكاميرا بتعدّ
- **Hook:** «اعمل ضغط.. والموبايل يعدّ.»
- **Beats:**
  1. Idea: a viral push-up game; the rule: nothing of that game is used (`docs/designs/move_games.md`).
  2. Counting on the device, no recording, nothing leaves the phone (#92, store shot 5 «الكاميرا بتعدّ ضغطك»).
  3. Stack game + counting out loud (#99, #102).
  4. Real-phone bugs: app crash on start (#104), camera behind the permission dialog (#105), «too slow» while still sitting (#106).
  5. Testing: real sets replayed as joints and times only (#103).
- **CTA:** «إزاي بنتأكد إن كل ده شغال؟ الحلقة الجاية.»
- **AR:** ألعاب الحركة: الكاميرا بتعدّ الضغط على الموبايل نفسه، من غير تسجيل ولا صور. وكل لعبة تتحسب مجموعة في تمرينك.
- **EN:** Move games: the camera counts your push-ups on the phone itself, with no recording and no photos, and every round counts as a set in your training.
- **Tags:** `#MLKit #OnDeviceAI`

## 09 · الجودة
- **Hook:** «1,649 تست.. ليه؟»
- **Beats:**
  1. Counters: 1,649 Flutter tests, 234 dashboard tests, 25 database permission test files (timeline → Numbers).
  2. Every screen × 32 variants (overflow, cut text, Arabic, dark mode, large text).
  3. Security in CI: secret scanning, vulnerable packages, workflow checks (`docs/security.md`), diagram of the CI gate.
  4. Every merge = a release: 72 versions in 16 days (`docs/release.md`, tags).
- **CTA:** «الحلقة الجاية: الستور.»
- **AR:** الجودة مش حلقة لوحدها، دي كانت من أول يوم: 1,649 تست، كل شاشة بتتجرب على 32 شكل، وفحص أمان في كل PR.
- **EN:** Quality wasn't a phase, it was there from day one: 1,649 tests, every screen checked in 32 variants, security checks on every PR.
- **Tags:** `#Testing #CI`

## 10 · على الستور
- **Hook:** «حتى صفحة الستور.. كود.»
- **Beats:**
  1. Store texts and screenshots in Arabic and English, made from the real screens (#116, `store/README.md`).
  2. Uploads from GitHub Actions (#119–#124).
  3. Three ready plans for someone starting alone (#107).
  4. Status on the stores **[needs owner]** (open question 2).
- **CTA:** «آخر حلقة: وصلنا لحد فين.»
- **AR:** صفحة الستور نفسها بتتكتب في الريبو وبتترفع لوحدها، بالعربي والإنجليزي.
- **EN:** Even the store listing lives in the repo and uploads itself, in Arabic and English.
- **Tags:** `#AppStore #GooglePlay`

## 11 · وصلنا لحد فين
- **Hook:** «من فولدر فاضي.. لده.»
- **Beats:**
  1. Animated timeline of all 117 PRs over 16 days.
  2. Counters: 7 features · 20 pages · 659 strings × 2 languages · 72 releases.
  3. «مع AI coding agent.. وكل سطر عدّى على تستات» (the `Co-Authored-By` lines in `git log`).
  4. The last 8 s of the brand promo (`docs/brand/promo_video/`, 95–103 s): logo, «جيمك.. في جيب كل متدرب», azmm.pages.dev.
- **CTA:** «جرّبه، وقولّي أبني إيه بعد كده.»
- **AR:** 16 يوم، 130 commit، 117 PR، 72 إصدار. ده عزم النهارده. قولّي في الكومنتات: أبني إيه بعد كده؟
- **EN:** 16 days, 130 commits, 117 PRs, 72 releases. This is Azm today. Tell me in the comments what I should build next.
- **Tags:** `#عزم_من_الصفر #IndieDev`
