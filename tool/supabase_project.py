#!/usr/bin/env python3
"""Create this app's Supabase project when env/prod.json has no SUPABASE_URL.

Called by tool/setup_secrets.sh. When SUPABASE_URL in env/prod.json is empty
it:
  1. reuses a project named like the repo in SUPABASE_ORG, or creates one
     (strong random database password, region SUPABASE_REGION),
  2. saves SUPABASE_DB_PASSWORD to app.env right away (so it is never lost),
  3. waits until the project is ACTIVE_HEALTHY,
  4. fills SUPABASE_URL + SUPABASE_PUBLISHABLE_KEY in env/prod.json and adds
     SUPABASE_SECRET_KEY to app.env.
Nothing is changed when SUPABASE_URL is already set.

Environment: SUPABASE_ADMIN_TOKEN (Access Tokens: create projects + read API
keys and their secrets), SUPABASE_ORG (organization slug), SUPABASE_PROJECT
(project name, default: the repo name), SUPABASE_REGION (default
eu-central-1), APP_ENV (path of apps/<repo>/app.env), DRY_RUN=true|false,
SUPABASE_API (default https://api.supabase.com). Argument: env/prod.json.
"""
import json
import os
import secrets
import string
import sys
import time
import urllib.error
import urllib.request

TOKEN = os.environ.get("SUPABASE_ADMIN_TOKEN", "")
ORG = os.environ.get("SUPABASE_ORG", "")
NAME = os.environ.get("SUPABASE_PROJECT", "")
REGION = os.environ.get("SUPABASE_REGION", "") or "eu-central-1"
APP_ENV = os.environ.get("APP_ENV", "")
API = os.environ.get("SUPABASE_API", "https://api.supabase.com").rstrip("/")
DRY_RUN = os.environ.get("DRY_RUN", "false") == "true"
WAIT_SECONDS = int(os.environ.get("SUPABASE_WAIT_SECONDS", "600"))
POLL_SECONDS = float(os.environ.get("SUPABASE_POLL_SECONDS", "10"))


def say(msg):
    print(f"supabase      {msg}")


def api(method, path, body=None):
    """Return (status, parsed JSON or None). Never raises for HTTP errors."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{API}/v1{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "User-Agent": "flutter-project-kit",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        try:
            return err.code, json.loads(err.read() or b"null")
        except ValueError:
            return err.code, None


def fail(status, what, body=None):
    detail = ""
    if isinstance(body, dict):
        detail = body.get("message") or body.get("error") or ""
    hint = ""
    if status in (401, 403):
        hint = " -- check SUPABASE_ADMIN_TOKEN's permissions (create projects, API keys + API key secrets: read)"
    elif status == 402:
        hint = " -- the organization has no free project slot left (free plan: 2 active projects)"
    say(f"{what} failed (HTTP {status}){': ' + detail if detail else ''}{hint}")
    sys.exit(1)


def read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def app_env_has(key):
    if not APP_ENV or not os.path.isfile(APP_ENV):
        return False
    with open(APP_ENV, encoding="utf-8") as f:
        return any(line.startswith(f"{key}=") and line.strip() != f"{key}=" for line in f)


def app_env_set(key, value):
    """Add or replace KEY=value in app.env, keeping every other line."""
    lines = []
    if os.path.isfile(APP_ENV):
        with open(APP_ENV, encoding="utf-8") as f:
            lines = [l for l in f.read().splitlines() if not l.startswith(f"{key}=")]
    lines.append(f"{key}={value}")
    old_umask = os.umask(0o077)
    try:
        with open(APP_ENV, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    finally:
        os.umask(old_umask)


def strong_password(length=32):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def find_project():
    status, projects = api("GET", "/projects")
    if status != 200:
        fail(status, "listing projects", projects)
    for p in projects or []:
        if p.get("name") != NAME:
            continue
        orgs = {p.get("organization_id"), p.get("organization_slug")} - {None}
        if not orgs or ORG in orgs:
            return p
    return None


def create_project():
    password = strong_password()
    status, body = api(
        "POST",
        "/projects",
        {"name": NAME, "organization_id": ORG, "db_pass": password, "region": REGION},
    )
    if status not in (200, 201):
        fail(status, f"creating project {NAME}", body)
    ref = body["id"]
    # Saved before anything else can fail: the password is shown only now.
    app_env_set("SUPABASE_DB_PASSWORD", password)
    say(f"created project {NAME} ({ref}, {REGION}); DB password saved to app.env")
    return ref


def wait_until_healthy(ref):
    deadline = time.time() + WAIT_SECONDS
    last = ""
    while True:
        status, body = api("GET", f"/projects/{ref}")
        if status != 200:
            fail(status, "checking the project's status", body)
        state = (body or {}).get("status", "")
        if state == "ACTIVE_HEALTHY":
            return
        if state != last:
            say(f"waiting for the project ({state or 'starting'})…")
            last = state
        if time.time() > deadline:
            say(f"still {state} after {WAIT_SECONDS}s -- run tool/setup_secrets.sh again in a few minutes")
            sys.exit(1)
        time.sleep(POLL_SECONDS)


def api_keys(ref):
    status, keys = api("GET", f"/projects/{ref}/api-keys?reveal=true")
    if status != 200:
        fail(status, "reading API keys", keys)
    keys = keys or []
    have = {k.get("type") for k in keys}
    for kind in ("publishable", "secret"):
        if kind not in have:
            status, body = api("POST", f"/projects/{ref}/api-keys?reveal=true",
                               {"type": kind, "name": "default"})
            if status not in (200, 201):
                fail(status, f"creating the {kind} key", body)
            keys.append(body)
    pick = lambda kind: next((k.get("api_key") for k in keys if k.get("type") == kind), "")
    return pick("publishable"), pick("secret")


def main():
    if not (TOKEN and NAME and APP_ENV):
        say("skipped (needs SUPABASE_ADMIN_TOKEN)")
        return
    path = sys.argv[1] if len(sys.argv) > 1 else "env/prod.json"
    if not os.path.isfile(path):
        say(f"no {path} yet -- copy env/example.json to it, then run this again")
        return
    env = read_json(path)
    if env.get("SUPABASE_URL"):
        return  # already connected to a project: nothing to do

    if not ORG:
        say("skipped (set SUPABASE_ORG to your organization slug)")
        return

    existing = find_project()
    if DRY_RUN:
        if existing:
            say(f"would connect existing project {NAME} ({existing.get('id')}) to {path}")
        else:
            say(f"would create project {NAME} in {ORG} ({REGION}) and fill {path} + app.env")
        return

    if existing:
        ref = existing["id"]
        say(f"project {NAME} already exists ({ref}) -- connecting it")
        if not app_env_has("SUPABASE_DB_PASSWORD"):
            say("its DB password isn't in app.env: reset it (Database → Settings) and add SUPABASE_DB_PASSWORD=…")
    else:
        ref = create_project()

    wait_until_healthy(ref)
    publishable, secret = api_keys(ref)
    if not publishable:
        say("no publishable key returned -- copy it from Project Settings → API Keys")
        sys.exit(1)

    env["SUPABASE_URL"] = f"https://{ref}.supabase.co"
    env["SUPABASE_PUBLISHABLE_KEY"] = publishable
    write_json(path, env)
    say(f"filled SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in {path}")
    if secret and not any(c in secret for c in "*•…"):
        app_env_set("SUPABASE_SECRET_KEY", secret)
        say("saved SUPABASE_SECRET_KEY to app.env")
    else:
        say("secret key not revealed -- give the token 'API Key Secrets: read', or add SUPABASE_SECRET_KEY by hand")


if __name__ == "__main__":
    main()
