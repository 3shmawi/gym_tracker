# Feature: exercise picture library (Cloudinary)

Every usable drawing of the Everkinetic set (538 pictures of 269 exercises),
hosted on Cloudinary, with the words people search by stored in the database.
A captain adding an exercise (web dashboard) searches by word and picks one
or several pictures. The app's bundled pictures for the 23 library exercises
(`docs/features/exercise_images.md`) stay as they are: they work offline.

**This change = data + tooling + docs.** Not here yet (next changes): the
dashboard's picker, the cache in the app and on the web, Arabic exercise names.

## How it fits together
```
everkinetic/data @ SOURCE_COMMIT  ──build.py──▶  package/{png/, images.json, seed.sql}
                                                   │             │
                              upload.py (workflow) ▼             ▼ committed
                              Cloudinary azm/exercises/…     migration 0014 → table exercise_images
```
- **Source**: `src/exercises/<id>/` of [`everkinetic/data`](https://github.com/everkinetic/data),
  pinned to one commit (`SOURCE_COMMIT` in `tool/exercise_images/build.py`; the
  script refuses any other). `images-png-unknown` and `images-ai` are never read.
- **Package** (`tool/exercise_images/build.py`, needs Pillow): each drawing
  becomes a transparent mask (dark lines black and opaque, paper transparent,
  1024 px max), so the picture has no background and is tinted by the page or
  app. Names: `ek-<id>-tension.png` and `ek-<id>-relaxation.png` (the two
  positions of the move).
- **Cloudinary**: public id `azm/exercises/ek-<id>-<frame>`. Public URL (from
  Cloudinary's docs):
  `https://res.cloudinary.com/<cloud name>/image/upload/<transformations>/<public id>.png`.
  Ask for the size and format in the URL, e.g. `w_400,f_auto,q_auto`; Cloudinary
  caches the result on its CDN.
- **Database**: table `exercise_images` (migration 0013) and its rows
  (migration 0014, generated: `seed.sql`).

## The table `exercise_images`
`public_id` (primary key), `exercise_key` (`ek-0055`), `frame`
(`tension`/`relaxation`), `title_en`, `keywords text[]` (English and Arabic),
`muscle_groups` (`chest`/`back`/`shoulders`/`arms`/`legs`/`core`, the same as
the app's library), `muscles`, `equipment`, `exercise_type`, `source_url`,
`source_commit`, `license`, `author`, `attribution`.
- **Search** with the GIN index: any word `keywords && array['chest', 'دمبل']`,
  all words `keywords @> array['chest', 'dumbbell']`.
- **Keywords** come from the repo's own data (title, muscles, equipment, type)
  plus a fixed English-to-Arabic table for muscles, groups and equipment in
  `build.py` (nothing guessed per exercise). Arabic exercise *names* are not
  included: they need a person who writes them.
- **RLS**: everyone can read; nobody but the service role can write (no write
  policy, no grant). Checks in the table refuse a licence outside CC0 / CC BY /
  CC BY-SA, and a public id that is not `azm/exercises/<a-z0-9->`.
  `supabase/tests/exercise_images_rls.test.sql` proves it.

## Licence (the pictures)
All 538 are Everkinetic drawings under **CC BY-SA 4.0** (the repo's
`LICENSE.md`; wger and Wikimedia Commons list the same drawings as 3.0). We
change them (transparent, resized), so the changed files are shared under the
same licence, and **wherever a picture is shown its author and licence must be
reachable** (`attribution` is stored per row for this). Not verified: the
author's own site could not be read. More in `exercise_images.md` ("Where the
pictures come from").

## Set-up and upload (once)
1. GitHub → Settings → Environments → new environment **`cloudinary`**
   (optionally: required reviewers). Add these **environment secrets**:
   `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`
   (Cloudinary console → API keys). Nothing else is needed; nobody else sees them.
2. Actions → **Exercise images** → Run workflow → tick **upload**. It builds the
   package, uploads (`overwrite=false`: running it twice is harmless), then checks
   that every picture's public URL answers. The log shows counts and public ids
   only.
3. The table fills when the migrations deploy on merge (`supabase.yml`).

A pull request that touches the tool runs the same build and validation with no
secrets, and fails if `0014_exercise_images_seed.sql` is not what the script
builds today.

## Cloudinary: what was read (2026-11-03)
- Signed upload: `POST https://api.cloudinary.com/v1_1/<cloud name>/image/upload`;
  sign the fields (not `file`, `cloud_name`, `resource_type`, `api_key`) sorted
  and joined as `name=value&…`, append the API secret with no separator, hash
  with SHA-1 (default; SHA-256 is also supported); valid one hour.
- Pricing page: Free plan = "25 monthly credits"; one credit = 1 GB managed
  storage, or 1 GB image bandwidth, or 1,000 transformations. No separate
  storage, bandwidth, file-size or asset-count figure is shown for Free. Plus
  starts at $99 a month ($89 yearly). Our 538 files are about 27 MB.
- Compared with Supabase Storage (checked the same day): free 1 GB storage, 5 GB
  egress, but image transformations only on Pro. Chosen: Cloudinary (decision
  of the project owner), mainly for transformations from the URL.

## Tests
- `test/security/exercise_image_library_test.dart`: the table (RLS, no write
  policy, licence list, public id), the seed (one statement, reviewed commit,
  licence, author, attribution, Arabic words, no smuggled SQL), the tool
  (secret from the environment only, never printed, only `src/exercises`), the
  workflow (manual, in the environment, no `pull_request_target`, no secret in
  the PR job) and the upload script against hostile input (crafted public ids
  and licences, duplicates, missing files, bad cloud names, no credentials).
- `supabase/tests/exercise_images_rls.test.sql` (pgTAP, runs in CI).

## Analytics events
None.
