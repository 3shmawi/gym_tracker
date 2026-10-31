# Security

Security is tested, not assumed. Three layers run on every pull request.

## 1. App tests (`flutter test`, folder `test/security/`)
| Test | Guards against |
|---|---|
| `secrets_test.dart` | private keys, Supabase secret/service-role keys, AWS/Stripe/GitHub/Google keys or hard-coded keystore passwords in `lib/`, `android/`, `ios/`, `website/`, `supabase/`, `env/`; non-empty `env/example.json`; `.gitignore` missing env/signing entries |
| `platform_config_test.dart` | cleartext HTTP, debuggable releases, extra exported Android activities, disabled iOS App Transport Security |
| `workflow_secrets_test.dart` | secrets pasted into CI scripts, a key written to a file without `scripts/mask_secrets.sh`, `set -x`, actions not pinned to a commit |
| `deep_link_test.dart` | crafted/unknown deep links crashing the app or reaching unexpected screens; open redirects via query parameters |

## 2. CI `security` job
- **gitleaks** — scans the whole git history for committed secrets.
- **OSV-Scanner** — checks `pubspec.lock` against known vulnerabilities.
- **zizmor** — audits `.github/workflows/`: actions pinned to a commit,
  read-only tokens unless a job needs more, no credentials left after
  checkout, no untrusted text run as shell code, no risky triggers.
- **Supabase RLS tests** — `supabase test db` runs `supabase/tests/*.sql`
  (pgTAP) against a local database built from the migrations. Enable once:
  `supabase init` (creates `supabase/config.toml`), commit it.

## 3. Rules for new code (also in CLAUDE.md)
- New route → add hostile paths to `deep_link_test.dart`.
- New table → RLS on + `supabase/tests/<table>_rls.test.sql`.
- New input → tests for empty, huge, injection-like and malformed values.
- Auth → signed-out redirect tests + "user A can't touch user B's rows" RLS tests.
- Only publishable keys in the app. Server secrets live in Supabase
  (Edge Function secrets / Vault).

## 4. CI and secrets
Treat every CI log and artifact as public: in a public repo they are.
GitHub hides a secret only where its **exact stored text** appears; a key
decoded from base64 or read out of a JSON secret is different text and
would be printed in full by any tool that echoes it in an error.

- Secrets reach scripts through `env:` only, never `${{ secrets.X }}` inside
  `run:`.
- A key written to a file (`.p8`, `.pem`, a service-account `.json`) is
  passed to `./scripts/mask_secrets.sh` right after it's written, before any
  tool reads it.
- Never `set -x`, `curl -v` or "print the config to debug" in CI.
- A secret's value must not be a common word: GitHub stars out that text
  everywhere in every log. That's why new Android keystores use the alias
  `<repo>-upload`, not `upload` (which turned "Keep the AAB for a manual
  upload" into "… manual ***").
- Pass passwords through environment variables the tool reads, not as
  command-line arguments.
- Workflows start with `permissions: contents: read`; a job that must write
  asks for exactly that. `actions/checkout` uses
  `persist-credentials: false`.
- Third-party actions are pinned to a full commit SHA with a `# vX.Y.Z`
  comment (Dependabot updates both). Tools installed in CI are pinned to a
  version: Codemagic CLI, fastlane, zizmor, gitleaks, OSV-Scanner (see
  `docs/release.md` → "Pinned tools").
- No `pull_request_target`. Anything a PR can control (titles, branch or
  file names, step outputs) goes through `env:` and is quoted.

## If a key leaks (log, chat, commit)
1. **Revoke or rotate it first**, then clean up. Logs can be copied in the
   minutes they are public.
2. Delete the logs: Actions → the run → ⋯ → **Delete all logs**.
3. Replace it everywhere it's used (`~/.app-secrets/shared.env` is shared by
   all your apps) and re-run `tool/setup_secrets.sh` in each app.

| Leaked | Do this |
|---|---|
| Apple Distribution certificate / .p12 | Create a new certificate first, export a new `.p12`, update secrets in every app, then revoke the old one (apps already on the store keep working) |
| App Store Connect API key (.p8) | App Store Connect → Users and Access → Integrations → revoke, create a new key |
| Play service-account JSON | Google Cloud → IAM → Service accounts → Keys → delete the key, create a new one |
| Android upload keystore | Play Console → App integrity → request an upload key reset |
| Supabase secret key / DB password / access token | Supabase dashboard → rotate it |
| Sentry auth token, GitHub token | Revoke in Sentry / GitHub settings, create a new one |

## If a scan fails
- Secret found → **rotate the key first**, then remove it from history.
- Vulnerable package → `flutter pub upgrade <package>`; if no fix exists,
  document the risk in `docs/decisions/`.
