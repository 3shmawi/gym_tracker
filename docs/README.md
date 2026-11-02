# Azm — documentation

Start with [`../CLAUDE.md`](../CLAUDE.md) (rules + stack), then:

- [Design](design.md) — Claude Design links, tokens → code, screen checklist
- [Getting started](getting_started.md) — run the app, env files, Supabase
- [Release & CI/CD](release.md) — how merging to `main` ships to the stores
- [Deep links](deep_links.md)
- [Security](security.md) — what is tested and how
- [Decisions](decisions/) — why the stack looks the way it does; [gym accounts](decisions/gym_accounts.md) (accepted; backend and app built, captain tools and dashboard not yet)

## Features
- [App update gate](features/app_update.md)
- [Settings (language & theme)](features/settings.md)
- [Workout (plan, plan editor, next workout, weight suggestions, levels)](features/workout.md)
- [Splash and loading animation](features/splash_and_loading.md)
- [Join a gym by link or code](features/gym_join.md) (web page `/join/<code>` + the app's enter-code screen)
- [Gym accounts — backend](features/gym_accounts_backend.md) (tables, RLS, `redeem_invite`, QR cards)
- [Gym accounts — the app](features/gym_account_app.md) (first screen, scanner, join, switcher, profile, delete account)
