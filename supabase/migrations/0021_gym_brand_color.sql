-- Gym brand colour (dashboard D6, docs/designs/gym_brand_colours.md).
-- One colour per gym, picked by the owner; null = Azm's colours. The app
-- generates the light and dark values and the text on top itself, with the
-- contrast guaranteed whatever the colour is, so the database checks only
-- that the value is a colour: '#rrggbb' in lower case, and not black, white
-- or a grey (channels at least 40 apart: such a value has no hue to show).
--
-- Column privileges (Supabase docs, database/postgres/column-level-security,
-- read 2026-11-11): update stays granted column by column, as since 0005;
-- which rows is still the policy "owners update their gym" (0020,
-- private.i_own). Reading follows the table's select grant and "members read
-- their gyms": a colour is not personal data.

create function private.brand_color_ok(p_color text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_color is not null
    and p_color ~ '^#[0-9a-f]{6}$'
    and (
      select greatest(r, g, b) - least(r, g, b) >= 40
      from (
        select
          ('x' || substr(p_color, 2, 2))::bit(8)::int as r,
          ('x' || substr(p_color, 4, 2))::bit(8)::int as g,
          ('x' || substr(p_color, 6, 2))::bit(8)::int as b
        where p_color ~ '^#[0-9a-f]{6}$'
      ) c
    )
$$;

revoke all on function private.brand_color_ok(text) from public, anon;
grant execute on function private.brand_color_ok(text) to authenticated, service_role;

alter table public.gyms
  add column brand_color text
  constraint gyms_brand_color_ok
    check (brand_color is null or private.brand_color_ok(brand_color));

grant update (brand_color) on table public.gyms to authenticated;

-- The answer to a redeemed invite carries the colour, so the "Joined" screen
-- is already the gym's. Same function as 0006, one more key.
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
