# Feature: gym brand colours (the app)

> Spec: [`../designs/gym_brand_colours.md`](../designs/gym_brand_colours.md)
> (approved 2026-11-11). Behind the **`gym_brand_colours`** flag (PostHog,
> off by default): off, the app is Azm's colours everywhere, as before.
> The dashboard side (the owner picks the colour) is in
> [`dashboard.md`](dashboard.md) → D6.

## What it does
- A gym's owner picks one colour. While that gym is the member's active
  workspace, the app's brand colour is the gym's: buttons, progress bars and
  rings, the workout pill, selected marks, coloured text and icons, and the
  tint of the background.
- Training solo, an ended membership, a gym without a colour, a value the
  app does not accept, or the flag off: Azm's green.
- The member's light / dark / system setting is unchanged; the gym only
  changes the colour inside it.
- Switching workspace, or the owner changing the colour, fades to the new
  colour in 200 ms (at once with Reduce Motion) the next time the
  memberships refresh (app start, resume, back online). Nothing but colour
  changes, so it also applies during a workout.

**Never changes per gym:** trend colours (up, keep, down, new), error red
and danger buttons, the Azm logo, splash, loading animation and level
figures, the rest notification's accent, the app icon, backgrounds, card
surfaces and text greys, the update dialog and the consent sheet
(`AzmTheme`).

## How the colour is made
`lib/core/theme/brand_color_rule.dart` (pure Dart, integers). From the
picked colour, per mode:

| Value | Used for | Guarantee |
|---|---|---|
| `palette.brand` | fills | ≥ 3:1 against the mode's reference surface |
| `palette.onBrand` | text and icons on a fill (white or black) | ≥ 4.5:1 |
| `colorScheme.primary` | coloured text, icons, borders | ≥ 4.5:1 |
| `colorScheme.onPrimary` | text on the accent as a fill | ≥ 4.5:1 |
| `palette.glowStart` / `glowEnd` | the background's tinted corners | never stronger than Azm's |

A light colour is shown darker in light mode (yellow becomes dark gold) and
a dark colour lighter in dark mode. Material's other generated roles (card
surfaces in lite mode, outlines) stay seeded from Azm's green for every gym.
The same rule runs in the dashboard's preview; both are checked against
`brand_colour_vectors.json`.

## How the app gets it
- `brand_color` rides the membership query the app already makes
  (`gyms(id, name, history_after_end, brand_color)`) and its cache in
  `SharedPreferences` (`gym.memberships`): **no new request, no new key**,
  and it works offline. The answer to a redeemed invite carries it too, so
  the "Joined" screen is already the gym's colour.
- `Gym.brandColor` is the `#rrggbb` string or null. `Gym.readBrandColor`
  accepts only the exact format with enough colour (not black, white or
  grey); anything else, of any type, is null. It never throws.
- **The colour is not part of `Gym ==`.** A new colour must not rebuild what
  depends on the membership (the workout repository, the plan, the
  pictures); it is read only through `activeBrandColorProvider`.
- `gymBrandColoursEnabledProvider`: the flag. It starts from the last answer
  kept on the phone (`FlagCache`, key `flags.gym_brand_colours`), so the app
  opens in the right colours, then asks PostHog once and remembers.
- `BrandThemeHost` (in `AppShell.builder`, inside `ConsentGate`) puts
  `AppTheme.of(brightness, gymColor:)` on the navigator with `AnimatedTheme`.

## Performance
- Themes are built once per brightness, colour and screen scale and reused
  (`AppTheme`), so a rebuild of the shell does not rebuild every screen.
- With no gym colour the host hands down the app's own theme object: no
  extra work for solo members.
- A colour change rebuilds the theme once; no provider that loads data
  listens to it.

## Analytics (no personal data)
| Event | Properties |
|---|---|
| `gym_theme_applied` | `mode`: `light` \| `dark`; `adjusted`: whether the fill differs from the picked colour |

Never the colour, the gym or an id (`gym_account_app_test.dart` checks the
event names and property keys). The spec also listed `gym_theme_fallback`;
it is not built: the domain layer cannot report, and a refused value is
already impossible to store (migration 0021).

## Tests
- `test/core/theme/`: the rule against the shared vectors, its guarantees on
  a sweep of the colour cube, theme values, the theme cache, the usage test.
- `test/features/gym/presentation/gym_brand_test.dart`: reading the colour
  (valid, 15 hostile values, the cache round trip, equality); the provider
  (active gym, solo, no colour, ended, unknown workspace, flag off, the
  kept flag answer, switching workspace); **a new colour during a workout
  does not rebuild the workout repository**; the host (gym colour inside,
  `AzmTheme` stays Azm, no colour = the same theme object, the fade and
  Reduce Motion); `screensUiTests` for home and the workout in a light-ish
  (yellow) and a dark-ish (navy) colour: 32 variants each with the layout,
  contrast and golden checks.
- `integration_test/app_test.dart`: "a gym with its own colour: join, and
  the app is the gym's".

## Demo & post
Hook: "Your gym, your colours."
Scenario (integration test): a new install is Azm green → scan Iron House's
QR → "Welcome to Iron House" → *Start training* → every button, bar and
ring is the gym's yellow.
Captions: EN "Join your gym and the app wears its colours. Still readable in
light and dark, every time." · AR "ادخل جيمك والتطبيق يلبس ألوانه. والكلام
يفضل واضح في الفاتح والغامق."
Hashtags: #Azm #GymApp #Flutter #BuildInPublic
