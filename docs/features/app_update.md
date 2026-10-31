# Feature: app update gate

## What it does
On every launch the app compares its version with the `app_versions` row for
its platform in Supabase:
- below `min_supported_version` → **forced update**: dialog with "Update"
  only, can't be dismissed.
- below `latest_version` → **optional update**: "Update" / "Later".
The dialog shows the current and new version and the changelog in the user's
language (`changelog_en` / `changelog_ar`).

## How to ship an update notice
After the new version is live in the stores, edit the row in Supabase →
Table editor → `app_versions`: set `latest_version` (and
`min_supported_version` to force it) plus the changelog. No release needed.

## Files
- `lib/core/update/app_version.dart` — semantic version parsing/comparison
- `lib/core/update/update_info.dart` — `VersionConfig`, `evaluateUpdate()`
- `lib/core/update/update_service.dart` — Supabase query
- `lib/core/update/update_dialog.dart` — adaptive dialog
- `lib/core/update/app_update_listener.dart` — runs the check after the first frame
- `supabase/migrations/0001_app_versions.sql`

## Tests
`test/core/update/` — version parsing, update decision, dialog behaviour.

## Edge cases
- Offline / Supabase not configured / no row → no dialog.
- Web and desktop → skipped.
