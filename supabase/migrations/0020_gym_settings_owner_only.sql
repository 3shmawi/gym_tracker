-- Gym settings are the owner's (product decision, dashboard D5).
-- Until now "managers" (owner or captain, private.i_manage) could change the
-- gym's name, logo and history setting (0005) and write the gym-logos folder
-- (0008). Now only an active owner on a permanent session can. Captains keep
-- reading both, as before; nothing else that uses private.i_manage changes.
--
-- Supabase Storage (docs read 2026-11-11, storage/security/access-control):
-- an upload needs INSERT; an upsert also needs SELECT and UPDATE; a delete
-- needs DELETE. SELECT stays "members read their gym logo" (0008).

-- Active owner of the gym, signed in with a permanent session.
create function private.i_own(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_permanent()
    and coalesce(private.my_role_in(p_gym_id) = 'owner', false)
$$;

revoke all on function private.i_own(uuid) from public, anon;
grant execute on function private.i_own(uuid) to authenticated, service_role;

-- gyms: the column grant (name, logo_path, history_after_end) is unchanged;
-- only who may use it narrows.
drop policy "managers update their gym" on public.gyms;
create policy "owners update their gym" on public.gyms
  for update to authenticated
  using ((select private.i_own(id)))
  with check ((select private.i_own(id)));

-- gym-logos: write, replace and delete only by the gym's owner.
drop policy "managers upload their gym logo" on storage.objects;
drop policy "managers replace their gym logo" on storage.objects;
drop policy "managers delete their gym logo" on storage.objects;

create policy "owners upload their gym logo" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'gym-logos'
    and (select private.i_own(private.logo_gym_id(name)))
  );

create policy "owners replace their gym logo" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'gym-logos'
    and (select private.i_own(private.logo_gym_id(name)))
  )
  with check (
    bucket_id = 'gym-logos'
    and (select private.i_own(private.logo_gym_id(name)))
  );

create policy "owners delete their gym logo" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'gym-logos'
    and (select private.i_own(private.logo_gym_id(name)))
  );
