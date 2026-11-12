# Azm — documentation

Start with [`../CLAUDE.md`](../CLAUDE.md) (rules + stack), then:

- [Design](design.md) — Claude Design links, tokens → code, screen checklist
- [Getting started](getting_started.md) — run the app, env files, Supabase
- [Release & CI/CD](release.md) — how merging to `main` ships to the stores
- [Deep links](deep_links.md)
- [Security](security.md) — what is tested and how
- [Performance](performance.md) — scroll performance test, glass vs lite, numbers before/after
- [Decisions](decisions/) — why the stack looks the way it does; [gym accounts](decisions/gym_accounts.md) (accepted; backend and app built, captain tools and dashboard not yet); [videos outside the app](decisions/video_outside_app.md) (accepted: no PiP or background play, pause on leaving)
- [Designs](designs/) — approved specs for big features, reviewed with EGM
  ([getting started](getting_started.md) → "Design reviews")

## Features
- [App update gate](features/app_update.md)
- [Settings (language & theme)](features/settings.md)
- [Workout (plan, plan editor, next workout, weight suggestions, levels)](features/workout.md)
- [Splash and loading animation](features/splash_and_loading.md)
- [Join a gym by link or code](features/gym_join.md) (web page `/join/<code>` + the app's enter-code screen)
- [Gym accounts — backend](features/gym_accounts_backend.md) (tables, RLS, `redeem_invite`, QR cards)
- [Exercise library](features/exercise_library.md) (shared exercises, picker in the plan editor, exercise screen)
- [Exercise pictures](features/exercise_images.md) (drawings for the library, sources and licences, how to add one)
- [Exercise picture library](features/exercise_image_library.md) (all Everkinetic pictures on Cloudinary, searchable keywords in the database, upload workflow)
- [Gym-chosen exercise pictures](features/gym_exercise_images.md) (table, RLS, limits, the dashboard contract; app side next)
- [How-to videos](features/exercise_videos.md) (YouTube: link parser and shared vectors, library videos, the card and the player, privacy)
- [Captain web dashboard](features/dashboard.md) (`dashboard/`, own origin `azmm-dash.pages.dev`; D0: email-code sign-in, my gyms; D1: members, invite codes, QR cards, names from Excel; deploy, owner bootstrap)
- [Trainee dashboard data](features/trainee_dashboard_data.md) (SQL views the captain's dashboard will read; privacy)
- [Gym accounts — the app](features/gym_account_app.md) (first screen, scanner, join, switcher, profile, delete account, solo data import)
