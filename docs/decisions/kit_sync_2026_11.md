# Decision: kit sync to flutter-project-kit ae5f910 (Nov 2026)

Status: **accepted** (2026-11-24, owner chose "full sync, features off").
Replaces the automatic kit-sync PR (chore/kit-sync-a50ee3f) and closes the
"kit sync needs manual merge" issue.

## What came in
- Tools: `scripts/agent_run.sh` + `test_driver/agent_app.dart` (drive the app
  on a simulator with the Dart MCP server, debug only; guarded by
  `test/security/agent_driver_test.dart`), `scripts/add_module.sh`.
- Announce update: `scripts/store_live.sh`, `announce_plan.sh`,
  `whats_new.sh` (daily check that the version is live on both stores),
  tested by `test/scripts/announce_scripts_test.dart`.
- Social: `social-health.yml` (weekly token check / Threads refresh),
  `social-insights.yml` (post numbers after a week), opt-in Threads,
  Bluesky, Telegram and X keys in `tool/setup_secrets.sh`.
- `ios/Runner/PrivacyInfo.xcprivacy`, kit fixes to CI, release, store and
  website files that did not clash with Azm.

## What was left out (on purpose)
Every change the kit made to app code under `lib/`, `test/` and
`integration_test/` kept Azm's version. The kit's new app features did not
fit Azm's current code (101 analyzer errors against Azm's update dialog,
`showAppSheet`, consent and settings) and some change what users see or
what the privacy policy must say:
- Analytics consent sheet (`lib/core/privacy/`) — would change the privacy
  policy ("only if you allow it"); not wired, policy unchanged.
- Store review prompt (`lib/core/review/`).
- `showAppMessage` / `app_message.dart`, `LegalLinks`, `app_redirect.dart`,
  `backend_errors.dart`, the new full-screen forced update.
- Golden test file `test/golden/`, store screenshot renderer
  (`test/store/`) and the App Store header images (`store/tools/hero.js`) —
  Azm already has its own screenshot steps (store/README.md).
- Firebase backend parts (Azm is Supabase only), `docs/backend.md`.

`.project-kit.env` `KIT_COMMIT` now points at ae5f910, so the next
`scripts/kit_sync.sh` only offers changes made in the kit after it; these
skipped parts will not come back by themselves. To adopt one later, copy it
from the kit by hand in its own PR, behind a feature flag where it changes
what users see, and update the privacy policy first if it collects data.
