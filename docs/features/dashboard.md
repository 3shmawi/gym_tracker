# Feature: captain web dashboard (`dashboard/`)

> Step 0 of the delivery plan in [`../decisions/gym_accounts.md`](../decisions/gym_accounts.md) §13
> and the hosting rule in §7: a plain web app on **its own origin**
> (`https://azmm-dash.pages.dev`), not Flutter web. Phases **D0** (sign in,
> list the gyms you run), **D1** (members and invite codes), **D2** (exercise
> pictures and videos), **D3** (a member's plan, copy a plan), **D4** (gym plan
> templates) and **D5** (trainee progress, gym settings) are built.

## Scope

| Phase | What | State |
|---|---|---|
| **D0** | Project, build and deploy, headers/CSP, sign-in by email code, session, "my gyms", members page shell (empty state), English + Arabic (RTL), light/dark | **built (this doc)** |
| **D1** | Members and invites: member list, add trainees, QR cards, permissions, end a member | **built (this doc, "D1 Members and invite codes")** |
| **D2** | Exercise media: gym-chosen pictures and videos (tables `gym_exercise_images`, `gym_exercise_videos`) | **built (this doc, "D2 Exercise media")** |
| **D3** | Plans: view and edit a member's plan through `save_plan`, copy a plan to other members | **built (this doc, "D3 A member's plan")** |
| **D4** | Plan templates: save, rename, delete, replace a plan with one, what changed and Reset, apply a change to everyone on a template (backend: migration 0019) | **built (this doc, "D4 Gym templates")** |
| **D5** | Progress (the `member_*` views, [trainee_dashboard_data.md](trainee_dashboard_data.md)) and gym settings (name, logo, history after a membership ends) | **built (this doc, "D5 Progress and gym settings")** |

D0 to D3 add **no** migration, no RPC and no table; they only use what
migrations 0005, 0006, 0007, 0008, 0013, 0015, 0016 and 0017 already allow.
D4 adds migration `0019_plan_templates.sql` (one table, two nullable columns
on `plans`, one RPC).

## Design
- Board: https://claude.ai/artifact/8dPMf6CPxewxFRgtjovg1P. D0 uses boards
  **0.1 to 0.5**; D1 uses **1.1 to 1.7**.
- Based on the Design System https://claude.ai/artifact/WUzyEppnEkcQXvVYec4m9H
  and the exercise media board https://claude.ai/artifact/VDxBpGdwNidSZgrGjfARJo
  (the app side of exercise media).
- D2 board: https://claude.ai/artifact/1hRNf6WxKvsmZ1vpK5S1YK (D2.1 to D2.4,
  approved Nov 2026: the exercise media boards cover the app only).
- Same rules as the app: no invented styles, Arabic and English (RTL with
  logical CSS), dark mode, loading / empty / error / offline states, touch
  targets of at least 48 px, labels for screen readers.

## Stack and pinned versions
Everything is pinned to an exact version in `dashboard/package.json` and
`dashboard/package-lock.json`. Node 22 (`dashboard/.node-version`,
`engines.node >= 22.12.0`).

| Package | Version | Why |
|---|---|---|
| `preact` | 11.0.1 | small UI library, no virtual-DOM extras |
| `@supabase/supabase-js` | 2.118.0 | Auth + PostgREST |
| `vite` | 8.3.4, `@preact/preset-vite` 2.10.6 | build and dev server |
| `typescript` | **6.0.3** | stays below 6.1: `typescript-eslint` 8.72.0 supports `<6.1.0` only |
| `eslint` 10.13.0, `typescript-eslint` 8.72.0, `@eslint/js` 10.0.1 | | lint |
| `vitest` | **4.1.12** | the first version that fixes GHSA-82fw-gwwq-j7x9 and GHSA-qxg6-89mg-rqv8 |
| `jsdom` | 30.1.3 | DOM for unit tests |
| `@playwright/test` 1.65.0, `@axe-core/playwright` 4.14.0 | | browser tests, accessibility; the CI image `mcr.microsoft.com/playwright:v1.65.0-noble` must be the same version |
| `minimatch` | **11.0.3** (npm `overrides`) | fixes GHSA-g3hv-75wg-m249 in a transitive dependency |

Lockfile note: `package-lock.json` was generated with **npm 11.21.1**,
because npm 10.9.9 crashes while resolving vitest 4.1's peer set. A plain
`npm ci` with npm 10 installs from the finished lockfile without problems
(Cloudflare's build image uses its own npm, which is fine for the same
reason). When you change dependencies, regenerate with npm 11.

## Architecture
```
dashboard/
  index.html, public/          shell (no inline script or style), icons
  build/headers.ts             writes dist/_headers (CSP and friends)
  vite.config.ts               validates the env, adds the headers plugin
  src/
    main.tsx                   start-up
    app/                       App (state wiring), router.ts
    core/                      config, supabase client, result/failure, text, prefs, online
    auth/auth.ts               email-code sign-in, session
    gyms/gyms.ts               the gyms the person manages
    exercises/                 D2: library copy, link parser, picture rules, media repository
    plans/                     D3: plan model and rules, edits, diff, save_plan repository;
                               D4: templates repository, differences from a template
    i18n/                      en.ts, ar.ts
    ui/ pages/ styles/         screens and styling
  test/                        unit tests (Vitest) and e2e (Playwright)
```
- **Result / Failure.** Nothing throws to the UI. Every call goes through
  `guard()` (`core/result.ts`) and returns `Result<T>` (`ok` or
  `{ ok: false, failure }`). `core/failure.ts` turns Supabase Auth, PostgREST
  and network errors into a small set of kinds (`offline`, `forbidden`,
  `session_ended`, `not_found`, `conflict`, `invalid`, `rate_limited`,
  `code_wrong`, `code_expired`, `server`). The UI shows a message per kind,
  never the server's text. Same idea as `guard` in the Flutter app.
- **Pages are thin.** Pages wire state to views that only take data and
  callbacks.
- **Routes** (`src/app/router.ts`, a tiny History API router):

| Path | Screen |
|---|---|
| `/` | home: sends a signed-in person to `/gyms`, otherwise to `/sign-in` |
| `/sign-in` | email, then the code |
| `/gyms` | the gyms you run (owner or captain) |
| `/g/<gym-uuid>/members` | members page (`/g/<gym-uuid>` is the same) |
| `/g/<gym-uuid>/members/<member-uuid>` | one member (D1) |
| `/g/<gym-uuid>/members/<member-uuid>/plan` | that member's plan (D3) |
| `/g/<gym-uuid>/members/add` | add trainees (D1) |
| `/g/<gym-uuid>/members/add-captain` | add a captain, owners only (D1) |
| `/g/<gym-uuid>/templates` | the gym's plan templates (D4) |
| `/g/<gym-uuid>/settings` | gym settings (D5) |
| `/g/<gym-uuid>/members/<member-uuid>/plan/{replace,copy,save-template}` | the member's plan with that quick-action dialog open (D3/D4) |
| `/g/<gym-uuid>/exercises` | the exercise list (D2) |
| `/g/<gym-uuid>/exercises/<library-id>` | one exercise's pictures and video (D2); an id that is neither in the library nor an `ex-…` plan id is "not found" |
| anything else | not found |

  The gym id must match the UUID pattern, otherwise the route is "not found";
  trailing slashes are ignored. Cloudflare Pages serves `index.html` for
  every path (single-page-app fallback, automatic while the build has no
  top-level `404.html`).

## Contracts used (migration 0005, no new RPC)
Read through the signed-in person's session; Row Level Security decides.

| Table | Policy that lets the dashboard read it |
|---|---|
| `people` | "read own person" (`id` where `auth_user_id` is me) |
| `memberships` | "read own memberships" (status `active`, role `owner` or `captain`) and "managers read gym memberships" (for member counts; needs `private.i_manage`) |
| `gyms` | "members read their gyms" (deleted gyms are hidden) |

`src/gyms/gyms.ts` does: `people` (my person id) then `memberships` joined
with `gyms` (`role in ('owner','captain')`, `status = 'active'`), then one
head-count per gym of memberships that are not `ended`. Writes and RPCs are
D1 (see "D1 Members and invite codes").

## D1 Members and invite codes
Boards **1.1 to 1.7**: the owner or captain sees who is in the gym, adds
trainees with a printed QR card each, changes what a trainee may edit, makes a
new code for someone who lost their phone, and ends a membership.

| Board | Screen | Code |
|---|---|---|
| 1.1 | Members: counts, tabs (All / Active / Waiting to join / Ended), search, role and status, "Can change" column; table on desktop, cards on a phone | `src/pages/MembersPage.tsx` |
| 1.2 | One member: name, role (owner only), permissions, status | `src/pages/MemberPage.tsx` |
| 1.3 | Member states: read-only for a captain looking at a captain or owner, ended, loading, error | `MemberPage.tsx`, `src/ui/states.tsx` |
| 1.4 | Add trainees (and, for owners, "Add a captain"): names, permissions, make codes, codes table, copy links | `src/pages/AddMembersPage.tsx` |
| 1.5 | Failures: partial add ("2 of 3 codes made", "Try again for 1"), recovery code refused because the person is in another gym (F), a code that was not made (G) | `AddMembersPage.tsx`, `MemberPage.tsx`, `src/ui/memberText.ts` |
| 1.6 | Print view: A4, 2 x 2 cards, English and Arabic lines | `src/ui/PrintSheet.tsx`, `src/styles/app.css` (`@media print`) |
| 1.7 | Names from Excel or CSV, or pasted | `src/ui/NamesImport.tsx`, `src/invites/namesFile.ts` |

### Contracts used (migrations 0005, 0006, 0008; nothing new)
Everything is decided by Row Level Security and the RPCs. `src/members/members.ts`
only asks, and the UI mirrors the rules so a refusal shows a message instead of
a crash. The rules are in the comments at the top of that file.

| What | Table / RPC | Policy or rule |
|---|---|---|
| Read members | `memberships` (`id, display_name, role, status, can_edit_targets, can_edit_plan, can_build_own_plan, joined_at, ended_at, created_at`, `gym_id = eq.<gym>`) | "managers read gym memberships" (`private.i_manage`, permanent session) |
| Read invites | `invites` (`id, membership_id, kind, created_at, expires_at, used_at, revoked_at`) | "managers read invites". **`code_hmac` is never selected** (no select grant, 0006) |
| Add a pending member | `memberships` insert (`gym_id, display_name, role, can_*, created_by = my person id`) | "managers add pending members": owners add captains, captains add trainees |
| Change a member | `memberships` update (`display_name`, `role`, `status`, the three flags) | "managers update members" + `private.i_manage_role` (owners change anyone, captains trainees only); `memberships_guard` keeps at least one active owner (`23514`, "a gym needs at least one active owner") and allows only `pending` or `active` to `ended`; `memberships_plan_implies_targets` (whole plan implies targets) and `memberships_flags_trainee_only` |
| Make a code | RPC `create_invite(p_membership_id, p_kind)`, kind `join` (waiting) or `recover` (new phone) | returns `{ invite_id, code, expires_at }`; older unused codes of that member stop working; `person_in_other_gym` (`22023`) for a recovery across gyms; `42501 forbidden` |
| Revoke a code | RPC `revoke_invite(p_invite_id)` | managers of that gym |
| Gym logo | Storage bucket `gym-logos`, object `<gym-id>/logo.png\|jpg` | "members read their gym logo" (0008) |
| My person id (for `created_by`) | `people` where `auth_user_id` is me | "read own person" |

An `update` that RLS filters out changes 0 rows and raises no error, so the
dashboard asks for the row back (`select('id')`) and treats "nothing came back"
as forbidden. Every refusal becomes a fixed message per failure kind; the
server's own text is never shown.

### The code-once rule
The plain code comes back from `create_invite` **once** (the server keeps only
an HMAC). The dashboard keeps it **in component memory only**: never in the URL,
`localStorage`, `sessionStorage`, a cookie, a log or an event. A page reload or
leaving the page loses it, and the answer is "make a new code" (the older one
stops working). While codes are on screen the page warns before leaving:
- on the add page, "All members" and "Done" open a Stay / Leave dialog;
  everywhere else (header brand and navigation, "All members" on the member
  page) the browser's `confirm` asks;
- browser Back/Forward asks as well (`useLeaveWarning`, `setLeaveGuard` in
  `src/app/router.ts`), and closing or reloading the tab triggers
  `beforeunload`.

### QR cards
Same rules as `scripts/make_invites` (decision `gym_accounts.md` §2 #4, §15):
- the link is `https://azmm.pages.dev/join/<code>` (code alphabet
  `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, 6 characters, checked with a regex before
  anything is drawn);
- error correction **level H**, smallest version that fits, quiet zone of 4
  modules;
- the logo box is **18 %** of the symbol's side (never above the 20 % limit;
  `logoBoxPx` throws above it). The logo is the gym's `gym-logos` picture, else
  the app icon (`/logo-96.png`), else none;
- **every QR is decoded again with `jsQR` before it may be printed**. A card
  whose QR does not read back is left out, the page says which one, and offers
  "Try again" and "Try without the logo". The print button only prints the cards
  that passed;
- layout: A4, 2 x 2 cards per page, gym name, the member's name, the QR, the code
  in large type, the scan and single-use lines in English and Arabic, and the
  link (`PrintSheet.tsx`, 4 cards per page, extra pages by `break-after`).

`scripts/make_invites` stays for the owner's command-line use (for example the
first captain, see "Owner bootstrap"); for captains the dashboard replaces it.

### Printing through the browser
"Print N cards" calls `window.print()`. The print sheet exists only between the
request and `afterprint`, and `@media print` hides everything else (header,
navigation, the screen content). To get a PDF choose **Save as PDF** as the
printer. The QR is a `<canvas>` (the one that was drawn and read back), so no
`blob:` or `data:` URL is needed and the CSP (`img-src 'self'`) is unchanged.

### Names from Excel, CSV or paste
Read in the browser; **nothing is uploaded**.
- `.xlsx` and `.csv` only, up to **1 MB** (checked on `file.size` and again on
  the bytes). `.xls` gets "save it as .xlsx"; a password-protected workbook (an
  OLE file with an `.xlsx` name) says it has a password; other types say
  "wrong type".
- `.xlsx` is a zip: unzipped with `fflate` through a **filter** that takes only
  `xl/workbook.xml`, its rels, `xl/sharedStrings.xml` and `xl/worksheets/sheetN.xml`,
  and stops if the unzipped size is over 20 MB (a zip bomb cannot fill memory).
  XML is parsed with the browser's `DOMParser` (data only, no external entities).
  Only the **first sheet** is read, up to 5000 rows and 26 columns.
- `.csv`: UTF-8 (BOM allowed), delimiter `,` `;` or tab picked from the first
  line, quoted cells.
- The person picks the column, says whether row 1 is a title, and may start at a
  later row (more than 50 names: the first 50 go in, the page names the row to
  start at next time). Every cell goes through `cleanName` (hidden direction and
  control characters removed). Empty cells and repeated names are reported, not
  hidden; names over 40 characters are marked by line.
- Pasting a column from Excel works too (cells arrive one per line, tabs between
  columns: the first column is used).
- Limits of one batch: 50 names, 1 to 40 characters each.

### New dependencies (checked 2026-11-04, no OSV advisories)
| Package | Version | Used for |
|---|---|---|
| `qrcode-generator` | 2.0.4 | the QR matrix (level H) |
| `jsqr` | 1.4.0 | reading each QR back before printing |
| `fflate` | 0.8.3 | unzipping `.xlsx` with a size cap |

All three are pinned exactly in `dashboard/package.json` and the lock file, run
in the browser only, and make no network request.

### Events
**None.** D1 sends no analytics and no feature flag calls (the dashboard still
has no PostHog or Sentry). Names and codes are personal data and are never put in
logs.

### D1 tests
- `dashboard/test/members.test.ts`, `members-ui.test.tsx`, `qr.test.ts`,
  `namesFile.test.ts`: repository calls and failure mapping, the pages with a
  fake repository, QR round trip and logo limit, file parsing (zip bomb cap, OLE,
  CSV delimiters, hostile cells).
- `dashboard/e2e/members.spec.ts` (list, tabs, search, who sees "Add a captain"),
  `member.spec.ts` (permissions, read-only, end membership dialog, last-owner and
  RLS refusals, new and recovery codes, locked-history wording),
  `add-members.spec.ts` (the add-trainees demo, partial failure and retry, leave
  guard, Excel/CSV/paste import, print view and PDF),
  `members-a11y.spec.ts` (axe on every D1 screen in English light and Arabic dark,
  keyboard) and `members-security.spec.ts` (hostile names, no request leaves the
  site, no code in storage or the URL). The fake Supabase
  (`e2e/fixtures/supabase.ts`) keeps members and invites per test and can make
  one insert, `create_invite` or `PATCH` fail.

### Demo & post (D1)
- **Hook:** "Add your whole gym in a minute: type the names, print a QR card for
  each."
- **Scenario** (the Playwright `add-members.spec.ts` "add trainees (the demo)"
  test, Supabase mocked): open Members, press "Add trainees", type three names
  (one Arabic), pick what trainees can change, make the codes (progress shown),
  copy the links, "Check and print" (every QR read back), and open the print view
  with the A4 page of cards in English and Arabic.
- **Caption (EN):** "New in the Azm captain dashboard: type your trainees' names,
  get a single-use QR code for each, and print the cards. Every QR is checked
  before it prints. Hand one to each trainee, they scan it, done."
- **Caption (AR, Egyptian):** "جديد في لوحة الكابتن بتاعة Azm: اكتب أسامي المتدربين
  واطلع لكل واحد كود QR يتستخدم مرة واحدة، واطبع الكروت. كل QR بيتفحص قبل ما
  يتطبع. إدّي كل متدرب كارته، يعمل سكان وخلاص."
- **Hashtags:** #Azm #GymApp #BuildInPublic #QRCode #Preact #Egypt

## D2 Exercise media
Boards **D2.1 to D2.4** (link above): the owner or a captain picks the pictures
and the how-to video the gym's members see for each library exercise. The app
already shows them (`gym_exercise_images.md`, `exercise_videos.md`).

| Board | Screen | Code |
|---|---|---|
| D2.1 | Exercises: all 36 library exercises (both names, muscle, the gym's cover), search (English, Arabic, id), filters All / Has your media / No video, a summary line | `src/pages/ExercisesPage.tsx` |
| D2.2 | One exercise: the chosen pictures (cover first, move earlier/later, remove, remove all, undo), search the 538-picture library with both frames of a move side by side ("Add both"), save; the gym's video (paste a link, see the id, save, remove, open on YouTube) | `src/pages/ExercisePage.tsx`, `src/ui/Picture.tsx` |
| D2.3 | Arabic RTL in dark: a refused link, the 6-picture limit | same |
| D2.4 | States: loading, nothing found, no pictures yet, error with retry, offline, saved, refused | same, `src/ui/states.tsx` |

### Where the exercise list comes from
The library lives in the app (`lib/features/library/data/exercise_catalog.dart`
and `exercise_videos.dart`; decision doc §20, "`ExerciseLibrary` is the seam").
There is no table for it, so the dashboard keeps a **generated copy**:
`node scripts/library_from_dart.mjs > src/exercises/library.ts` (ids, both
names, muscle, whether the library has a video). `test/library.test.ts` fails
when the copy drifts from the Dart files, so a new library exercise is one
command away. Today: **36 exercises**, 23 with a library video (the 13 added for
days 4 and 5 have none yet). Exercises written into a plan (`ex-…` ids)
show in D3's plan editor (with the gym's cover if one was saved for that id).

**Exercises written into plans (follow-up to D2).** The Exercises tab lists
them after the 36 library exercises, marked "Written by you", with no muscle
group; they count in the summary and the "No video" filter, and search finds
them in both languages. `MediaRepository.customExercises(gymId)` reads the
gym's membership ids, then only `days:body->days` of their plans (≤ 500 rows),
and `customFromDays` keeps ids of the app's shape (`^ex-[a-z0-9]{1,20}(-n)?$`,
never a library id), one entry per id, names cleaned like the plan editor and
capped at 200. A failed read leaves just the library (quiet on purpose). The
route `/g/<gym>/exercises/ex-…` opens the same page as a library exercise
(pictures and video saved under that id); an `ex-` id no plan names and no
media row mentions is "not found". Tests: `test/media.test.ts` (extraction,
hostile entries, query), `test/router.test.ts`, `test/exercises-ui.test.tsx`,
`e2e/exercises.spec.ts`, `e2e/exercises-a11y.spec.ts`.

**Quick actions per member.** The wide members table has *Plan*, *Template* and
*Copy* buttons next to *Manage* for active members you can manage; the member
page's Plan card has *Open the plan*, *Replace with template*, *Copy to other
members* and *Save as template*. They are links to fixed paths
`/g/<gym>/members/<id>/plan/{replace|copy|save-template}`; the plan page opens
that dialog once and puts the address back to the plain plan (a reload does not
reopen it). Copy and Save-as-template open only when the member has a plan.
Phone cards still open the member page, where the same actions are. Tests:
`test/router.test.ts`, `e2e/templates.spec.ts` ("quick actions on a member").

**Simpler to get to (UX pass).**
- Member page order: the plan card (with its quick actions) and the progress come first, then phone recovery / codes / end membership, and the person's own name and permissions last.
- Members list: a "Needs you" row shows only when something needs doing: members without a plan (a button that filters the list to them, read with one `plans.versions` request for the active people you manage; a failure hides it) and expired codes (opens the Waiting tab).
- Phone: each card has a "more" button with Plan, Template and Copy, so the actions of the wide table exist on a phone too.
- Exercises: a "No pictures" tab next to "No video".

**Picture search cards in Arabic.** The English picture title and the two
frames keep their own left-to-right order inside the card (title isolated and
wrapped cleanly; "start of the move" then "end of the move" like a timeline),
so mixed Arabic/English no longer pushes the title to the far edge.

### Contracts used (migrations 0013, 0015, 0017; nothing new)
`src/exercises/media.ts` only asks; Row Level Security decides.

| What | Table / RPC | Rule |
|---|---|---|
| Read the gym's pictures | `gym_exercise_images` (`exercise_id, public_id, position`, `gym_id = eq.<gym>`, ordered, ≤ 1200 rows) | "members read …" (`private.my_role_in`) |
| Read the gym's videos | `gym_exercise_videos` (`exercise_id, video_id, start_seconds, end_seconds`, ≤ 300 rows) | same |
| Search the library | `exercise_images` (`public_id, exercise_key, frame, title_en`, `keywords=cs.{…}` (all the words), ≤ 60 rows; only when that finds nothing and there are two or more words, `keywords=ov.{…}` (any word, ≤ 400 rows, ranked by how many words match, cut to 60)) | public read (0013). Words are cleaned like the app (lower case, Latin/Arabic letters and digits, ≤ 5 words of ≤ 30) and sent as **values** of the array filter, never as SQL |
| Picture titles (alt text) | `exercise_images` (`public_id=in.(…)`, ≤ 6) | public read |
| Save an exercise's pictures | RPC `set_gym_exercise_images(p_gym_id, p_exercise_id, p_public_ids)` | one transaction replaces the list; array order = position, `[]` removes all; security invoker, `private.i_manage` (permanent session) |
| Set the video | `gym_exercise_videos` **update** (`video_id, start_seconds, end_seconds`) when the gym has one, else **insert** (`gym_id, exercise_id, video_id, start_seconds, end_seconds`) | insert/update policies (`private.i_manage`); a `23505` on insert (someone added one meanwhile) turns into an update, an update that changes no row into an insert |
| Remove the video | `gym_exercise_videos` delete (`gym_id`, `exercise_id`) | delete policy; members then see the library's video, if any |

**Not an upsert.** PostgREST's upsert writes every sent column in
`ON CONFLICT … DO UPDATE SET` (`src/library/PostgREST/Query/QueryBuilder.hs`,
`PostgREST/postgrest` main, read 2026-11-10), and 0017 grants `UPDATE` only on
`video_id`, `start_seconds`, `end_seconds`: an upsert carrying `gym_id` and
`exercise_id` would be refused with `42501`. Insert and update are each covered
by `supabase/tests/gym_exercise_videos_rls.test.sql`.

Before anything is sent the dashboard checks the gym id (UUID), the exercise
id (the tables' own pattern, and the route accepts library ids only), every
`public_id` (`exercises/[a-z0-9-]`), at most 6, no repeats, and the video id
and times (same rules as the database). Rows read back that break the rules are
dropped, never shown; titles go through `cleanName`.

**Errors** (one fixed message each, never the server's text,
`saveFailureKey` in `src/exercises/useGymMedia.ts`): `42501` → only the owner
and captains; `23514 too_many_pictures_in_gym` → 1,200 pictures;
`too_many_videos_in_gym` → 300 videos; `too_many_pictures` → the 6 limit;
`22023`/`23503` → refused, reload; offline; session ended; anything else →
nothing was changed, try again.

### Video links
`src/exercises/youtube.ts` implements the app's rules
(`lib/core/media/youtube_link.dart`) and runs the **same 55 shared vectors**
(`docs/features/youtube_link_vectors.json`, `test/youtube.test.ts`), plus
more hostile cases. The link is split by hand rather than with `new URL()`
(the browser's parser resolves `..`, punycodes hosts and decodes parts); dot
segments are refused. **Only the id** (and start/end seconds) is sent and
stored, never the link. The page shows "This is video `<id>`" with the start
and end before saving. Nothing is fetched from YouTube (no thumbnail, no
oEmbed); "Open on YouTube" is a plain link built from the id.

### Pictures and the CDN
URLs come only from `pictureUrl(cloud, public_id, size)`:
`https://res.cloudinary.com/<cloud>/image/upload/c_limit,w_160|640,f_webp,q_auto/<public_id>.png`,
the same fixed transformations as the app, so both use the same cached files.
The cloud name is the new **publishable** setting `VITE_CLOUDINARY_CLOUD_NAME`
(same value as the app's `CLOUDINARY_CLOUD_NAME`; `[a-z0-9][a-z0-9_-]{0,62}`,
else the build fails). Without it the pages work with plain tiles. With it the
CSP's `img-src` gains `https://res.cloudinary.com/<cloud>/image/upload/` only
(CSP Level 3 path matching, W3C WD 2026-10-27, read 2026-11-10). Images load
with `referrerpolicy="no-referrer"`; a picture that fails shows the plain tile.
Credit line: "Pictures: Everkinetic · CC BY-SA 4.0".

### States
Loading (skeleton), error with **Try again**, empty (no pictures yet, nothing
found, no exercise in this filter), offline (the global bar; what was loaded
stays, Search and Save are off with "Saving needs internet"), saved, refused,
the 6-picture limit. Unsaved picture changes say "Not saved yet." and leaving
the page asks first (`useLeaveWarning`, the same as D1's codes). Keyboard:
every action is a button; moving a picture keeps focus on that picture's move
button; removing one moves focus to the "Pictures" heading.

### Events
**None** (the dashboard has no analytics). Nothing about the gym's choices,
links or words is kept in the browser.

### D2 tests
- `test/youtube.test.ts` (the 55 shared vectors and 22 more hostile links),
  `test/library.test.ts` (the copy equals the generator's output, all 36 ids,
  the 23 videos; lookups, Arabic search folding; routes with hostile ids),
  `test/media.test.ts` (picture rules and URLs, search words, what each call
  sends and drops, the insert/update video path and its races, refusals before
  any request, failure messages), `test/exercises-ui.test.tsx` (both pages with
  a fake repository, English and Arabic, every state), `test/config.test.ts`
  and `test/headers.test.ts` (cloud name, `img-src`).
- `e2e/exercises.spec.ts` (main flow: list → pick pictures, order, cover, save →
  paste a link, save, change → reload → remove; remove all with the leave
  warning; error with retry; offline; refusals; the 6 limit),
  `e2e/exercises-a11y.spec.ts` (axe on 7 screens in English light and Arabic
  dark; RTL; keyboard-only flow), `e2e/exercises-security.spec.ts` (crafted ids
  in the URL, another gym, hostile rows and titles from the server, hostile
  links and search words, every request goes to the site, the project or the
  one picture path, the CSP, nothing stored). The fake Supabase answers the
  three tables, the RPC and the picture CDN.

### Deploy note
Add `VITE_CLOUDINARY_CLOUD_NAME` to the Pages project (Production and
Preview, Settings > Variables and Secrets) with the app's cloud name, and
redeploy. Until then the exercise pages work with plain tiles.

### Demo & post (D2)
- **Hook:** "Your gym's own pictures and video for every exercise, chosen in a minute."
- **Scenario** (`e2e/exercises.spec.ts`, main flow): open Exercises, pick Flat
  Dumbbell Press, search "dumbbell press", "Add both" frames, add the incline
  start frame and move it to the cover, save; paste a YouTube Shorts link, see
  "This is video …", save; reload and everything is there.
- **Caption (EN):** "New in the Azm captain dashboard: pick the pictures and the
  how-to video your members see for each exercise. Paste a YouTube link and
  they get it in the app."
- **Caption (AR, Egyptian):** "جديد في لوحة الكابتن بتاعة Azm: اختار الصور وفيديو
  الطريقة اللي أعضاء الجيم يشوفوها لكل تمرين. الصق لينك يوتيوب ويوصلهم في
  التطبيق."
- **Hashtags:** #Azm #GymApp #BuildInPublic #Supabase #Preact #Egypt

## D3 A member's plan
From a member's page, **Open the plan** (shown when the person may change it:
owners for anyone, captains for trainees; not for ended memberships). Board
"Dashboard 5" (copy) and "Dashboard 6" (targets in a table) of
https://claude.ai/artifact/26EDAr572B4Qr8eBLB4D75; the editor itself has no
board, so it follows those two boards and the app's plan editor
(`docs/features/workout.md` → "Plan editor").

| Screen | Code |
|---|---|
| Plan: day tabs (with exercise counts), the day's name in both languages, move/rename/delete the day, add a day; a table of exercises (gym cover or a dumbbell tile, both names, "Written by you" for `ex-…` ids) with sets, reps, rest, weight step, "Logged by" and "With next" edited in place; move/rename/delete per row; **Save plan** and **Undo changes** in a bar that stays at the bottom | `src/pages/PlanPage.tsx`, `src/ui/PlanDayView.tsx` |
| Add an exercise: **From the library** (D2's list of 36, search in both languages; one already in the day says so) or **Write your own** (Arabic and English, one is enough) | `src/ui/PlanDialogs.tsx` |
| Conflict: "Someone saved this plan while you were editing", what they changed and what you changed (by id: added, deleted, renamed, moved, targets), **Load the newest plan** | `PlanPage.tsx`, `src/plans/diff.ts` |
| Copy to other members: active and waiting members this person may write for, "Has a plan · will be replaced" / "No plan yet", a warning with the count, one save per member, results per member, **Try again for N** | `src/ui/CopyPlanDialog.tsx` |
| States: loading, error with retry, no plan yet (**Start a plan**: one day "Day 1 / اليوم 1"), a stored plan the dashboard can't read (shown, not editable), ended membership, offline (Save and Copy off), unsaved changes ("Not saved yet." and a warning before leaving) | |

### The rules (the same as the app and the server)
`src/plans/model.ts` and `src/plans/edit.ts` mirror `PlanLimits`, `PlanNames`,
`validatePlan`, `newPlanId` (`lib/features/workout/domain/usecases/plan_rules.dart`)
and `EditPlan` (`edit_plan.dart`), and `planProblem()` returns
`private.plan_problem`'s own words:
- 1–14 days; ≤ 30 exercises a day; names 1–40 characters in each language
  (counted like Dart's runes), cleaned to one line, control and direction
  characters removed; one language fills the other; sets 1–10, reps 1–100,
  rest 0–600 s (inputs step 15), weight step > 0 and ≤ 50 (choices 0.5, 1,
  1.25, 2, 2.5, 5; another stored value shows as its own choice); `unit`
  `kg` / `plate` / `reps`, written only when not kg; day and exercise ids
  `^[A-Za-z0-9_-]{1,64}$`, unique in their list; the body exactly
  `{days:[{id,name,exercises:[{id,name,sets,reps,rest,step,superset,unit?}]}]}`.
- **Size:** the server checks `octet_length(body::text)` ≤ 64 KB, and Postgres
  prints jsonb with a space after every `:` and `,`; `bodyBytes()` counts the
  same way. A full 14 × 30 plan with long Arabic names is over the limit; the
  page says so ("This plan is too big to save").
- **Ids never change and are never reused:** renaming keeps the id; a library
  exercise keeps the library id (so the member's history matches); a new
  day or written exercise gets `day-` / `ex-` and the time in microseconds in
  base 36, checked against every id in the stored plan, the draft and the
  ids issued in this session. A library exercise starts with the library's
  targets (`scripts/library_from_dart.mjs` now also copies them).
- **Supersets:** "with the next one"; the last exercise of a day never keeps it
  (moving or deleting its partner ends it); the first of a pair shows "After
  the pair" instead of its own rest.
- A stored body the dashboard can't read strictly is **not editable** (so it
  is never re-sent changed); the member still sees it in the app.

### Contracts used (migrations 0007 and 0016; nothing new)
| What | How | Rule |
|---|---|---|
| Read a plan | `plans` (`body, version, updated_by, updated_at`, `membership_id = eq.<id>`) | "read plans of my membership or my gym" (`private.can_read_plan` → `i_manage_role`: owners anyone, captains trainees) |
| Versions for the copy list | `plans` (`membership_id, version`, `membership_id = in.(…)`, ≤ 500) | same |
| Save | RPC `save_plan(p_membership_id, p_base_version, p_body)` only | security definer; `i_manage_role`; `private.plan_problem`; a manager's save always wins and bumps `version`; the app shows "Your captain updated your plan" |

Errors (fixed messages, `src/plans/text.ts`): `42501 forbidden` → you can't
change this member's plan; `22023 invalid_plan: <why>` → the server didn't
accept it (should not happen: the page checks the same rules first);
`P0001 plan_changed` → the conflict screen; offline; session ended; anything
else → nothing was changed.

**Conflicts: what the server does and doesn't do.** `save_plan` checks
`p_base_version` **only for a trainee**; for a manager it always saves. So
the dashboard reads the stored `version` right before it saves and stops with
`plan_changed` (nothing sent) when someone saved meanwhile; the server's own
`plan_changed` (two first plans at once) leads to the same screen. The gap
left is the moment between that read and the save. Closing it needs
`save_plan` to check the version for managers too, a backend change kept out
of D3 (see "Open points").

### Copy a plan (decision doc §20)
The **saved** plan is copied (Save first, the button says so). Each member gets
the same body, ids included, through `save_plan` with their own current
version (0 when they have none), one after the other; a member who has a plan
gets it replaced, after the warning; workout history is never touched. Results
are shown per member; **Try again for N** repeats only the failed ones.
Offered: members this person may write for (`canManage`: owners anyone,
captains trainees), not ended, not the source.

### Events
**None** (no analytics in the dashboard). Plans, names and drafts are kept in
memory only: nothing in `localStorage`, the URL or a log.

### Open points
- Server-side version check for managers (above): `apply_plan_template` (D4)
  has it; `save_plan` still doesn't. Adding it is an open question in
  [`../designs/plan_templates.md`](../designs/plan_templates.md).
- `updated_by` is shown as "Last saved by <name>" when that membership is in
  the list the person can read; otherwise only the date.

### D3 tests
- `test/plans.test.ts` (names, the body round trip, strict reading, the
  server's rules and size, ids, every edit, supersets, the diff in both
  languages, the repository: columns, crafted ids, version pre-check,
  `plan_changed`, refusals, copy), `test/plan-ui.test.tsx` (save, conflict,
  first plan, copy, error), `test/router.test.ts` (the plan route),
  `test/library.test.ts` (the library copy with targets).
- `e2e/plans.spec.ts` (main flow: member page → plan → edit targets, add from
  the library and by hand, reorder, superset, rename the day → save; the
  conflict path; copy to two members with a failure and retry; a first plan;
  error/refused/offline/leave; who sees the plan), `e2e/plans-a11y.spec.ts`
  (axe on 7 screens in English light and Arabic dark, RTL, keyboard, dialogs),
  `e2e/plans-security.spec.ts` (crafted ids in the URL, hostile and 41+
  character names, control characters, injection-like text, hostile stored
  plans, clamped numbers, every request goes to the site, the project or the
  picture path, nothing stored).

### Demo & post (D3)
- **Hook:** "Change a trainee's plan from your laptop, and copy it to the whole group."
- **Scenario** (`e2e/plans.spec.ts`, main flow and copy): open Ahmed's plan,
  4 sets on the press, add Barbell Back Squat from the library and a "Cable
  Fly" written by hand, pair it with the next one, rename the day, save; then
  copy the plan to Mona and Youssef.
- **Caption (EN):** "New in the Azm captain dashboard: edit any trainee's plan
  (days, exercises, sets, reps, rest) and copy it to other members in one go.
  They see 'Your captain updated your plan' in the app."
- **Caption (AR, Egyptian):** "جديد في لوحة الكابتن بتاعة Azm: عدّل خطة أي متدرب
  (الأيام والتمارين والمجموعات والعدّات والراحة) وانسخها لباقي الأعضاء مرة
  واحدة. هيشوفوا "الكابتن حدّث خطتك" في التطبيق."
- **Hashtags:** #Azm #GymApp #BuildInPublic #Supabase #Preact #Egypt

## D4 Gym templates
Spec (with the open questions): [`../designs/plan_templates.md`](../designs/plan_templates.md).
Boards "Dashboard 5" (Save as template, Replace with template) and
"Dashboard 6" (one change for one member, Reset, apply to everyone).

| Screen | Code |
|---|---|
| Plan page: **Save as template** (name in both languages, from the saved plan), **Replace with template** (pick one; the same warning and copy rule as D3), Copy | `src/pages/PlanPage.tsx`, `src/ui/TemplateParts.tsx` |
| Plan page: "From the template X. N changes for Y. Everything else follows the template." (N by id, D3's diff), "The template changed since…", "The template … was deleted"; rows that differ: "Template: 3 × 12 · 90 s" and **Reset** (that exercise back to the template, in the draft) | `src/plans/templateDiff.ts`, `src/ui/PlanDayView.tsx` |
| **Apply a change to everyone on this template…** (saved plan): pick the change; members (readable, not ended) whose plan came from the template; one `save_plan` each with their own version; skipped when they don't have that exercise; results per member, retry; "Change the template too" (default on, once) | `ApplyToAllDialog` in `src/ui/TemplateParts.tsx` |
| Templates page `/g/<gym>/templates` (menu "Templates"): name in both languages, size, last change; rename; delete ("plans made from it stay"); empty state; error with retry; offline | `src/pages/TemplatesPage.tsx` |

### Contracts (migration 0019)
| What | How |
|---|---|
| List | `plan_templates` (`id, name, body, version, updated_at`, `gym_id = eq.<gym>`, ≤ 50) |
| Save as template | insert `gym_id, name, body` only (the rest is set by the trigger); `23514 too_many_templates_in_gym` → "Your gym has 50 templates" |
| Rename / change body / delete | update `name` or `body`, delete; a row RLS hid (0 rows) → forbidden |
| Replace a member's plan | RPC `apply_plan_template(p_membership_id, p_template_id, p_base_version)` with the stored version; `plan_changed` → the conflict message |
| Which template a plan came from | `plans` (`template_id, template_version`) in its own query; "column/table missing" (`42703`, `PGRST204/205`, `42P01`) = no template, so the page works even if the dashboard deploys before the migration |
| Plans on a template | `plans` (`membership_id, version, body`, `template_id = eq.<id>`) |

### D4 tests
- `supabase/tests/plan_templates_rls.test.sql` (pgTAP, 56).
- `test/templates.test.ts` (rows, columns, insert payload, refusals before any
  request, the 51st, RLS-hidden rows, the RPC, the missing-migration fallback,
  differences, Reset, skipped members, the route), `test/plan-ui.test.tsx`.
- `e2e/templates.spec.ts` (save as template → templates page → rename →
  delete; replace → no changes → change → badge → Reset; apply to everyone with
  a skipped member and the template updated; a deleted template; before
  migration 0019; a stale version), `e2e/templates-a11y-security.spec.ts` (axe
  on 5 screens in English light and Arabic dark; crafted and foreign gym ids;
  hostile and malformed templates; 41+ characters and hidden characters in a
  name; requests; storage).

### Demo & post (D4)
- **Hook:** "One template, the whole gym: change it once, everyone gets it."
- **Scenario** (`e2e/templates.spec.ts`): save Ahmed's plan as "Push / Pull",
  start Youssef from it, give Ahmed 5 sets of Abs and see "1 change", apply
  that change to everyone on the template.
- **Caption (EN):** "New in the Azm captain dashboard: save a plan as a gym
  template, start members from it, see what you changed for each one, and push
  a change to everyone on the template."
- **Caption (AR, Egyptian):** "جديد في لوحة الكابتن بتاعة Azm: احفظ خطة كقالب
  للجيم، وابدأ منه الأعضاء، وشوف غيّرت إيه لكل واحد، وطبّق تغيير على كل اللي
  على القالب مرة واحدة."
- **Hashtags:** #Azm #GymApp #BuildInPublic #Supabase #Preact #Egypt

## D5 Progress and gym settings
Boards 10 ("trainee page": the panel "his workouts in this gym", the members
list's "last workout") and 12 ("gym settings") of
https://claude.ai/artifact/XjCnp9ZLUVZ57o7pJ7odBu (they open now; §21 said they
once didn't). Where the boards show nothing (charts, tables, states), the
screens follow the Design System and D0–D4.

### Progress (member page)
`src/ui/MemberProgress.tsx`, data `src/progress/` (read-only, no write).

| Shown | From (migration 0012, `security_invoker` views) |
|---|---|
| workouts, a week on average (since the first workout), level and best level, streak, weeks to the next level (or back to the best: "comeback"), first and last workout | `member_progress_summary` (`level, best_level, streak_weeks, comeback, weeks_to_next, workouts_total, first_workout_at, last_workout_at`) |
| last 12 weeks: bar chart of workouts per week with the "active (3)" line, and a table (week Sat–Fri, workouts, training days, sets done / planned, minutes, active) | `member_weekly_attendance` (`week_start ≥` 12 weeks ago); missing weeks are shown as 0 |
| recent workouts (10): date, day name (from the member's plan), time, sets done / logged / planned, skipped exercises by name, "New records: n" | `member_session_stats`, records counted from `member_exercise_progress` |
| weight progress: pick an exercise (gym cover tile from D2), line chart of the top weight per workout with records marked, and a table | `member_exercise_progress` (≤ 2000 rows) |
| members list: "Last workout" column (cards on a phone) | `member_progress_summary` (`membership_id, workouts_total, last_workout_at`, `gym_id = eq.<gym>`) |

- **Weeks** are the gym week of the app and the server (`private.gym_week`):
  Saturday to Friday by the date in `Africa/Cairo`, numbered from Saturday 1
  January 2000 (`src/progress/weeks.ts`). Labels read "Sat 7 Nov – Fri 13 Nov".
- **Numbers use Western digits** (like the app) in both languages, in the
  whole dashboard (product decision, D5): numbers in texts and dates format
  with `ar-EG-u-nu-latn` (`numberLocale()` in `src/i18n/index.ts`), and no
  Arabic text holds Arabic-Indic digits (checked by `test/i18n.test.ts`). A
  first plan's day is "Day 1 / اليوم 1".
- **Names:** exercises and days from the member's plan (D3), else the library
  (D2), else "An exercise no longer in the plan" / "A day no longer in the plan".
  A Move games round (`day_id` `move`) shows as "Move · push-up round
  (camera)" (`MOVE_DAY_ID`, kept in step with the app by `progress.test.ts`).
- **Limits shown, not hidden:** a null duration or planned count is "—", not 0;
  "planned sets are approximate" (compared with today's plan); "level counts
  gym workouts only"; "only workouts logged in this gym".
- **Who sees what** (RLS of the views): an owner sees everyone's, a captain
  trainees' only (the panel isn't shown for others); only while the
  membership is active.
- **States:** loading, error with retry, no workouts in this gym yet (solo
  workouts are never visible), waiting to join, ended (progress isn't shown
  for an ended membership; what the former member can read follows
  `history_after_end`).
- **Charts:** plain SVG, no library. Single series, so no legend; the colour
  token `--chart` (`#15803D` light, `#16A34A` dark) passed the dataviz palette
  validator (lightness, chroma, ≥ 3:1 against the surface) in both themes. Each
  chart has a text summary as its name, a tooltip per mark (bigger hit area),
  the same numbers in a table, and time running left to right in both
  languages. Records are a ring diamond, not colour only.

### Gym settings (`/g/<gym>/settings`, menu "Settings")
`src/pages/SettingsPage.tsx`, `src/gyms/settings.ts`.
- **Name:** 1–60 characters, cleaned like other names (control and direction
  characters removed, spaces collapsed); `update gyms set name` (the table's
  own check: 1–60 and trimmed).
- **Logo:** PNG or JPEG ≤ 512 KB. Checked in the browser **before any
  request**: the size, and what the first bytes are (PNG/JPEG signatures; an
  SVG or a renamed file is refused; the browser's type must not contradict the
  bytes). Then the picture is **decoded and drawn again** (≤ 512 px a side, same
  type), so only pixels are uploaded: no EXIF (camera, GPS place, time). The
  object path is `<gym_id>/logo.png|jpg` from the gym id and the checked type,
  never from the file name; `upsert`, then `gyms.logo_path`, then the old
  object under another extension is removed. Remove = `logo_path = null`, then
  the object. The preview is drawn on a canvas (like the QR cards), so the CSP
  is unchanged (no `blob:`/`data:`).
- **History after a membership ends:** two choices with plain explanations
  (readable: the former member can open what they logged here, nothing new;
  locked: hidden from them, never deleted, back if they rejoin).
- **Who:** the **owner** changes them. A **captain** sees the same page
  read-only (name, logo, the history choice and a note "Only the gym owner can
  change these settings"), as board 12 shows: no field, no button, no request
  that writes. The database enforces the same since migration
  `0020_gym_settings_owner_only.sql`: `update (name, logo_path,
  history_after_end)` with "owners update their gym" = `private.i_own`
  (active owner, permanent session), and the `gym-logos` insert / update /
  delete policies use `private.i_own` too (reading is unchanged). A refusal
  (RLS returns no row) says "You can't change this gym's settings". After a
  save the gym list reloads quietly (header and switcher follow).
- **States:** saved / refused per section, offline (everything off), errors
  with fixed messages.

### Events
**None** (no analytics in the dashboard).

### Needs a backend step
- **Rest overruns** are not shown: they are not stored
  (trainee_dashboard_data.md → "What is NOT stored yet").
- **Planned vs done per week** is approximate (plans keep no history).
- **Progress of an ended member** is not readable by managers (the views and
  policies are active-only); if captains should see a former member's history,
  that is a policy change.
- (Done) **Captains and settings:** migration 0020 makes gym settings and
  logo writes owner-only on the server too (pgTAP
  `supabase/tests/gym_settings_owner_only.test.sql`).

### D5 tests
- `test/progress.test.ts` (the gym week and labels, Western digits, every view
  row with its nulls, chart data, the repository's columns and filters,
  crafted ids, the route), `test/settings.test.ts` (names with hostile input,
  61 characters, emoji; logo bytes/size/type checks, crafted file names, the
  object path; repository calls, RLS-hidden rows, old logo removal).
- `e2e/progress-settings.spec.ts` (progress with data, empty / waiting / ended /
  error states, the members list column; settings: rename, upload, remove,
  history, refused files before any request, hostile names, offline, a
  captain's read-only page with no write request),
  `e2e/progress-settings-a11y-security.spec.ts` (axe on 7 screens in English
  light and Arabic dark, RTL and Western digits, keyboard only; crafted ids,
  a foreign gym, a captain and the owner's progress, requests, storage). The
  fake Supabase answers the four views (with their visibility rules), `gyms`
  updates and `gym-logos` uploads (multipart, as supabase-js sends them).

### Demo & post (D5)
- **Hook:** "See who trains, how often, and how much stronger they got."
- **Scenario** (`e2e/progress-settings.spec.ts`): open Ahmed: 38 workouts,
  intermediate, the last 12 weeks, last workout, a new record on the dumbbell
  press; then Settings: rename the gym, upload the logo, lock history.
- **Caption (EN):** "New in the Azm captain dashboard: each trainee's progress
  (attendance, time, sets, records, weights and level) and your gym's name,
  logo and privacy setting in one place."
- **Caption (AR, Egyptian):** "جديد في لوحة الكابتن بتاعة Azm: تقدّم كل متدرب
  (الحضور، الوقت، المجموعات، الأرقام الجديدة، الأوزان والمستوى) واسم الجيم
  وشعاره وإعداد الخصوصية في مكان واحد."
- **Hashtags:** #Azm #GymApp #BuildInPublic #Supabase #Preact #Egypt

## D6 Gym brand colour
Spec: [`../designs/gym_brand_colours.md`](../designs/gym_brand_colours.md)
(approved 2026-11-11). The app side:
[`gym_brand_colours.md`](gym_brand_colours.md).

A **Brand colour** panel on the settings page (`src/ui/BrandColour.tsx`,
`src/gyms/brandColor.ts`, `GymSettingsRepository.setBrandColor`).
- **Pick:** the browser's colour input, a code field (`#RRGGBB`, any letter
  case, saved in lower case) and seven starting colours.
- **What the app will use:** a light and a dark sample with the generated
  button colour, the coloured text, and a sentence when the colour was made
  darker or lighter ("Buttons are 33% darker than your colour, so they show
  on light").
- **Readability check:** the three contrast ratios for light and dark
  (buttons against the background ≥ 3:1, text on buttons ≥ 4.5:1, coloured
  text ≥ 4.5:1). They always pass: the rule adjusts the colour, so the table
  explains, it does not block. Numbers are rounded down.
- **Refused before any request:** a code that is not `#` + six hex digits,
  and black, white and greys (channels less than 40 apart). A colour close
  to the error red gets a note, not a refusal.
- **Preview:** two small drawings of the app (light, dark) with three
  screens: home with exercise pictures, the workout with the pill, a sheet.
  With no colour, or a code that can't be saved, they show Azm's colours,
  as the app would.
- **Save** sends `{brand_color: '#rrggbb'}` only; **Reset to Azm colours**
  sends `{brand_color: null}`. RLS answering with no row is "You can't
  change this gym's settings".
- **Who:** the owner. A captain sees the saved colour, the samples and the
  preview read-only: no field, no button, no request that writes. The
  database agrees (migration `0021_gym_brand_color.sql` + the 0020 policy).
- **The same rule as the app.** `brandColor.ts` is a port of the app's
  `brand_color_rule.dart`; both are tested against
  `docs/features/brand_colour_vectors.json`, so the preview shows what the
  phone shows.
- **CSP unchanged.** A gym's colours reach the page as CSS custom
  properties set from script (`style.setProperty`), never a `style`
  attribute; an e2e test checks no CSP violation is reported.
- The dashboard itself stays in Azm's colours.

### Contract (migration 0021)
| Action | Request |
|---|---|
| Read | `brand_color` in the `gym:gyms(...)` list of the memberships query |
| Save / reset | `PATCH gyms?id=eq.<gym>` with `{brand_color}` |

### Events
**None** (no analytics in the dashboard).

### D6 tests
- `test/brandColor.test.ts`: the rule against the shared vectors (the
  luminance table, 64 colours × 2 modes), valid and hostile stored values,
  the guarantees on a sweep of the colour cube, what the owner types.
- `test/settings.test.ts`: only a valid colour or null is sent, alone;
  hostile values and a crafted gym id never reach the network; RLS = forbidden.
- `test/gyms.test.ts`: a bad stored value reads as no colour.
- `e2e/brand-colour.spec.ts` (desktop and phone): pick, samples, numbers,
  preview, save, reset; a saved colour on open; keyboard only; captain
  read-only; offline; hostile codes; the request body and target; another
  gym's id; a server refusal; no CSP violation; axe (WCAG 2.1 AA) for five
  states in English light and Arabic dark; Arabic right to left without
  page overflow.

### Demo & post (D6)
Hook: "One colour. Your gym's app."
Scenario: Settings → Brand colour → tap yellow → the two phones turn
yellow, the light one a darker gold with the reason written under it →
Save.
Captions: EN "Pick your gym's colour once. Azm makes it readable in light
and dark, and your members see it the next time they open the app." · AR
"اختار لون جيمك مرة واحدة. Azm بيظبطه يبان في الفاتح والغامق، وأعضاءك
يشوفوه أول ما يفتحوا التطبيق."
Hashtags: #Azm #GymApp #BuildInPublic #Preact

## Sign-in flow and session
1. **Ask for a code.** `signInWithOtp({ email, options: { shouldCreateUser: false } })`.
   The dashboard never creates users. An unknown address makes Supabase answer
   HTTP 422 `otp_disabled` ("Signups not allowed for otp"); the dashboard shows
   the same "check your email" screen as for a known address, so the page can't
   be used to find out who manages a gym.
2. **Type the code.** `verifyOtp({ email, token, type: 'email' })`. Six digits
   (Arabic-Indic digits are accepted and converted). Wrong or expired codes
   show their own message.
3. **Permanent session only.** `private.i_manage()` requires a permanent
   (non-anonymous) JWT. If the session is anonymous, the dashboard signs it out
   locally and shows the signed-out state; an anonymous session never manages.
4. **Session storage.** supabase-js keeps the session in `localStorage` under
   `sb-<project-ref>-auth-token`; `persistSession: true`,
   `autoRefreshToken: true`, `detectSessionInUrl: false` (a crafted address can
   never plant a session; sign-in is by typed code, never a link).
5. **Sign out** uses `scope: 'local'`: this browser only; the person's phone
   session is untouched.

Supabase behaviour (docs read **2026-11-04**,
https://supabase.com/docs/guides/auth/auth-email-passwordless and
https://supabase.com/docs/guides/auth/rate-limits):
- A **code** (not a link) is sent when the **Magic Link** email template
  contains `{{ .Token }}` and not `{{ .ConfirmationURL }}`.
- One request per address per **60 seconds**; a code expires after **1 hour**
  (Authentication > Sign In / Providers > Email > Email OTP expiration).
- Code length is 6 by default, configurable 6 to 10 (`auth.email.otp_length`).
  The dashboard expects **6** (`CODE_LENGTH` in `src/auth/auth.ts`); change
  both together.
- The built-in email service is limited to **2 emails per hour**: set up a
  custom SMTP server before real use.

## Data kept in the browser
Only two things, neither shown to anyone else:
- the supabase-js session (`sb-<project-ref>-auth-token`);
- `azm.dashboard.prefs.v1`: `{ lang, theme }`. No personal data.

Storage may be blocked (private window): the dashboard still works for that
tab; every access is guarded.

## Events
**None.** The dashboard has no analytics and no feature flags in D0 to D5 (no
PostHog, no Sentry, no cookies). Its only third-party requests are the
exercise pictures from the one Cloudinary path (D2). If that changes,
update this section, `website/privacy.html` and `store/privacy_forms.md` first.

## How to run
```bash
cd dashboard
npm ci
cp .env.example .env.local        # then fill the two publishable values
npm run dev                       # http://localhost:5173
npm run check                     # typecheck + lint + unit tests + build
npm run e2e                       # Playwright, Supabase is mocked, no network
```
`.env.local` holds `VITE_SUPABASE_URL=https://<project-ref>.supabase.co` and
`VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_…` (Supabase > Project settings >
API Keys). **Publishable values only**: they end up in the public bundle. The
build fails when either is missing, when the URL is not
`https://<20-character ref>.supabase.co`, or when the key looks secret
(`sb_secret_…`, or contains `service_role`); see `src/core/config.ts`. `.env*`
files are git-ignored except `.env.example`.

## Deploy (Cloudflare Pages, Git integration; for the owner)
Like the website, the dashboard is deployed by **Cloudflare Pages' own Git
integration**: no GitHub workflow and no Cloudflare API token in this repo.
**No GitHub secret is needed for D0.** Menu names below were read from the
docs on **2026-11-04** and may move
(https://developers.cloudflare.com/pages/configuration/git-integration/,
https://developers.cloudflare.com/pages/configuration/build-configuration/,
https://developers.cloudflare.com/pages/configuration/build-watch-paths/,
https://developers.cloudflare.com/pages/configuration/build-image/,
https://developers.cloudflare.com/pages/configuration/headers/).

**A. Create the Pages project (once)**
1. Cloudflare dashboard > **Workers & Pages** > **Create** > **Pages** >
   **Connect to Git**; pick `3shmawi/gym_tracker`.
2. **Project name:** `azmm-dash` (this gives `azmm-dash.pages.dev`; the name
   must be unique across Cloudflare, pick another and update the docs if it is
   taken).
3. **Production branch:** `main`. **Framework preset:** None.
4. **Build command:** `npm run build`. **Build output directory:** `dist`.
5. **Root directory (advanced) > Path:** `dashboard`. The output directory is
   relative to the root directory: check in the first deploy that
   `dist/_headers` and `dist/index.html` are picked up (verify in the
   dashboard preview).
6. **Environment variables**, added for **Production and Preview** (Settings >
   Variables and Secrets): `VITE_SUPABASE_URL`,
   `VITE_SUPABASE_PUBLISHABLE_KEY` and (D2) `VITE_CLOUDINARY_CLOUD_NAME`.
   Publishable values only. Add
   `VITE_TURNSTILE_SITE_KEY` (the Turnstile **site** key, publishable) as soon
   as CAPTCHA protection is on in Supabase (see C).
7. **Save and Deploy.** Node comes from `dashboard/.node-version` (22); the
   build image v3 default is Node 22.23.4.
8. **Settings > Build > Build watch paths > Include** `dashboard/*`, so only
   dashboard commits rebuild it. Optional: in the website project (`azmm`),
   include `website/*` so dashboard commits don't rebuild the site.

Things to know:
- A repo can have at most 5 Pages projects.
- Every PR and branch gets a preview URL (`<hash>.azmm-dash.pages.dev`,
  `<branch>.azmm-dash.pages.dev`) with `X-Robots-Tag: noindex` added
  automatically. Previews are **public** unless Cloudflare Access is turned on;
  they use the same Supabase project, so don't share them around.
- `_headers` (in `dist/`) allows 100 rules and 2,000 characters per line;
  `build/headers.ts` throws if a line is too long.
- Pages adds `Access-Control-Allow-Origin: *` by default; our `_headers`
  removes it (`! Access-Control-Allow-Origin`).
- A dashboard-only commit does **not** make a store release:
  `scripts/next_version.sh` ignores commits that change only `dashboard/`
  (`test/scripts/next_version.test.mjs`).

**B. Supabase dashboard (once)**
1. **Authentication > URL Configuration:** keep **Site URL** as it is if the app
   uses it. Add the Redirect URL `https://azmm-dash.pages.dev/**`. This is
   optional for code sign-in (codes don't redirect); keep it for safety.
2. **Authentication > Emails > Templates > Magic Link:** the body must contain
   `{{ .Token }}` and must **not** contain `{{ .ConfirmationURL }}`. Suggested
   text:
   - English: `Your Azm Dashboard code: {{ .Token }}. It works for 1 hour. If you didn't ask for it, ignore this email.`
   - Arabic: `كود دخولك إلى لوحة Azm: {{ .Token }}. يشتغل لمدة ساعة. لو إنت ما طلبتوش، تجاهل الإيميل ده.`

   (A template is one text per project: put both lines in the body.)
3. **Authentication > Sign In / Providers > Email:** provider enabled, **Email
   OTP expiration** `3600`, **OTP length** `6`.
4. **Authentication > Emails > SMTP Settings:** set up **custom SMTP** before
   real use. The built-in service sends 2 emails per hour.
5. Check the CSP once: the project ref in `dist/_headers` must be the one in
   `VITE_SUPABASE_URL`.

**C. Turnstile (when CAPTCHA protection is on in Supabase)**
Supabase's CAPTCHA protection covers "sign-in, sign-up, and password reset
forms" (https://supabase.com/docs/guides/auth/auth-captcha, read 2026-11-04),
so once it is on for the app's anonymous sign-in, the dashboard's "send me a
code" needs a Turnstile token too. **Order matters**, as for the app
(`docs/release.md` → Turnstile):
1. Cloudflare > **Turnstile** > the widget > **Domains**: add
   `azmm-dash.pages.dev` (next to `azmm.pages.dev`).
2. Cloudflare Pages > `azmm-dash` > Settings > Variables and Secrets: add
   `VITE_TURNSTILE_SITE_KEY` (Production and Preview) and redeploy. The build
   then adds `https://challenges.cloudflare.com` to `script-src` and
   `frame-src` (Cloudflare's CSP guidance,
   https://developers.cloudflare.com/turnstile/reference/content-security-policy/,
   read 2026-11-04); without the key the CSP keeps `frame-src 'none'`.
3. Only then turn CAPTCHA protection on in Supabase. With protection on and no
   site key, managers cannot sign in.

## Owner bootstrap: the first owner of a pilot gym
Sign-in uses `shouldCreateUser: false`, so a person who has never been created
**cannot** sign in to create themselves. The first owner is created by hand.
This is a runbook **you** run, in the **Supabase dashboard**; never from CI or
from a script in the repo.

1. **Authentication > Users > Add user** (create new user) with the owner's
   email, with **Auto Confirm User** on. (They get no password; they sign in
   with email codes.)
2. **SQL Editor**, replace the three placeholders and run:

```sql
-- Runs with the SQL editor's privileges (it bypasses RLS and column grants).
-- Run it by hand, once per owner. Never from CI or a script.
-- <email>: the owner's email as typed in step 1. <name>: 1 to 40 characters.
-- <gym-uuid>: public.gyms.id of the pilot gym (it must already exist).
insert into public.people (auth_user_id, display_name)
select id, '<name>' from auth.users where email = '<email>'
on conflict (auth_user_id) do nothing;

insert into public.memberships
  (gym_id, person_id, display_name, role, status, joined_at)
values (
  '<gym-uuid>',
  (select id from public.people
    where auth_user_id = (select id from auth.users where email = '<email>')),
  '<name>', 'owner', 'active', now()
);
```
   - The `memberships_person_matches_status` check requires a `person_id` for
     an `active` membership, which is why the person row comes first.
   - `unique (gym_id, person_id)` makes a second run fail, not duplicate.
   - Check: sign in on the dashboard with that email; the gym opens (or shows
     on "Pick a gym" when there are several) with the role Owner.
3. **Captains** are not made by SQL. In D1 the owner adds a captain on the
   dashboard and prints the code; the captain joins in the **app** with it
   (anonymous account), then adds an email in the app's Profile ("Add email",
   `updateUser`), and from then on signs in to the dashboard with that email.
   `private.i_manage()` only counts a permanent (email) session.

## Tests
- `dashboard/test/` (Vitest + jsdom): config (missing/secret/odd keys), failure
  mapping, text cleaning (bidi and control characters, email, code), router
  (UUID only, hostile paths), auth (no enumeration, anonymous refused), gyms,
  headers (CSP exact, `_headers` limits), pages.
- `dashboard/e2e/` (Playwright + axe, Supabase mocked, no network): sign-in
  flow, wrong code, offline, Arabic RTL, dark mode; D1 to D3 specs are listed
  under "D1 tests", "D2 tests" and "D3 tests".
- Locally, the Playwright browser can be a preinstalled Chromium:
  `PW_CHROMIUM=/path/to/chrome npm run e2e`.
- `test/security/dashboard_test.dart` (Flutter side, static guards) and the
  OSV scan of `dashboard/package-lock.json`; see
  [`../security.md`](../security.md) → "Captain dashboard".

## Demo & post
- **Hook:** "Your gym, from your laptop: sign in with a code, no password."
- **Scenario** (the Playwright sign-in flow, Supabase mocked): open the
  dashboard, type the owner's email, get the code, type it, land on "My gyms"
  with the gym card and its member count, open it, switch to Arabic (the page
  flips to RTL) and to dark mode.
- **Caption (EN):** "Azm now has a captain dashboard. Sign in with a one-time
  code, see your gyms, and soon invite members with a QR card. No passwords."
- **Caption (AR, Egyptian):** "لوحة الكابتن بتاعة Azm وصلت! تدخل بكود على
  إيميلك من غير باسورد، وتشوف جيماتك، وقريب تدعو الأعضاء بكارت QR."
- **Hashtags:** #Azm #GymApp #BuildInPublic #Supabase #Preact #Egypt

## What's next
All planned phases (D0–D6) are built. Open items are listed in each phase's
"Open points" / "Needs a backend step" and in
[`../designs/plan_templates.md`](../designs/plan_templates.md).
