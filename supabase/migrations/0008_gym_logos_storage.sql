-- Gym accounts, part 4: the private Storage bucket for gym logos
-- (docs/decisions/gym_accounts.md §3-§4). Object path: <gym_id>/logo.png|jpg|jpeg.
-- Members read their own gym's folder; managers write it. The bucket is
-- private, so a logo is only served with a signed URL or an authenticated
-- request, and nobody can list another gym's folder.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gym-logos', 'gym-logos', false, 524288, array['image/png', 'image/jpeg'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Is the caller a member (any status: an ended member still sees the logo)?
create function private.is_gym_member(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    join public.gyms g on g.id = m.gym_id
    where m.gym_id = p_gym_id
      and m.person_id = private.current_person_id()
      and g.deleted_at is null
  )
$$;

-- The gym id from the first folder of an object name, or null if it is not a uuid.
create function private.logo_gym_id(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo\.(png|jpe?g)$'
    then split_part(p_name, '/', 1)::uuid
  end
$$;

revoke all on function private.is_gym_member(uuid), private.logo_gym_id(text) from public, anon;
grant execute on function private.is_gym_member(uuid), private.logo_gym_id(text)
  to authenticated, service_role;

create policy "members read their gym logo" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'gym-logos'
    and (select private.is_gym_member(private.logo_gym_id(name)))
  );

create policy "managers upload their gym logo" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'gym-logos'
    and (select private.i_manage(private.logo_gym_id(name)))
  );

create policy "managers replace their gym logo" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'gym-logos'
    and (select private.i_manage(private.logo_gym_id(name)))
  )
  with check (
    bucket_id = 'gym-logos'
    and (select private.i_manage(private.logo_gym_id(name)))
  );

create policy "managers delete their gym logo" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'gym-logos'
    and (select private.i_manage(private.logo_gym_id(name)))
  );
