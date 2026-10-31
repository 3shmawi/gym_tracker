#!/usr/bin/env python3
"""Make sure this app has a Sentry project, and put its DSN in env/*.json.

Called by tool/setup_secrets.sh (apps using Sentry). Creates the project when
it doesn't exist yet, then fills SENTRY_DSN in every env/<name>.json where it
is still empty. A DSN that is already set is never changed.

Reads from the environment: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT,
optional SENTRY_TEAM (default: the org's first team), SENTRY_URL (default
https://sentry.io) and DRY_RUN=true|false. Arguments: the env files.

The token is a Sentry *user* auth token (User settings -> Auth Tokens) with
scopes org:read, team:read, project:read, project:write and project:releases.
Organization tokens (sntrys_...) can upload symbols but can't create projects.
"""
import json
import os
import sys
import urllib.error
import urllib.request

TOKEN = os.environ.get("SENTRY_AUTH_TOKEN", "")
ORG = os.environ.get("SENTRY_ORG", "")
PROJECT = os.environ.get("SENTRY_PROJECT", "")
TEAM = os.environ.get("SENTRY_TEAM", "")
BASE = os.environ.get("SENTRY_URL", "https://sentry.io").rstrip("/")
DRY_RUN = os.environ.get("DRY_RUN", "false") == "true"


def say(msg):
    print(f"sentry        {msg}")


def api(method, path, body=None):
    """Return (status, parsed JSON or None). Never raises for HTTP errors."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{BASE}/api/0{path}",
        data=data,
        method=method,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        try:
            return err.code, json.loads(err.read() or b"null")
        except ValueError:
            return err.code, None


def fail(status, what):
    hint = ""
    if status in (401, 403):
        hint = " -- the token needs org:read, team:read, project:read and project:write (a user auth token, not an org token)"
    elif status == 404:
        hint = f" -- check SENTRY_ORG ({ORG}) and SENTRY_URL ({BASE})"
    say(f"{what} failed (HTTP {status}){hint}")
    sys.exit(1)


def ensure_project():
    status, _ = api("GET", f"/projects/{ORG}/{PROJECT}/")
    if status == 200:
        say(f"project {ORG}/{PROJECT} exists")
        return True
    if status != 404:
        fail(status, "looking up the project")

    team = TEAM
    if not team:
        status, teams = api("GET", f"/organizations/{ORG}/teams/")
        if status != 200:
            fail(status, "listing teams")
        if not teams:
            say(f"no team in {ORG} -- create one in Sentry, or set SENTRY_TEAM")
            sys.exit(1)
        team = teams[0]["slug"]

    if DRY_RUN:
        say(f"would create project {ORG}/{PROJECT} (Flutter, team {team})")
        return False
    status, _ = api(
        "POST",
        f"/teams/{ORG}/{team}/projects/",
        {"name": PROJECT, "slug": PROJECT, "platform": "flutter"},
    )
    if status not in (200, 201):
        fail(status, f"creating project {PROJECT}")
    say(f"created project {ORG}/{PROJECT} (Flutter, team {team})")
    return True


def project_dsn():
    status, keys = api("GET", f"/projects/{ORG}/{PROJECT}/keys/")
    if status != 200:
        fail(status, "reading the project's client keys")
    for key in keys or []:
        if key.get("isActive", True) and key.get("dsn", {}).get("public"):
            return key["dsn"]["public"]
    status, key = api("POST", f"/projects/{ORG}/{PROJECT}/keys/", {"name": "Default"})
    if status not in (200, 201):
        fail(status, "creating a client key")
    return key["dsn"]["public"]


def fill_env_files(dsn, paths):
    filled = 0
    for path in paths:
        if os.path.basename(path) == "example.json" or not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        current = data.get("SENTRY_DSN", "")
        if current:
            if current != dsn:
                say(f"{path} already has a different SENTRY_DSN -- left as is")
            continue
        if DRY_RUN:
            say(f"would fill SENTRY_DSN in {path}")
            continue
        data["SENTRY_DSN"] = dsn
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        say(f"filled SENTRY_DSN in {path}")
        filled += 1
    if filled == 0 and not any(
        os.path.isfile(p) and os.path.basename(p) != "example.json" for p in paths
    ):
        say("no env/<name>.json yet -- copy env/example.json, then run this again")


def main():
    if not (TOKEN and ORG and PROJECT):
        say("skipped (needs SENTRY_AUTH_TOKEN, SENTRY_ORG and a project name)")
        return
    exists = ensure_project()
    if not exists:  # dry run of a project that doesn't exist yet
        return
    fill_env_files(project_dsn(), sys.argv[1:])


if __name__ == "__main__":
    main()
