-- Gym accounts, part 6: the demo gym for App Review, nightly clean-up and the
-- scheduling helper (docs/decisions/gym_accounts.md §8, §12).
--
-- A `demo` invite is the only reusable kind: no expiry, not consumed, valid
-- only for a gym marked is_demo, and it gives a trainee membership with every
-- permission. The code goes into App Store Connect / Play Console review notes
-- (never into the repo); rotate it with admin_create_demo_invite.

alter table public.invites alter column membership_id drop not null;
alter table public.invites alter column expires_at drop not null;

alter table public.invites drop constraint invites_kind_check;
alter table public.invites add constraint invites_kind_check
  check (kind in ('join', 'recover', 'demo'));

alter table public.invites drop constraint invites_expiry_window;
alter table public.invites add constraint invites_expiry_window check (
  (kind = 'demo' and expires_at is null)
  or (kind <> 'demo' and expires_at is not null
      and expires_at > created_at and expires_at <= created_at + interval '7 days')
);

-- A demo invite belongs to a gym, not to a member, and is never "used".
alter table public.invites add constraint invites_demo_shape check (
  (kind = 'demo') = (membership_id is null) and (kind <> 'demo' or used_at is null)
);

create function private.invites_demo_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.kind = 'demo'
     and not exists (select 1 from public.gyms g where g.id = new.gym_id and g.is_demo) then
    raise exception 'a demo invite needs a demo gym' using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger invites_demo_guard
  before insert or update on public.invites
  for each row execute function private.invites_demo_guard();

-- Managers of the demo gym see its demo invite (never the hash).
drop policy "managers read invites" on public.invites;
create policy "managers read invites" on public.invites
  for select to authenticated
  using (
    (membership_id is not null and (select private.i_manage_membership(membership_id)))
    or (kind = 'demo' and (select private.i_manage(gym_id)))
  );

-- Creates (and rotates) the demo code. Secret key only. Returns
-- {invite_id, code}; the code is shown once.
create function public.admin_create_demo_invite(p_gym_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_id uuid;
  v_try int := 0;
begin
  if not exists (
    select 1 from public.gyms where id = p_gym_id and is_demo and deleted_at is null
  ) then
    raise exception 'gym_not_found' using errcode = '22023';
  end if;
  update public.invites
     set revoked_at = now()
   where gym_id = p_gym_id and kind = 'demo' and revoked_at is null;
  loop
    v_try := v_try + 1;
    v_code := private.generate_invite_code();
    begin
      insert into public.invites (gym_id, kind, code_hmac)
      values (p_gym_id, 'demo', private.hash_invite_code(v_code))
      returning id into v_id;
      exit;
    exception when unique_violation then
      if v_try >= 5 then raise; end if;
    end;
  end loop;
  return jsonb_build_object('invite_id', v_id, 'code', v_code);
end;
$$;

revoke all on function public.admin_create_demo_invite(uuid) from public, anon, authenticated;
grant execute on function public.admin_create_demo_invite(uuid) to service_role;

-- redeem_invite_core again, now with the demo kind (everything else as in 0006).
create or replace function public.redeem_invite_core(
  p_auth_user_id uuid,
  p_code text,
  p_install_id uuid,
  p_ip text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ip_hash text;
  v_inv public.invites;
  v_m public.memberships;
  v_gym public.gyms;
  v_person uuid;
  v_target uuid;
  v_reason text;
begin
  if p_auth_user_id is null or p_code is null or p_install_id is null then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  v_ip_hash := private.hash_ip(coalesce(nullif(left(p_ip, 64), ''), 'unknown'));

  -- One redeem at a time per auth user: the counters below stay exact.
  perform pg_advisory_xact_lock(hashtextextended(p_auth_user_id::text, 0));

  -- Throttle (not recorded: a locked-out person must not stay locked out).
  if (select count(*) from public.invite_attempts
       where auth_user_id = p_auth_user_id and not ok
         and at > now() - interval '1 hour') >= 10
     or (select count(*) from public.invite_attempts
          where ip_hash = v_ip_hash and not ok
            and at > now() - interval '1 hour') >= 30
     or (select count(*) from public.invite_attempts
          where not ok and at > now() - interval '10 minutes') > 200 then
    return jsonb_build_object('ok', false, 'reason', 'throttled');
  end if;

  if p_code !~ '^[A-HJKMNP-Z2-9]{6}$' then
    v_reason := 'not_found';
  else
    select * into v_inv
      from public.invites
     where code_hmac = private.hash_invite_code(p_code)
     for update;
    if not found then
      v_reason := 'not_found';
    end if;
  end if;

  if v_reason is null then
    if v_inv.kind <> 'demo' then
      select * into v_m from public.memberships where id = v_inv.membership_id for update;
    end if;
    select * into v_gym from public.gyms where id = v_inv.gym_id;
    select id into v_person from public.people where auth_user_id = p_auth_user_id;

    if v_gym.id is null or v_gym.deleted_at is not null then
      v_reason := 'not_found';
    elsif v_inv.revoked_at is not null then
      v_reason := 'revoked';
    elsif v_inv.kind = 'demo' then
      -- Reusable: no single-use, no expiry. Only valid for a demo gym.
      if not v_gym.is_demo then v_reason := 'not_found'; end if;
    elsif v_inv.used_at is not null then
      -- The same phone retrying after a lost answer is a success, nothing else is.
      if v_inv.bound_install_id = p_install_id
         and v_person is not null and v_m.person_id = v_person and v_m.status = 'active' then
        insert into public.invite_attempts (auth_user_id, ip_hash, ok)
        values (p_auth_user_id, v_ip_hash, true);
        return private.redeem_payload(v_gym, v_m);
      end if;
      v_reason := 'used';
    elsif v_inv.expires_at <= now() then
      v_reason := 'expired';
    elsif v_inv.kind = 'join' and not (v_m.status = 'pending' and v_m.person_id is null) then
      v_reason := 'not_found';
    elsif v_inv.kind = 'recover' and v_m.person_id is null then
      v_reason := 'not_found';
    end if;
  end if;

  if v_reason is null and v_inv.kind = 'demo' then
    -- App Review: every use gives (or re-activates) a trainee membership with
    -- all permissions in the demo gym. The code is not consumed.
    if v_person is null then
      insert into public.people (auth_user_id, display_name)
      values (p_auth_user_id, 'App Review')
      returning id into v_person;
    end if;
    select * into v_m from public.memberships
     where gym_id = v_inv.gym_id and person_id = v_person for update;
    if not found then
      insert into public.memberships (
        gym_id, person_id, display_name, role, status,
        can_edit_targets, can_edit_plan, can_build_own_plan, joined_at
      ) values (
        v_inv.gym_id, v_person, 'App Review', 'trainee', 'active', true, true, true, now()
      ) returning * into v_m;
    elsif v_m.status <> 'active' then
      update public.memberships
         set status = 'active', joined_at = now(), ended_at = null, ended_by = null
       where id = v_m.id
      returning * into v_m;
    end if;
    insert into public.invite_attempts (auth_user_id, ip_hash, ok)
    values (p_auth_user_id, v_ip_hash, true);
    return private.redeem_payload(v_gym, v_m);
  end if;

  if v_reason is null then
    if v_inv.kind = 'join' then
      if v_person is null then
        insert into public.people (auth_user_id, display_name)
        values (p_auth_user_id, left(v_m.display_name, 40))
        returning id into v_person;
      end if;
      if exists (select 1 from public.memberships
                  where gym_id = v_m.gym_id and person_id = v_person) then
        v_reason := 'conflict';
      else
        update public.memberships
           set person_id = v_person, status = 'active', joined_at = now()
         where id = v_m.id
        returning * into v_m;
      end if;
    else
      -- recover: the person moves to this phone's auth user.
      v_target := v_m.person_id;
      if v_person is not null and v_person <> v_target then
        v_reason := 'conflict';
      elsif v_person is null and exists (
        select 1
        from public.memberships o
        join public.gyms og on og.id = o.gym_id
        where o.person_id = v_target and o.gym_id <> v_m.gym_id
          and o.status = 'active' and og.deleted_at is null
      ) then
        v_reason := 'conflict';
      else
        if v_person is null then
          -- RLS keys on people.auth_user_id: the old session is cut off here.
          update public.people set auth_user_id = p_auth_user_id where id = v_target;
        end if;
        if v_m.status <> 'active' then
          update public.memberships
             set status = 'active', joined_at = now(), ended_at = null, ended_by = null
           where id = v_m.id
          returning * into v_m;
        end if;
      end if;
    end if;
  end if;

  if v_reason is not null then
    insert into public.invite_attempts (auth_user_id, ip_hash, ok)
    values (p_auth_user_id, v_ip_hash, false);
    return jsonb_build_object('ok', false, 'reason', v_reason);
  end if;

  update public.invites
     set used_at = now(), bound_install_id = p_install_id
   where id = v_inv.id;
  insert into public.invite_attempts (auth_user_id, ip_hash, ok)
  values (p_auth_user_id, v_ip_hash, true);
  return private.redeem_payload(v_gym, v_m);
end;
$$;


-- Nightly: demo members' history and plans are wiped, so every review starts
-- clean and no demo data piles up.
create function public.wipe_demo_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sessions bigint;
  v_plans bigint;
begin
  delete from public.workout_sessions
   where gym_id in (select id from public.gyms where is_demo);
  get diagnostics v_sessions = row_count;
  delete from public.plans
   where membership_id in (
     select m.id from public.memberships m join public.gyms g on g.id = m.gym_id where g.is_demo
   );
  get diagnostics v_plans = row_count;
  return jsonb_build_object('sessions', v_sessions, 'plans', v_plans);
end;
$$;

revoke all on function public.wipe_demo_data() from public, anon, authenticated;
grant execute on function public.wipe_demo_data() to service_role;

-- Schedules the two daily jobs when pg_cron is on (Supabase Cron guide:
-- `create extension pg_cron with schema pg_catalog;`). Run it once as the
-- project owner (SQL editor) after enabling the extension; it is safe to run
-- again (a job with the same name is replaced).
create function public.schedule_maintenance()
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled: nothing scheduled';
  end if;
  perform cron.schedule('purge-invite-attempts', '17 3 * * *', 'select public.purge_invite_attempts()');
  perform cron.schedule('wipe-demo-data', '43 2 * * *', 'select public.wipe_demo_data()');
  return 'scheduled';
end;
$$;

revoke all on function public.schedule_maintenance() from public, anon, authenticated, service_role;
