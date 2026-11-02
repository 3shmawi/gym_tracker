-- Gym accounts, part 7: deleting an account (docs/decisions/gym_accounts.md §8;
-- Apple 5.1.1(v) and Google Play need in-app account deletion).
--
-- The Edge Function `delete-account` verifies the caller's JWT, asks
-- account_deletion_blockers() whether the account may go, then deletes the auth
-- user (auth.admin.deleteUser). Everything hangs off auth.users by cascade:
--   auth.users -> people -> memberships, workout_sessions, personal_plans
-- and `invites.created_by` / `memberships.created_by` / `ended_by` are set null
-- (audit rows stay, without the person).

-- Who would be left alone: the person is the only active owner of a gym that
-- still has other (pending or active) members. Secret key only.
-- Returns {blocked: bool, gyms: [{id, name}]}.
create function public.account_deletion_blockers(p_auth_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'blocked', coalesce(bool_or(true), false),
    'gyms', coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name)), '[]'::jsonb)
  )
  from public.people p
  join public.memberships m on m.person_id = p.id and m.role = 'owner' and m.status = 'active'
  join public.gyms g on g.id = m.gym_id and g.deleted_at is null
  where p.auth_user_id = p_auth_user_id
    and not exists (
      select 1 from public.memberships o
      where o.gym_id = m.gym_id and o.id <> m.id and o.role = 'owner' and o.status = 'active'
    )
    and exists (
      select 1 from public.memberships x
      where x.gym_id = m.gym_id and x.id <> m.id and x.status in ('pending', 'active')
    )
$$;

revoke all on function public.account_deletion_blockers(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_blockers(uuid) to service_role;

-- Defense in depth: even if something deletes the auth user directly, the last
-- active owner of a gym with other members cannot be cascaded away. A hard
-- delete of the whole gym still works (its row is gone when its memberships go).
create function private.memberships_protect_last_owner()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.role = 'owner' and old.status = 'active'
     and exists (select 1 from public.gyms g where g.id = old.gym_id and g.deleted_at is null)
     and exists (
       select 1 from public.memberships x
       where x.gym_id = old.gym_id and x.id <> old.id and x.status in ('pending', 'active')
     )
     and not exists (
       select 1 from public.memberships o
       where o.gym_id = old.gym_id and o.id <> old.id and o.role = 'owner' and o.status = 'active'
     ) then
    raise exception 'last_owner' using errcode = '23514';
  end if;
  return old;
end;
$$;

create trigger memberships_protect_last_owner
  before delete on public.memberships
  for each row execute function private.memberships_protect_last_owner();
