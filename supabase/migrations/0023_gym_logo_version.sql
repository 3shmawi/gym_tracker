-- Gym logo version (docs/designs/gym_logo.md §1). The dashboard replaces a
-- logo at the same path (`<gym_id>/logo.png` stays `logo.png`), so the app
-- cannot tell a new logo from the path alone. `logo_updated_at` changes on
-- every write that names `logo_path`, even with the same value: a column
-- trigger fires when the column is "mentioned as a target of the UPDATE
-- command" (PostgreSQL docs, CREATE TRIGGER, read 2026-11-14). The
-- dashboard always sets `logo_path` after an upload, so it needs no change.
--
-- Only the trigger writes the column: it is not in the update grant (0005,
-- 0021). Members read it with the rest of the row ("members read their
-- gyms"); a logo version is not personal data.

alter table public.gyms add column logo_updated_at timestamptz;

-- Logos uploaded before this migration get a version, so the app downloads
-- them once.
update public.gyms set logo_updated_at = now() where logo_path is not null;

create function private.touch_gym_logo()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.logo_updated_at := case when new.logo_path is null then null else now() end;
  return new;
end
$$;

revoke all on function private.touch_gym_logo() from public, anon, authenticated;

create trigger gyms_touch_logo
  before insert or update of logo_path on public.gyms
  for each row execute function private.touch_gym_logo();

-- The answer to a redeemed invite carries the version, so the app downloads
-- the logo right after joining, under the same version the next refresh
-- reads. Same function as 0021, one more key.
create or replace function private.redeem_payload(p_gym public.gyms, p_m public.memberships)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'ok', true,
    'gym', jsonb_build_object(
      'id', p_gym.id,
      'name', p_gym.name,
      'logo_path', p_gym.logo_path,
      'logo_updated_at', p_gym.logo_updated_at,
      'history_after_end', p_gym.history_after_end,
      'brand_color', p_gym.brand_color
    ),
    'membership_id', p_m.id,
    'role', p_m.role,
    'permissions', jsonb_build_object(
      'edit_targets', p_m.can_edit_targets,
      'edit_plan', p_m.can_edit_plan,
      'build_own_plan', p_m.can_build_own_plan
    )
  )
$$;

revoke all on function private.redeem_payload(public.gyms, public.memberships)
  from public, anon, authenticated;
grant execute on function private.redeem_payload(public.gyms, public.memberships) to service_role;
