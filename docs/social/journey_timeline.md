# Azm: the build journey (timeline)

The facts behind the «من الصفر لحد النهارده» build-in-public series
(`docs/social/journey_series.md`). Every line has a source in this repo: a
commit, a PR, or a file in `docs/`. Nothing here is estimated. If something
is not in the repo, it is listed under "Open questions" and stays out of the
videos until the owner answers.

Collected 2026-11-16 from `main` at `15ca14c` (full clone, `git fetch --unshallow`).

## Numbers (how each one was counted)

| Number | Value | Command / source |
|---|---|---|
| Days from first to last commit | 16 (2026-10-31 → 2026-11-15) | `git log --reverse --format=%ad --date=short` |
| Commits on `main` | 130 | `git rev-list --count HEAD` |
| Merged PRs | 117 of #1–#124 (4 closed without merge; #10, #66, #67 not closed) | GitHub `list_pull_requests state=closed` |
| Tagged releases | 72 (`v0.1.0` on 2026-11-01 → `v0.57.2` on 2026-11-15) | `git tag -l 'v*'` |
| Flutter tests (test / testWidgets calls) | 1,649 in 164 files | `grep -rEo "^\s*(test\|testWidgets)\(" test integration_test` |
| Dashboard tests (it / test calls) | 234 | same grep in `dashboard/` |
| Screen variants per screen test | 32 (devices × EN/AR × light/dark × text 1.3) | `b19a406`, `docs/design.md` → "UI testing" |
| Pages (`*_page.dart`) | 20 | `find lib -name '*_page.dart'` |
| App features (`lib/features/`) | 7: workout, gym, library, video, backup, move, settings | `ls lib/features` |
| Strings per language | 659 keys, English + Arabic | `lib/l10n/app_en.arb` |
| Supabase migrations / pgTAP test files | 21 / 25 | `supabase/migrations`, `supabase/tests` |
| GitHub workflows | 13 | `.github/workflows` |
| Dart lines in `lib/` (not generated) | ~42,500 | `wc -l` |

## Timeline

Each stop lists: what was done · why (the decision) · the problem or lesson ·
source · visuals available. "Store shot n" = `store/android/ar/images/phoneScreenshots/n.png`
(real screens, 1080×1920). "Golden" = a widget-test render in
`test/features/*/presentation/goldens/`.

### 0 · 2026-10-31: the start
- **Done:** project bootstrapped from flutter-project-kit: 310 files, 11,178 lines.
- **Why:** stack decided at creation: staging + prod, layered clean
  architecture, Riverpod, Supabase, Sentry, PostHog (no Firebase), go_router,
  Arabic + English (RTL), GitHub Actions on a public repo.
- **Source:** `247391e`, `docs/decisions/0001-initial-stack.md`.
- **Gap:** the "Why" section of 0001 is empty → open question 1.
- **Visuals:** the stack table, the folder tree from `CLAUDE.md`.

### 1 · 2026-11-01: design system + the first feature
- **Done:** workout plan, next-workout screen, one-tap set logging, rest
  timer, supersets, finish summary (#1). Same day: animated logo (#2), levels
  beginner/intermediate/pro (#5), progress per exercise (#7), start each
  exercise at last time's second set (#9). First release `v0.1.0`.
- **Why:** the product line in `CLAUDE.md`: "next session, last weight, quick
  logging". The home screen shows the next workout with ↑ increase / → keep /
  ↓ decrease (`docs/features/workout.md`).
- **Lesson:** on tablets text and spacing scaled 2.2× and button labels lost
  the app font. Fix: clamp the screen scale to 0.9–1.15 and add
  `screensUiTests`, 32 variants per screen (overflow, cut text, fonts, a11y,
  golden screenshots) (#1, `b19a406`).
- **Visuals:** store shots 1 (next workout), 2 (one-tap log), 3 (rest),
  4 (progress); `docs/design/workout_logging.html`; `docs/design/motion/`.

### 2 · 2026-11-02 → 04: the first real-phone bugs
- **Done:** "Rest over" notification with the phone locked (#12), edit the
  whole plan (#17).
- **Problem:** iOS killed the app while scrolling history. One "premium
  glass" card wrapped the whole history and captured the screen behind its
  whole height (#15, Sentry `GYM_TRACKER-12`). Fix: a flat card for tall lists.
- **Problem:** glass blur re-blurred the screen on every scroll frame; it
  cost 4–19× the raster time of the lite card. Fix: cards keep the glass
  look with blur 0; a repeatable perf workflow was added (`cb855d0`, #39,
  `docs/performance.md`).
- **Visuals:** store shot 8 (plan editor); code from `f1cdd93` / `cb855d0`.

### 3 · 2026-11-02 → 05: from solo to gyms
- **Decision:** solo mode stays with no account. A captain creates the
  trainee; the trainee joins by scanning a QR (`azmm.pages.dev/join/<code>`,
  single use, 7 days, 6-char code under it). Roles owner / captain /
  trainee. History belongs to the person. Later: the app has no captain
  tools; captains get a web dashboard (`docs/decisions/gym_accounts.md`, #19).
- **Done:** RLS tables + `redeem_invite` (#20), sessions / solo import /
  account deletion (#23), join page (#21), gym accounts in the app (#27),
  plan sync and "your captain updated your plan" (#29).
- **Problem:** joining timed out. The Turnstile web view's first load was
  blocked by its own allow-list on iOS, and Cloudflare Pages' 308 redirect
  dropped the code from `/join/<code>` (#60).
- **Visuals:** store shot 7 (joined a gym); goldens `join_*`, `joined_*`.

### 4 · 2026-11-03 → 04: exercises, pictures, videos
- **Done:** shared exercise library (#31), transparent exercise drawings with
  a licence page (#33), a picture library (#34, #36, #38), YouTube how-to
  videos (#40), a gym's own video (#46), a floating mini player (#48, #50).
- **Decision:** no picture-in-picture and no background audio. YouTube's API
  policy forbids a "background player" (`docs/decisions/video_outside_app.md`, #47).
- **Visuals:** store shot 6 (exercise screen); exercise drawings in `assets/exercises/` (Everkinetic, CC BY-SA 4.0).

### 5 · 2026-11-04 → 12: the captain's dashboard (web)
- **Done:** D0 email-code sign-in (#53), D1 members, invite codes, printed QR
  cards, names from Excel (#54), D2 exercise media (#72), D3 member plans
  (#73), D4 plan templates (#74), D5 trainee progress (#75), D6 gym colour
  with a readability check and live preview (#82). Members see the gym's
  colour in the app (#81).
- **Visuals:** no real dashboard screenshots in the repo. Drawn from tokens
  (marked as illustrative) or taken from the promo's dashboard scenes; gym
  colour goldens `gym_colour_*`.

### 6 · 2026-11-11 → 15: never lose your training
- **Before:** history was one JSON list in `SharedPreferences`, rewritten on
  every save and cut to the last 200 workouts (`docs/designs/never_lose_history.md`).
- **Done:** a local SQLite database with the whole history (#90), backup to
  the account (#91, #93), email-code sign-in (#94), restore on a new phone
  (#95), backup offered after the 3rd and 10th workout (#96), sign-out (#97),
  gym workouts back after a recovery code (#114).
- **Problem:** RLS lets owners and captains read their members' workouts,
  and select policies add up, so a captain who restored got their trainees'
  workouts in their own history. Fix: the restore names the person (#113).
- **Visuals:** goldens `backup_*` (20 states).

### 7 · 2026-11-12 → 15: Move games (the camera counts push-ups)
- **Done:** on-device push-up counting (#92), game screens and saving to
  history (#98), the Stack game and sounds (#99), privacy and store forms
  (#100), ML Kit on iOS (#101), counting out loud (#102), widest camera +
  zoom (#111).
- **Decision:** nothing about the camera leaves the phone; no recording; a
  manual counter for anyone without the camera. The idea came from a viral
  push-up-controlled clone of a tap-to-flap game, and nothing of that game is
  used (`docs/designs/move_games.md`).
- **Problems:** release builds crashed at launch since 0.48.0 (R8 removed
  Room's constructor, pulled in by ML Kit) (#104). The camera dropped behind
  the permission dialog (#105). A real OPPO phone was marked "too slow"
  while the owner was still sitting down (#106). Real push-up sets are
  replayed through the detector as pose recordings: joints and times only,
  never video (#103).
- **Visuals:** store shot 5 (the Stack game).

### 8 · Quality the whole way (2026-11-01 → 15)
- `screensUiTests` (32 variants), `test/security/` (secrets, cleartext,
  deep links), pgTAP RLS tests per table, gitleaks / OSV-Scanner / zizmor in
  CI, actions pinned to SHAs, coverage gate, Conventional Commits with
  release per merge (`CLAUDE.md`, `docs/security.md`, `docs/release.md`).
- Demo videos on demand from the integration tests (#11).
- **Visuals:** numbers table above; a CI-check diagram.

### 9 · 2026-11-14 → 16: ready for the stores
- **Done:** promo video (#112), store listing texts, screenshots and feature
  graphic in Arabic and English (#116), store uploads as code (#119–#124),
  three ready plans for a new member (#107).
- **Visuals:** all 8 store shots; `store/android/*/images/featureGraphic.png`;
  `docs/brand/promo_video/`.

## Open questions (for the owner; not used in videos until answered)
1. When and why did the idea of Azm come up? (0001 → "Why" is empty.)
2. Is the app live on the App Store / Google Play now, or in review?
3. Should the series say that the code was written with an AI coding agent?
   (The commits carry `Co-Authored-By` lines for one.)
4. Names in the video: which name/handle to show? (Commit authors and
   e-mails are not shown.)
