-- Gym plan templates (dashboard D4; decision doc gym_accounts.md §20,
-- design docs/designs/plan_templates.md).
--
-- A template is a plan body a gym's owner or captain saves to start members
-- from. Applying one to a member goes through the same rules as save_plan and
-- records which template (and which version of it) the plan came from, so the
-- dashboard can show what a member's plan changed and offer Reset.
--
-- Backward compatible: a new table, two new nullable columns on plans, one new
-- RPC. save_plan and the app's plan JSON are unchanged; the app reads plans
-- with explicit columns (body, version, updated_by), so it never sees the new
-- ones. Docs read 2026-11-10: PostgreSQL 17 "CREATE TABLE" (a CHECK may call
-- an immutable function of the row; ON DELETE SET NULL), Supabase "Row Level
-- Security" (wrap helpers in (select …), security definer runs as the owner).

-- Table ----------------------------------------------------------------------

create table public.plan_templates (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms (id) on delete cascade,
  -- {"ar": …, "en": …}, 1–40 characters each, same rule as a plan's day name.
  name jsonb not null
    constraint plan_templates_name_ok check (private.plan_name_ok(name)),
  -- Exactly a plan body (private.plan_problem: shape, limits, ≤ 64 KB).
  body jsonb not null
    constraint plan_templates_body_ok check (private.plan_problem(body) is null),
  -- Grows by one each time the body changes (not the name).
  version int not null default 1 check (version >= 1),
  created_by uuid references public.memberships (id) on delete set null,
  updated_by uuid references public.memberships (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index plan_templates_gym_idx on public.plan_templates (gym_id);
create index plan_templates_created_by_idx on public.plan_templates (created_by) where created_by is not null;
create index plan_templates_updated_by_idx on public.plan_templates (updated_by) where updated_by is not null;

comment on table public.plan_templates is
  'A gym''s plan templates (body checked like plans). Read and write: the gym''s owner and captains (permanent session). Members never see them.';

-- Stamps, versions and the per-gym limit -------------------------------------
-- security definer only to count the gym's rows in one index scan under a
-- per-gym lock (as 0015/0017); the policies still decide who may write.

create function private.plan_templates_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  select m.id into v_actor
    from public.memberships m
   where m.gym_id = new.gym_id
     and m.person_id = private.current_person_id()
     and m.status = 'active';

  if tg_op = 'INSERT' then
    perform pg_advisory_xact_lock(hashtextextended('plan_templates:' || new.gym_id::text, 0));
    if (select count(*) from public.plan_templates t where t.gym_id = new.gym_id) >= 50 then
      raise exception 'too_many_templates_in_gym' using errcode = '23514';
    end if;
    new.version := 1;
    new.created_by := v_actor;
    new.created_at := now();
  else
    new.gym_id := old.gym_id;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.version := case when new.body is distinct from old.body then old.version + 1 else old.version end;
  end if;
  new.updated_by := v_actor;
  new.updated_at := now();
  return new;
end;
$$;

create trigger plan_templates_guard
  before insert or update on public.plan_templates
  for each row execute function private.plan_templates_guard();

revoke all on function private.plan_templates_guard() from public, anon, authenticated;

-- Who can do what --------------------------------------------------------------

alter table public.plan_templates enable row level security;
revoke all on table public.plan_templates from anon, authenticated;
grant select, delete on table public.plan_templates to authenticated;
grant insert (gym_id, name, body) on table public.plan_templates to authenticated;
grant update (name, body) on table public.plan_templates to authenticated;

create policy "managers read their gym's templates" on public.plan_templates
  for select to authenticated
  using ((select private.i_manage(gym_id)));

create policy "managers add templates" on public.plan_templates
  for insert to authenticated
  with check ((select private.i_manage(gym_id)));

create policy "managers change templates" on public.plan_templates
  for update to authenticated
  using ((select private.i_manage(gym_id)))
  with check ((select private.i_manage(gym_id)));

create policy "managers remove templates" on public.plan_templates
  for delete to authenticated
  using ((select private.i_manage(gym_id)));

-- Which template a plan came from ----------------------------------------------
-- Set only by apply_plan_template (plans has no write grant for clients).
-- A deleted template clears template_id; template_version is then ignored.

alter table public.plans
  add column template_id uuid references public.plan_templates (id) on delete set null,
  add column template_version int check (template_version is null or template_version >= 1);

create index plans_template_idx on public.plans (template_id) where template_id is not null;

-- Apply a template to a member ---------------------------------------------------
-- The same rules as save_plan for a manager (it calls save_plan), plus: the
-- template belongs to the member's gym, and `p_base_version` must equal the
-- stored version (0 when the member has no plan) — unlike save_plan, which
-- lets a manager's save win without checking. Returns save_plan's answer plus
-- the template's id and version.

create function public.apply_plan_template(p_membership_id uuid, p_template_id uuid, p_base_version int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_t public.plan_templates;
  v_m public.memberships;
  v_current int;
  v_saved jsonb;
begin
  if private.current_person_id() is null then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select * into v_t from public.plan_templates where id = p_template_id for share;
  select * into v_m from public.memberships where id = p_membership_id for update;
  if v_t.id is null or v_m.id is null or v_m.gym_id <> v_t.gym_id
     or not private.i_manage_role(v_m.gym_id, v_m.role) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select p.version into v_current from public.plans p where p.membership_id = v_m.id for update;
  if coalesce(v_current, 0) is distinct from p_base_version then
    raise exception 'plan_changed' using errcode = 'P0001';
  end if;

  v_saved := public.save_plan(v_m.id, p_base_version, v_t.body);

  update public.plans
     set template_id = v_t.id, template_version = v_t.version
   where membership_id = v_m.id;

  return v_saved || jsonb_build_object('template_id', v_t.id, 'template_version', v_t.version);
end;
$$;

revoke all on function public.apply_plan_template(uuid, uuid, int) from public, anon;
grant execute on function public.apply_plan_template(uuid, uuid, int) to authenticated;
