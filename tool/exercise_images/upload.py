#!/usr/bin/env python3
"""Uploads the picture package (build.py's output) to Cloudinary.

    python3 tool/exercise_images/upload.py --package <dir> [--dry-run] [--verify]

Credentials come ONLY from the environment (the workflow passes them from
GitHub secrets through `env:`):
  CLOUDINARY_CLOUD_NAME   not secret: it is in every picture URL
  CLOUDINARY_API_KEY
  CLOUDINARY_API_SECRET   secret: signs the requests, never printed or sent

Signed upload as in Cloudinary's documentation (checked 2026-11-03,
cloudinary.com/documentation/authentication_signatures and upload_images):
POST https://api.cloudinary.com/v1_1/<cloud name>/image/upload with the
fields to sign sorted by name as `name=value` joined by `&`, the API secret
appended with no separator, hashed with SHA-1 (the default). `file`,
`cloud_name`, `resource_type` and `api_key` are never part of the signed
string. A signature is valid for one hour, so each file gets its own.

`overwrite=false` makes a second run harmless: existing pictures stay as they
are. Output is counts and public ids only. No request, header or key is ever
printed.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

API = "https://api.cloudinary.com/v1_1/{cloud}/image/upload"
CDN = "https://res.cloudinary.com/{cloud}/image/upload/{public_id}.png"
CLOUD_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{1,62}$")
PUBLIC_ID_RE = re.compile(r"^azm/exercises/[a-z0-9-]+$")
ALLOWED_LICENSES = {"CC0-1.0", "CC-BY-4.0", "CC-BY-SA-3.0", "CC-BY-SA-4.0"}
RETRIES = 3
TIMEOUT = 60


def load_package(package: Path) -> list:
    data = json.loads((package / "images.json").read_text(encoding="utf-8"))
    images = data["images"]
    seen = set()
    for row in images:
        public_id = row["public_id"]
        if not PUBLIC_ID_RE.fullmatch(public_id):
            sys.exit(f"Refusing a public id: {public_id!r}")
        if public_id in seen:
            sys.exit(f"Duplicate public id: {public_id}")
        seen.add(public_id)
        if row.get("license", data["license"]) not in ALLOWED_LICENSES:
            sys.exit(f"Refusing a licence for {public_id}")
        if not (package / "png" / (public_id.split("/")[-1] + ".png")).is_file():
            sys.exit(f"Missing file for {public_id}")
    if data["license"] not in ALLOWED_LICENSES:
        sys.exit(f"Refusing the package licence: {data['license']!r}")
    return images


def sign(params: dict, secret: str) -> str:
    to_sign = "&".join(f"{k}={params[k]}" for k in sorted(params))
    return hashlib.sha1((to_sign + secret).encode("utf-8")).hexdigest()


def multipart(fields: dict, file_name: str, file_bytes: bytes):
    boundary = uuid.uuid4().hex
    body = b""
    for name, value in fields.items():
        body += (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"'
            f"\r\n\r\n{value}\r\n"
        ).encode("utf-8")
    body += (
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
        f'filename="{file_name}"\r\nContent-Type: image/png\r\n\r\n'
    ).encode("utf-8")
    body += file_bytes + f"\r\n--{boundary}--\r\n".encode("utf-8")
    return body, f"multipart/form-data; boundary={boundary}"


def upload_one(row: dict, package: Path, cloud: str, key: str, secret: str) -> str:
    public_id = row["public_id"]
    path = package / "png" / (public_id.split("/")[-1] + ".png")
    last_error = ""
    for attempt in range(1, RETRIES + 1):
        signed = {
            "overwrite": "false",
            "public_id": public_id,
            "tags": f"azm,exercise,{row['exercise_key']}",
            "timestamp": str(int(time.time())),
        }
        fields = dict(signed, api_key=key, signature=sign(signed, secret))
        body, content_type = multipart(fields, path.name, path.read_bytes())
        request = urllib.request.Request(
            API.format(cloud=cloud),
            data=body,
            headers={"Content-Type": content_type},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                json.load(response)
                return ""
        except urllib.error.HTTPError as error:
            # Cloudinary answers with {"error": {"message": ...}}: safe to show.
            try:
                last_error = json.load(error)["error"]["message"][:160]
            except Exception:  # noqa: BLE001
                last_error = f"HTTP {error.code}"
            # Belt and braces: a credential never reaches a (public) log.
            for credential in (secret, key):
                last_error = last_error.replace(credential, "***")
            if error.code not in (429, 500, 502, 503, 504):
                break
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = type(error).__name__
        time.sleep(2 * attempt)
    return last_error


def verify_one(row: dict, cloud: str) -> str:
    url = CDN.format(cloud=cloud, public_id=row["public_id"])
    try:
        request = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return "" if response.status == 200 else f"HTTP {response.status}"
    except urllib.error.HTTPError as error:
        return f"HTTP {error.code}"
    except (urllib.error.URLError, TimeoutError) as error:
        return type(error).__name__


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verify", action="store_true", help="HEAD each public URL")
    args = parser.parse_args()

    images = load_package(args.package)
    print(f"Package OK: {len(images)} pictures")
    cloud = os.environ.get("CLOUDINARY_CLOUD_NAME", "")
    if not CLOUD_RE.fullmatch(cloud):
        sys.exit("CLOUDINARY_CLOUD_NAME is missing or not a plain cloud name")
    if args.dry_run:
        print("Dry run: nothing was sent.")
        return

    if args.verify:
        failures = []
        with ThreadPoolExecutor(max_workers=8) as pool:
            for row, error in zip(images, pool.map(lambda r: verify_one(r, cloud), images)):
                if error:
                    failures.append((row["public_id"], error))
        for public_id, error in failures[:20]:
            print(f"MISSING {public_id}: {error}")
        print(f"Verified: {len(images) - len(failures)}/{len(images)} reachable")
        sys.exit(1 if failures else 0)

    key = os.environ.get("CLOUDINARY_API_KEY", "")
    secret = os.environ.get("CLOUDINARY_API_SECRET", "")
    if not key or not secret:
        sys.exit("CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET must be set")

    failed = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = pool.map(
            lambda r: upload_one(r, args.package, cloud, key, secret), images
        )
        for row, error in zip(images, results):
            if error:
                failed.append((row["public_id"], error))
    for public_id, error in failed[:20]:
        print(f"FAILED {public_id}: {error}")
    print(f"Uploaded or already there: {len(images) - len(failed)}/{len(images)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
