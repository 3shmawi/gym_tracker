# Feature: gym-chosen exercise pictures

A gym's owner or captain picks pictures for an exercise from the shared picture
library (`exercise_images`, 538 Everkinetic drawings,
[`exercise_image_library.md`](exercise_image_library.md)). The gym's members see
them on the exercise screen. The app only **shows** them. Captains manage them
in the web dashboard (decision doc §20).

Design: https://claude.ai/artifact/VDxBpGdwNidSZgrGjfARJo (boards 1.1–2.1 and
5.1, approved Nov 2026).

| Stage | What | Status |
|---|---|---|
| P-A | Table, RLS, limits, pgTAP, the dashboard contract (this doc) | this change |
| P-B | Cloud name config, URL builder, image cache, offline copy, carousel, credit line, licenses page | next |

**This change is backend only.** Migration `0015_gym_exercise_images.sql` adds
one table, one trigger and one function, and changes nothing that exists.
When it deploys on merge (`supabase.yml`), the published app keeps working,
because it doesn't read the table yet.

## The table `gym_exercise_images`
| Column | Rule |
|---|---|
| `id` | uuid, generated |
| `gym_id` | the gym (`gyms.id`, cascade on delete). **The only column used for authorization.** |
| `exercise_id` | a library id (`^[a-z][a-z0-9_]*$`, e.g. `flat_db_press`) or a plan editor id (`^ex-[a-z0-9]{1,20}(-[0-9]{1,4})?$`, from `newPlanId('ex', …)`: `ex-<base36 time>`, plus `-<n>` after a clash); ≤ 64 characters. Anything else is refused (`23514`). |
| `public_id` | a picture of the library: references `exercise_images.public_id` (`exercises/ek-<id>-<frame>`); unknown → `23503`. If the library ever removes a picture, the gym's choice of it is removed too. |
| `position` | 1–6, 1-based order; 1 is the cover. Gaps are allowed; readers sort by `position`. |
| `updated_by` | `people.id` of who changed it last. **Set by the database**; the client cannot write it. |
| `created_at`, `updated_at` | set by the database |

Keys and limits, all enforced in the database, not only in the dashboard:
- `unique (gym_id, exercise_id, public_id)`: a picture once per exercise.
- `unique (gym_id, exercise_id, position)`, deferrable (checked at the end of
  each statement, so one `UPDATE` can swap two positions). With
  `position between 1 and 6`, this caps an exercise at **6 pictures**. Each
  frame is its own row and counts toward the 6.
- At most **1200 rows per gym** (200 exercises × 6), counted by a trigger under
  a per-gym advisory lock, so concurrent saves can't overshoot.

## Who can do what (RLS)
`revoke all … from anon, authenticated` first, then column grants:
`select, delete`; `insert (gym_id, exercise_id, public_id, position)`;
`update (position)`.

| Caller | Read | Add / reorder / remove / save |
|---|---|---|
| `anon` | no (no grant) | no |
| active trainee of the gym (often an anonymous user) | the gym's rows | no |
| ended or pending member | nothing | no |
| member (any role) of another gym | nothing of this gym | no |
| the gym's captain or owner, **permanent session** | the gym's rows | yes (`private.i_manage(gym_id)`) |
| captain signed in anonymously | the gym's rows | no (`i_manage` needs a permanent session) |
| service role | everything | everything |

Read = `private.my_role_in(gym_id) is not null`: an active membership in a
live (not deleted) gym. No new helper was added.

## Dashboard contract
The dashboard signs in as the captain (permanent session) and uses the Data
API (PostgREST) with the publishable key. It never sends a URL, only
`public_id`s it read from `exercise_images`.

### 1. Find pictures (table `exercise_images`, public read)
`keywords` holds English and Arabic words (lower case), with a GIN index.
- **Any word** (search box, OR): SQL `keywords && array['chest','دمبل']`;
  REST `GET /rest/v1/exercise_images?keywords=ov.{chest,دمبل}`.
- **All words** (AND, for "chest dumbbell"): SQL `keywords @> array['chest','dumbbell']`;
  REST `?keywords=cs.{chest,dumbbell}`.
- **Filters**: `muscle_groups` (`chest`/`back`/`shoulders`/`arms`/`legs`/`core`)
  and `equipment` are arrays: REST `muscle_groups=cs.{chest}`,
  `equipment=ov.{dumbbell,barbell}`.
- **Show both frames together**: group by `exercise_key` (`ek-0055`). Order
  `frame` as `tension` (start of the move), then `relaxation` (end).
- Select only what the picker shows: `select=public_id,exercise_key,frame,title_en,muscle_groups,equipment`.
  Lower-case the user's words and split them on spaces before the query; never
  build SQL from them.

### 2. Read a gym's choices
`GET /rest/v1/gym_exercise_images?gym_id=eq.<gym>&select=exercise_id,public_id,position&order=exercise_id,position`
(the app reads the same rows for its offline copy in P-B).

### 3. Save an exercise's list: preferred
One call replaces the whole list in one transaction, so readers never see half
a list:
```
POST /rest/v1/rpc/set_gym_exercise_images
{"p_gym_id": "<gym uuid>", "p_exercise_id": "flat_db_press",
 "p_public_ids": ["exercises/ek-0055-tension", "exercises/ek-0055-relaxation"]}
```
- The array order becomes `position` 1, 2, …. An empty array removes every
  picture of that exercise.
- "Add both frames" = add the `tension` and `relaxation` ids of one
  `exercise_key` to the list (two rows).
- The function is `security invoker`: the policies above still decide.

### 4. Single-row writes (allowed, same rules)
- Add: `POST /rest/v1/gym_exercise_images` with only `gym_id`, `exercise_id`,
  `public_id`, `position` (any other column → `42501`).
- Reorder: `PATCH …?id=eq.<id>` with `{"position": n}`. To swap two, use one
  statement that sets both; or use the RPC.
- Remove: `DELETE …?id=eq.<id>`.
- Upsert: only `on_conflict=gym_id,exercise_id,public_id`. The position key is
  deferrable, and Postgres doesn't accept deferrable keys as `ON CONFLICT`
  arbiters.

### 5. Errors the database returns
PostgREST maps the Postgres code to HTTP (PostgREST docs, "Errors"); the body
has `code` and `message`.

| `code` | HTTP | `message` / constraint | Meaning for the dashboard |
|---|---|---|---|
| `42501` | 403 (401 when signed out) | `forbidden`, or "new row violates row-level security policy", or "permission denied" | not a manager of this gym (or not a permanent session), or a column it may not write |
| `23514` | 400 | `too_many_pictures` (RPC) or constraint `gym_exercise_images_position_range` | more than 6 pictures for the exercise |
| `23514` | 400 | `too_many_pictures_in_gym` | the gym has 1200 pictures |
| `23514` | 400 | constraint `gym_exercise_images_exercise_id_format` | an exercise id that is neither a library id nor a plan id |
| `23505` | 409 | constraint `gym_exercise_images_one_per_picture` | that picture is already on the exercise |
| `23505` | 409 | constraint `gym_exercise_images_one_per_position` | that position is taken |
| `23503` | 409 | foreign key on `public_id` | not a picture of the library |
| `22023` | 400 | `duplicate_picture` / `invalid_list` (RPC) | same picture twice / a null, a nested array or a missing argument |

## How the app will use it (P-B, for reference)
Source order on the exercise screen: the gym's pictures by `position`, then the
bundled library picture, then the placeholder. Offline: the offline copy of
these rows (like the gym plan) plus the image cache. A failed picture is skipped
silently. Never an error screen.

## Security and privacy
- No personal data: `updated_by` is a `people.id`, readable only by the gym's
  members (as with the gym plan). Nothing here goes to analytics.
- No URL is stored. The app and dashboard build picture URLs from `public_id`
  with a fixed builder (P-B), so a crafted value can't point anywhere else, and
  the FK guarantees it is a library picture.
- Every function pins `search_path = ''`. The trigger function is
  `security definer` only to count the gym's rows in one index scan; the insert
  policy still decides whether the caller may add the row.

## Tests
- `supabase/tests/gym_exercise_images_rls.test.sql` (pgTAP, 55 checks; CI
  `supabase test db`):
  - roles: `anon`, active trainee, ended trainee, another gym's captain and
    trainee, an anonymous-session captain, the gym's captain and owner;
  - limits: the 7th picture (row and list), a duplicate position, the same
    picture twice, an unknown `public_id`, a URL in `public_id`, position 0, the
    1201st row of a gym;
  - crafted exercise ids: path, upper case, injection-like, Cyrillic look-alike,
    65 characters, `ex-`; plan ids with and without the clash suffix accepted;
  - the stamped and unforgeable `updated_by`; no moving a row to another gym or
    exercise; a one-statement swap; the RPC (order, replace, refusals, a refused
    save leaves the old list).
- `test/security/supabase_backend_test.dart` picks up the new table (RLS on,
  grants revoked, a pgTAP file, `search_path` pinned, function closed to `anon`).
- Before pushing, the migrations (0005, 0013–0015) and this test file were run
  on a local PostgreSQL 16, with Supabase's `auth` schema and the six pgTAP
  functions the file uses replaced by small stand-ins (55/55). The real check
  is CI: the Supabase stack (Postgres 17) with pgTAP.

## Docs read (2026-11-03)
`supabase.com`, `postgresql.org`, `pgtap.org` and `docs.postgrest.org` were not
reachable from the build environment (network policy), so the official sources
were read from their repositories:
- Supabase docs `apps/docs/content/guides/database/postgres/`
  (`row-level-security.mdx`, `column-level-security.mdx`), `supabase/supabase`
  at `a26ee8b` (2026-11-03): revoke the default grants (policies don't remove
  them), wrap helpers in `(select …)` for an initPlan, index the columns policies
  filter on (leading column of a btree), `security definer` runs as the
  function's owner.
- PostgreSQL 17 docs (`postgres/postgres` `REL_17_STABLE` at `b6090b0`,
  2026-11-03): `CREATE TABLE` (a deferrable constraint that is
  `INITIALLY IMMEDIATE` is checked after each statement), `INSERT` (only
  `NOT DEFERRABLE` constraints are `ON CONFLICT` arbiters), `CREATE POLICY`
  (`WITH CHECK` runs after `BEFORE` triggers).
- PostgREST docs `docs/references/errors.rst` (`PostgREST/postgrest` at
  `93f532c`, 2026-11-02): the SQLSTATE → HTTP table above.

## Analytics events
None in this stage. The app adds `exercise_pictures_viewed` (`count`: `1`,
`2-3`, `4+`; `source`: `gym`/`bundled`) in P-B.

## Not done here
The app side (P-B) and the dashboard's picker. The Demo & post section comes
with P-B (the first user-facing part).
