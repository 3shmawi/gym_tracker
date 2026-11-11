# Design: gym plan templates (dashboard D4)

> **Status: proposed, waiting for the owner's approval in the D4 pull request.**
> `CLAUDE.md` asks for an EGM-reviewed spec before code for a new table. The
> EGM plugin's `/egm:` commands were not loaded in the session that built D4,
> so this spec was written without it (as `CLAUDE.md` allows) and ships in the
> same draft PR as the code. Nothing deploys until the PR is merged; approve
> or change this spec there.

Source: decision doc [`gym_accounts.md`](../decisions/gym_accounts.md) §20
(templates, "change one exercise for one member", "apply a change to everyone
on this template") and boards "Dashboard 5, 6" of
https://claude.ai/artifact/26EDAr572B4Qr8eBLB4D75.

## Goal
A gym's owner or captain saves a plan as a **template**, starts members from
it, sees what a member's plan changed from it, resets one exercise to it, and
pushes one change to everyone whose plan came from it. Members never see
templates; they get an ordinary plan (a copy).

## Data
| Object | Shape | Rules |
|---|---|---|
| `plan_templates` (new) | `id`, `gym_id`, `name` `{ar, en}`, `body` (a plan body), `version`, `created_by`, `updated_by` (memberships), `created_at`, `updated_at` | `name`: `private.plan_name_ok` (1–40 each, no control or direction characters). `body`: `private.plan_problem(body) is null` (same shape, limits and 64 KB as `plans`). ≤ **50 per gym** (trigger, per-gym advisory lock). `version` grows when the body changes (not the name). Stamps set by the trigger; `gym_id`, `created_*` can't change. |
| `plans.template_id`, `plans.template_version` (new, nullable) | the template and its version a plan was made from | set only by `apply_plan_template`; `on delete set null` on the template (the plan stays); `save_plan` leaves them as they are |

**Why columns on `plans` and not a link table:** one plan has at most one
source; the app never reads them (it selects `body, version, updated_by`); a
deleted template must not delete plans.

## Access
| | anon | member (any role) of the gym, not a manager | manager of another gym | captain on an anonymous session | owner / captain (permanent session) |
|---|---|---|---|---|---|
| read templates | no grant | nothing | nothing of this gym | nothing | the gym's |
| add / rename / change / delete | no | no | no | no | yes (`private.i_manage`) |
| `apply_plan_template` | no execute | `forbidden` | `forbidden` | `forbidden` | owner: anyone; captain: trainees (`private.i_manage_role`, same as `save_plan`) |

Column grants: `insert (gym_id, name, body)`, `update (name, body)`,
`select`, `delete`. `plans` gets no new client grant.

## RPC `apply_plan_template(p_membership_id, p_template_id, p_base_version)`
`security definer`, `search_path = ''`, in `public` (the dashboard calls it),
`execute` for `authenticated` only.
1. caller has a person; the template and the membership exist, are in the same
   gym, and the caller `i_manage_role`s the member — else `forbidden` (42501),
   without saying which;
2. the stored plan version (0 when none) equals `p_base_version` — else
   `plan_changed` (P0001). **Stricter than `save_plan`**, which lets a manager
   overwrite without checking;
3. calls `public.save_plan(membership, base, template.body)` — so every rule
   of `save_plan` applies (body check, version bump, `updated_by`, the app's
   "Your captain updated your plan");
4. sets `template_id`, `template_version`; returns `save_plan`'s answer plus
   both.

## Dashboard
- Plan page (board 5): **Save as template** (name in both languages, the saved
  plan's body), **Replace with template** (the same warning and copy rule as
  D3's copy; goes through the RPC with the stored version), Copy (D3).
- Plan page (board 6): a banner "From the template X. N changes for Y" (N from
  the D3 diff, by id); rows whose targets differ show "Template: 3 × 12 · 90 s"
  and **Reset** (puts that exercise's targets, unit and superset back, in the
  draft; Save as usual); "The template changed since …" when its version is
  newer; "The template … was deleted" when the link points nowhere.
- **Apply a change to everyone on this template…** (saved plan only): pick one
  changed exercise; the dialog lists every member (readable, not ended) whose
  plan came from the template; one `save_plan` per member with their own
  version (a member without that exercise is skipped and said so); results per
  member; retry the failed; optionally (default on) the template body too, once.
- Templates page (`/g/<gym>/templates`): list (name in both languages,
  size, last change), rename, delete (plans made from it are kept).

## Compatibility and deploy
- Backward compatible: a new table, two nullable columns, one new function.
  `save_plan` and the app's JSON are unchanged.
- The dashboard reads the template link with its own query and treats
  "column/table does not exist" (`42703`, `PGRST204/205`, `42P01`) as "no
  template", so a dashboard deployed a few seconds before the migration still
  works (e2e: "before migration 0019").

## Tests
`supabase/tests/plan_templates_rls.test.sql` (56 checks): structure (RLS,
pinned `search_path`, grants), anon, a trainee, another gym's captain, an
anonymous-session captain, the captain and the owner; body and name rules
(hostile, too long, direction override, over 64 KB, injection-like stored as
text); stamps and versions; apply (first plan, link, stale version, re-apply,
`save_plan` afterwards keeps the link, captain → captain refused, owner →
captain allowed); delete keeps plans; the 51st template. Dashboard: vitest
(`templates.test.ts`), Playwright (`templates.spec.ts`,
`templates-a11y-security.spec.ts`).

## Open questions for the owner
1. **`save_plan` and managers.** It still lets a manager's save win without a
   version check (D3 reads the version just before saving instead). Adding the
   same check `apply_plan_template` has would close the last race, but it
   changes an RPC the app uses (the owner's own plan goes through the manager
   path). Left out; say if you want it.
2. **Copying a plan (D3) to a member whose plan came from a template** keeps
   the old template link (`save_plan` doesn't touch it), so the banner then
   shows many "changes". Options: clear the link in a later migration when a
   manager saves a whole new body, or accept it. Left as is.
3. **50 templates per gym** and **name rule = day-name rule**: fine?
