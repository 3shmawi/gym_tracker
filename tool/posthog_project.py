#!/usr/bin/env python3
"""Fill POSTHOG_API_KEY / POSTHOG_HOST in env/*.json, then check they work.

Called by tool/setup_secrets.sh before the env files are uploaded.

1. Fill (only with POSTHOG_PERSONAL_API_KEY): finds this app's PostHog
   project -- the one named POSTHOG_PROJECT (default: the repo name), or the
   only project when there is just one -- and writes its project API key
   (phc_...) and the ingestion host of POSTHOG_REGION into every
   env/<name>.json where POSTHOG_API_KEY is still empty. A key that is
   already set is never changed. Projects are not created: a second project
   needs a paid PostHog plan, so create it in PostHog when you need one.
2. Check (always): sends one feature-flag request with each env file's key
   to its host. PostHog answers 401 when the key is unknown there -- a wrong
   key, or a key from the other region (EU vs US) -- and then the app's
   events are dropped without any error in the app.

Reads from the environment: POSTHOG_PERSONAL_API_KEY (PostHog -> Settings ->
Personal API keys, scope project:read), POSTHOG_REGION (eu or us, default
eu), POSTHOG_PROJECT, DRY_RUN=true|false. Arguments: the env files.
Never prints a key.
"""
import json
import os
import sys
import urllib.error
import urllib.request

PERSONAL_KEY = os.environ.get("POSTHOG_PERSONAL_API_KEY", "")
REGION = (os.environ.get("POSTHOG_REGION") or "eu").strip().lower()
PROJECT = os.environ.get("POSTHOG_PROJECT", "")
DRY_RUN = os.environ.get("DRY_RUN", "false") == "true"


def say(msg):
    print(f"posthog       {msg}")


def request(method, url, body=None, token=None):
    """Return (status, parsed JSON or None). Never raises for HTTP errors."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        return err.code, None
    except (urllib.error.URLError, TimeoutError, ValueError):
        return 0, None


def env_files(paths):
    return [p for p in paths if os.path.basename(p) != "example.json" and os.path.isfile(p)]


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def find_project():
    """Return the project dict (has api_token), or None."""
    if REGION not in ("eu", "us"):
        say(f"POSTHOG_REGION must be eu or us (got {REGION}) -- fill skipped")
        return None
    url = f"https://{REGION}.posthog.com/api/projects/"
    projects = []
    while url:
        status, page = request("GET", url, token=PERSONAL_KEY)
        if status != 200:
            hint = ""
            if status in (401, 403):
                hint = " -- the personal API key needs scope project:read"
                hint += f", and must belong to the {REGION.upper()} region"
            if status == 0:
                hint = " -- no answer (offline?)"
            say(f"listing projects failed (HTTP {status}){hint}")
            return None
        if isinstance(page, list):
            projects += page
            url = None
        else:
            projects += (page or {}).get("results", [])
            url = (page or {}).get("next")
    named = [p for p in projects if (p.get("name") or "").strip().lower() == PROJECT.lower()]
    if named:
        return named[0]
    if len(projects) == 1:
        say(f"no project named '{PROJECT}' -- using the only one, '{projects[0].get('name')}'")
        return projects[0]
    names = ", ".join(sorted(p.get("name") or "?" for p in projects)) or "none"
    say(f"no project named '{PROJECT}' (have: {names}) -- create it in PostHog,"
        " or set POSTHOG_PROJECT in apps/<repo>/app.env")
    return None


def fill(paths):
    project = find_project()
    if not project or not project.get("api_token"):
        return
    key = project["api_token"]
    host = f"https://{REGION}.i.posthog.com"
    for path in env_files(paths):
        data = load(path)
        current = data.get("POSTHOG_API_KEY", "")
        if current:
            if current != key:
                say(f"{path} already has a different POSTHOG_API_KEY -- left as is")
            continue
        if DRY_RUN:
            say(f"would fill POSTHOG_API_KEY + POSTHOG_HOST ({host}) in {path}")
            continue
        data["POSTHOG_API_KEY"] = key
        data["POSTHOG_HOST"] = host
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        say(f"filled POSTHOG_API_KEY + POSTHOG_HOST ({host}) in {path}")


def check(paths):
    for path in env_files(paths):
        try:
            data = load(path)
        except ValueError:
            say(f"{path} is not valid JSON")
            continue
        key = data.get("POSTHOG_API_KEY", "")
        host = (data.get("POSTHOG_HOST") or "").rstrip("/")
        if not key:
            say(f"{path}: POSTHOG_API_KEY is empty -- analytics are off in that build")
            continue
        if not key.startswith("phc_"):
            say(f"{path}: POSTHOG_API_KEY is not a project API key (phc_...) -- events are dropped")
            continue
        if not host.startswith("https://"):
            say(f"{path}: POSTHOG_HOST must be https://eu.i.posthog.com or https://us.i.posthog.com")
            continue
        if host.endswith("://eu.posthog.com") or host.endswith("://us.posthog.com") or host.endswith("://app.posthog.com"):
            say(f"{path}: POSTHOG_HOST is the dashboard address -- use https://eu.i.posthog.com or https://us.i.posthog.com")
            continue
        status, _ = request(
            "POST", f"{host}/flags/?v=2", {"api_key": key, "distinct_id": "setup-check"}
        )
        if status == 200:
            say(f"{path}: key accepted by {host}")
        elif status == 401:
            other = "us" if ".eu." in host else "eu"
            say(f"{path}: {host} does not know this key -- wrong key, or the project"
                f" is in the other region (try https://{other}.i.posthog.com)")
        else:
            say(f"{path}: could not check the key (HTTP {status or 'no answer'})")


def main():
    paths = sys.argv[1:]
    if PERSONAL_KEY:
        fill(paths)
    check(paths)


if __name__ == "__main__":
    main()
