# Design: the gym's logo in the app

Status: **approved by the owner on 2026-11-14** ("agree, implement"), after an
EGM review the same day. PR 1: the backend (migration 0023). PR 2: the app.

Owner's ask: "I changed the logo but the app still shows the first letter of
the gym name; the name updated." Fallback chosen by the owner: with no logo,
the tile keeps the gym's letters, exactly as today.

## Goal

A member sees their gym's own logo wherever the app shows the gym's tile.
- When the owner replaces or removes the logo in the dashboard, the app
  follows the next time it comes to the front.
- After the first download it works offline.
- Nothing else about the gym changes.

## What exists today (checked in the code, 2026-11-14)

**Server**
- `gyms.logo_path` (0005:26-28) is `<gym_id>/logo.png|jpg|jpeg` or null.
- The file is in the private bucket `gym-logos` (0008):
  - 512 KB at most, png/jpeg only;
  - any member of a gym that is not deleted can read it, ended members too;
  - `anon` reads nothing;
  - only the owner writes (0020).
- pgTAP: `supabase/tests/gym_logos_storage.test.sql`.
- The update grant on `gyms` is asserted in
  `supabase/tests/gym_brand_color.test.sql:74`.
- `redeem_payload` (0021:46-69) returns `logo_path` but no version.

**Dashboard** (`dashboard/src/gyms/settings.ts:100-121`)
- `setLogo` re-encodes to at most 512 px a side.
- It uploads with `upsert: true`, `cacheControl: '60'` to
  `<gym_id>/logo.png|.jpg`, so **a replacement keeps the same path**.
- It then updates `logo_path` (often to the same value), and removes the
  old file if the extension changed.
- `removeLogo` sets null and deletes the file.

**App**
- `SupabaseGymRepository._fetchRows` (`supabase_gym_repository.dart:103-107`)
  selects `gyms(id, name, history_after_end, brand_color)`. These are
  explicit columns: no logo.
- `Gym.fromJson` drops `logo_path`, and `Membership.toJson`
  (`membership.dart:76-83`) writes only those 4 gym fields to the cache
  (`gym.memberships`, `maxMemberships = 50`).
- `Gym ==` leaves out `brandColor` on purpose, so a change of look does
  not restart the workout repository, the plan or the pictures
  (`gym.dart:45-52, 75-83`).
- **Memberships are refreshed only by `GymController.build()`**: a cold
  start or a session change (`gym_providers.dart:73-79`).
  - `GymSyncHost._run` (`gym_sync.dart:337-344`) runs on start, on resume
    and when the network returns, but only for the plan, media, uploads
    and backup.
  - So today a new **name or brand colour** also reaches the app only
    after a cold start. That is why the owner saw the name change and not
    the logo.
- `AppLogoTile` (`lib/core/ui/app_gym_controls.dart`) draws letters. It is
  used at `profile_view.dart:151`, `workspace_sheet.dart:96` and `:159`,
  and `joined_view.dart:39` (96 px).
- Patterns to copy:
  - `SyncGymMedia` + `GymMediaStore`: download, store on the phone, tell
    the UI;
  - `CachedMediaImage(url, fetch:)` (`media_cache.dart:78-113`);
  - the dashboard's PNG/JPEG signature check and `LOGO_PATH` rule
    (`settings.ts:30-47`, `gyms.ts:24, 62`).
- Clean-up on sign-out, session end and account deletion is done by
  `SignOut`, `HandleSessionEnded` and `DeleteAccount`
  (`end_account.dart`); all three call `GymLocalRepository.clear()`.

## Decisions

### 1. Knowing that the logo changed: a version set by the database

Migration `0023_gym_logo_version.sql`:
- `alter table gyms add column logo_updated_at timestamptz` (null when
  there is no logo).
- **Back-fill:** `update gyms set logo_updated_at = now() where logo_path
  is not null`, so logos uploaded before this migration get a version.
- `private.touch_gym_logo()` (`language plpgsql`, `set search_path = ''`)
  as a `before insert or update of logo_path` row trigger:
  - `NEW.logo_updated_at := case when NEW.logo_path is null then null else now() end`.
  - PostgreSQL (docs, CREATE TRIGGER): a column trigger fires when the
    column is "mentioned as a target of the UPDATE command", even with the
    same value. The dashboard always sets `logo_path` after an upload, so
    **the dashboard needs no change**.
  - It changes `NEW` only, so no `security definer` is needed.
- `logo_updated_at` is **not** in the update grant: only the trigger
  writes it.
- `create or replace redeem_payload` also returns `logo_updated_at`, so
  the join answer carries the version.

If an upload succeeds but the `update` then fails, the dashboard shows an
error and the version doesn't change. Retrying "set logo" runs the update
again. The 60 s `cacheControl` already limits a stale CDN copy, and
`cacheNonce` is a second guard.

Rejected: calling Storage `info(path)` and comparing its `etag` on every
refresh. That costs one more request per gym on every resume, and adds
another Storage endpoint the app depends on.

### 2. Following changes on resume (also fixes name and colour)

`GymSyncHost._run` also calls `GymController.refresh()`, then the logo
sync. At most one refresh runs at a time; a call made while one runs
joins it. So a new name, colour or logo reaches the app on resume and
when the network returns, not only on a cold start. This is a small
behaviour change for name and colour too: they are applied the way brand
colours already are (`docs/designs/gym_brand_colours.md` §8).

### 3. The model

- `Gym` gets `logoPath` (validated) and `logoVersion` (`DateTime?`).
- Both stay **out of `==` and `hashCode`**, like `brandColor`, so a new
  logo never restarts a workout.
- `Gym.fromJson` reads `logo_path` and `logo_updated_at`.
- **Path validation:** a path is kept only if it matches
  `^<this gym's id>/logo\.(png|jpe?g)$`. Anything else, including another
  gym's folder, is "no logo". This is the dashboard's `LOGO_PATH` rule
  plus its `startsWith(id/)` check.
- `Membership.toJson` writes both fields. An older cache without them
  reads as "no logo" until the next refresh.

### 4. Downloading and checking

- **Domain:** `GymLogoRepository` (`lib/features/gym/domain/repositories/
  gym_logo_repository.dart`) with
  `Future<Result<Uint8List>> fetch(GymLogoRef ref)`, where
  `GymLogoRef = (gymId, path, version)`.
- **Data:** `SupabaseGymLogoRepository`
  (`lib/features/gym/data/repositories/`):
  - calls `storage.from('gym-logos').download(path, cacheNonce:
    version.millisecondsSinceEpoch.toString())`;
  - goes through `guard()`.
- **Checks, in this order, before anything is kept** (in a pure
  `GymLogoCheck` in the domain):
  1. size 1 B–512 KB;
  2. PNG or JPEG signature (copied from `settings.ts:30-47`);
  3. the width and height read from the header with
     `ImmutableBuffer` + `ImageDescriptor.encoded`, **without decoding**;
     each must be between 16 and 2048 px (the dashboard writes ≤ 512);
  4. one frame.

  If any check fails: "no logo", the reason goes to monitoring (no path or
  id), and it is tried again at the next sync.
- **DI:** the repository and the store are wired in
  `core/di/dependencies.dart`; tests use in-memory ones (like
  `in_memory_gym_media.dart`).

### 5. Keeping it on the phone

- **Files.** `GymLogoStore` (`prefs_gym_logo_store.dart`, modelled on
  `PrefsGymMediaStore`) writes files to the app support directory.
  - The file name is `gym_logos/<gymId>-<versionMs>.img`. The version is
    in the name, so Flutter's image cache (keyed by path) **never shows an
    old logo** for a new one.
  - The gym id is a validated UUID and the version is an integer: nothing
    else goes into the file name.
- **Index.** `SharedPreferences` key `gym.logos` maps each gym id to its
  path, version and file name.
- **Order of writes:** write to `*.tmp`, rename, update the index, then
  delete the old file. An index entry whose file is missing, or a file
  with no entry, is cleaned up at the next sync.
- **Which gyms.** Logos are downloaded only for **active memberships**, at
  most 10 (constant `GymLogoStore.maxLogos`, at most about 5 MB). Ended
  memberships show letters.
- **Sync.** `SyncGymLogos` (a use case) runs after each refresh, one gym
  at a time: it downloads what changed and deletes what is gone. A sync
  already running is not cancelled; the next one sees the new index.
- **Clean-up.** `GymLocalRepository.clear()` also clears the logo store.
  That covers `SignOut`, `HandleSessionEnded` (including the 401 in
  `_redeem`) and `DeleteAccount`.

### 6. Showing it

- **Provider.** `gymLogoProvider(gymId)` watches the logo index, not the
  membership. It returns
  `ResizeImage(FileImage(file), width: side × devicePixelRatio)`, or null
  when there is no file.
- **Widget.** `AppLogoTile` gets `ImageProvider? image`:
  - the picture is clipped to the same rounded square, `BoxFit.cover`;
  - a 1 px border in `palette.separator`, so a white logo has an edge;
  - `errorBuilder` shows the letters (the owner's fallback);
  - the change from letters to the logo fades in 200 ms, with no fade under
    Reduce Motion.
- **Accessibility.** The tile stays in `ExcludeSemantics`, because the row
  already names the gym. No new strings.
- **Call sites.** All 4 pass the image. `joined_view` shows the letters
  until the first download, which starts right after the join, using the
  version from the join answer.
- **Out of scope.** Not in the app bar, notifications, splash or launcher
  icon (brand-colour design §3: Azm stays Azm).

### 7. Feature flag

`Flags.gymLogos` (PostHog `gym_logos`), off by default:
- with it off, there are no downloads and the tile shows letters;
- it is turned on for staging, then prod, after the app PR ships.

The refresh on resume (§2) is **not** behind the flag, because it is a fix.

### 8. Edge cases

| Case | Behaviour |
|---|---|
| No logo | Letters. |
| Logo removed | The next sync sees `logo_path = null`: the file and the entry are deleted, and the letters show. |
| Replaced, same type | `logo_updated_at` changes, so the logo is downloaded again under a new file name. |
| Replaced, other type | The path and version change, so the logo is downloaded again. |
| Offline | The stored file; with no file, letters. |
| Download or check fails | Letters; tried again at the next sync. |
| Ended member | Letters (only active memberships download). |
| Logo changes during a workout | Only the tile changes; the workout is not restarted (`==` unchanged). Tested. |
| Old app versions | Unaffected: they select named columns and ignore new fields. |
| Order | PR 1 (migration) is merged, and **Supabase deploy is green**, before PR 2 merges. The app selects `logo_updated_at`, which fails on an older database. Merging to `main` also releases to the stores. |
| A path for another gym, `../`, `.svg`, empty or very long | Refused by the path check. |
| A huge, animated or broken image | Refused by the header and frame checks before any full decode. |

### 9. Analytics

- **No new events.** `docs/features/gym_account_app.md` says so.
- The logo path is never in any event or error.

### 10. Security and privacy

- **No new permission and no new data from the member.** The logo is the
  gym's brand, already printed on its QR cards.
- **`website/privacy.html`:** one line under "Gym accounts" (English
  :66) and "حسابات الجيم" (Arabic :132): the app downloads your gym's logo
  from our server and keeps it on the phone.
- **`docs/security.md`:** a "Gym logos in the app" section covering the
  path rule, the header checks and the file names.

### 11. Tests

**pgTAP** (new file `gym_logo_version.test.sql`, plus extending
`gym_brand_color.test.sql:74`):
- the back-fill;
- the version is set on insert and on update of `logo_path`, even with
  the same value;
- it is cleared to null with the path;
- an update that doesn't name `logo_path` leaves it alone;
- the grant doesn't include it;
- `redeem_payload` carries it;
- `anon` still reads nothing.

**Unit:**
- `Gym` parsing and the path rule;
- `==` unchanged by the logo;
- the `Membership` JSON round trip with an old cache;
- `GymLogoCheck` with hostile bytes: empty, 513 KB, a GIF, a truncated
  PNG, a 20 000 × 20 000 header, an animated PNG;
- the store: tmp, rename and index order; a missing file; an orphan file;
  `maxLogos`; `clear`;
- `SyncGymLogos`: changed, same, removed, offline, only active
  memberships;
- refresh on resume: the joining of concurrent refreshes.

**Widget:**
- `AppLogoTile` with a logo, a failing image (letters), RTL, large text
  and dark;
- the fade, with and without Reduce Motion;
- `screensUiTests` for profile, the workspace sheet and joined, with a
  logo;
- a test that the workout survives a logo change.

**Integration:** a demo with `beat(tester)`: join a gym that has a logo,
see it on the welcome screen and in the workspace switcher.

**Security:** the hostile paths and bytes above, in `test/security/`.

### 12. PRs

1. **Backend:** 0023 + pgTAP + `docs/features/gym_accounts_backend.md`
   (tables and `redeem` payload).
2. **App:**
   - §2–§7 and the tests;
   - docs: `docs/features/gym_account_app.md` (remove "logos are not
     downloaded yet"; link this design under "Decisions & edge cases";
     "Demo & post"), `docs/security.md`, privacy (en + ar),
     `docs/release.md` (the flag), and `docs/README.md` if a new doc is
     added.

## Official docs checked (2026-11-14)

- pub.dev: `supabase_flutter` 2.18.3 and `storage_client` 2.8.1 are the
  latest. `download(path, cacheNonce:)` was read in the 2.8.1 source.
- PostgreSQL CREATE TRIGGER: an `UPDATE OF column` trigger fires when the
  column is a target of the UPDATE.
- To re-read before the code: Supabase Storage access control and
  downloads (supabase.com/docs/guides/storage), and Flutter
  `ImageDescriptor` / `ResizeImage`.

## Review

EGM goldfish reviews (design, codebase details, implementation readiness),
2026-11-14. All of their findings are folded in above. The main changes:
- the version is in the file name;
- a header check before any decode;
- a back-fill;
- the version in `redeem_payload`;
- `==` is unchanged;
- refresh on resume;
- only active memberships;
- clean-up through `GymLocalRepository.clear()`;
- a flag.
