#!/usr/bin/env python3
"""Create gym invites and print them as a PDF of QR cards.

Run LOCALLY, by the gym's owner (you), on your own computer:

    scripts/make_invites/run.sh --gym <gym-uuid> --count 20 [--names names.txt]
                                [--logo logo.png] [--out cards.pdf]
                                [--edit-targets] [--edit-plan] [--build-own-plan]
    scripts/make_invites/run.sh --dry-run --count 6 --gym-name "Sample Gym"

What it does (docs/decisions/gym_accounts.md §5):
  1. asks Supabase to create N pending trainee memberships and N single-use
     invites that expire in 7 days (SQL function admin_create_invites; only the
     secret key may call it; only a keyed hash of each code is stored);
  2. draws one card per invite: a QR (error correction H) that opens
     https://azmm.pages.dev/join/<code>, the gym logo in the centre (its box is
     at most 20 % of the QR's side), and the same 6-character code in text for
     manual entry.

Secrets (docs/security.md → "CI and secrets", scripts/mask_secrets.sh rules):
  * SUPABASE_URL and SUPABASE_SECRET_KEY come from the ENVIRONMENT only. There
    is no flag for them, so they never reach a shell history or a process list.
  * It refuses to run in CI (GITHUB_ACTIONS / CI): the secret key must never be
    in a workflow, and the cards hold live codes. The PDF is never written
    inside this repository.
  * It never prints a code or the key. Error text is cut to a safe, short
    form and the key is redacted from it. No tracing, no verbose mode.
  * The codes exist only in the PDF (and on the cards): the server cannot
    show them again. Lost a card? Revoke it and issue a new one.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import io
import json
import os
import re
import sys
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable, Optional

JOIN_URL_BASE = "https://azmm.pages.dev/join/"
# Keep in sync with the SQL generator, the Edge Function and website/assets/join.js.
CODE_RE = re.compile(r"^[A-HJKMNP-Z2-9]{6}$")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
SUPABASE_URL_RE = re.compile(
    r"^(https://[a-z0-9]{20}\.supabase\.co|http://(127\.0\.0\.1|localhost):\d{2,5})$"
)
MAX_COUNT = 200
MAX_NAME_CHARS = 40
MAX_LOGO_BYTES = 512 * 1024
MAX_LOGO_PIXELS = 16_000_000
# The logo box may cover at most this fraction of the QR symbol's SIDE
# (the quiet zone does not count). ≈ 4 % of the area; level H recovers 30 %.
LOGO_SIDE_MAX = 0.20
LOGO_SIDE_DEFAULT = 0.18
HTTP_TIMEOUT_SECONDS = 30
REPO_ROOT = Path(__file__).resolve().parents[2]
FONT_DIR = REPO_ROOT / "assets" / "fonts"

_INVISIBLE = re.compile(r"[\x00-\x1F\x7F-\x9F‎‏‪-‮⁦-⁩]")
_ARABIC = re.compile(r"[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]")


class UsageError(Exception):
    """A problem the user can fix; the message is safe to print."""


class ApiError(Exception):
    """The server said no. Carries only a short, redacted description."""


# --------------------------------------------------------------------------
# Inputs
# --------------------------------------------------------------------------
def join_url(code: str) -> str:
    if not isinstance(code, str) or not CODE_RE.fullmatch(code):
        raise ValueError("not a valid invite code")
    return JOIN_URL_BASE + code


def clean_name(raw: str) -> str:
    """One line, trimmed, no control or bidi-override characters (same rules
    as plan names), 1-40 characters."""
    name = " ".join(_INVISIBLE.sub(" ", unicodedata.normalize("NFC", raw)).split())
    if not 1 <= len(name) <= MAX_NAME_CHARS:
        raise UsageError(f"names must be 1-{MAX_NAME_CHARS} characters")
    return name


def read_names(path: Path) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        raise UsageError("cannot read the names file (UTF-8 text, one name per line)")
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        raise UsageError("the names file is empty")
    if len(lines) > MAX_COUNT:
        raise UsageError(f"at most {MAX_COUNT} names")
    return [clean_name(line) for line in lines]


def check_environment(env: dict[str, str]) -> tuple[str, str]:
    """Returns (supabase_url, secret_key) or raises UsageError. Never echoes a value."""
    if env.get("GITHUB_ACTIONS") or env.get("CI"):
        raise UsageError(
            "refusing to run in CI: the secret key must never be in a workflow "
            "and the cards hold live codes. Run this on your own computer."
        )
    url = (env.get("SUPABASE_URL") or "").strip().rstrip("/")
    key = env.get("SUPABASE_SECRET_KEY") or ""
    if not SUPABASE_URL_RE.fullmatch(url):
        raise UsageError(
            "SUPABASE_URL must be https://<project-ref>.supabase.co "
            "(or http://127.0.0.1:<port> for a local stack)"
        )
    if not key or key != key.strip() or re.search(r"\s", key) or not 20 <= len(key) <= 400:
        raise UsageError("SUPABASE_SECRET_KEY is missing or malformed (set it in the environment)")
    return url, key


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="make_invites",
        description="Create gym invites and print them as a PDF of QR cards. "
        "SUPABASE_URL and SUPABASE_SECRET_KEY are read from the environment only.",
        allow_abbrev=False,
    )
    parser.add_argument("--gym", help="gym id (uuid)")
    parser.add_argument("--count", type=int, help=f"how many invites (1-{MAX_COUNT})")
    parser.add_argument("--names", type=Path, help="text file, one trainee name per line")
    parser.add_argument("--logo", type=Path, help="PNG/JPEG for the QR centre (default: the gym's logo)")
    parser.add_argument("--out", type=Path, help="PDF path (default: ~/azm-invites/…)")
    parser.add_argument("--edit-targets", action="store_true", help="trainees may edit targets")
    parser.add_argument("--edit-plan", action="store_true", help="trainees may edit the whole plan")
    parser.add_argument("--build-own-plan", action="store_true", help="trainees may build their own plan")
    parser.add_argument("--dry-run", action="store_true", help="draw sample cards, touch no server")
    parser.add_argument("--gym-name", help="gym name on the cards (dry run only)")
    return parser


@dataclasses.dataclass(frozen=True)
class Options:
    gym_id: Optional[str]
    count: int
    names: Optional[list[str]]
    logo_path: Optional[Path]
    out: Path
    permissions: tuple[bool, bool, bool]
    dry_run: bool
    gym_name: Optional[str]


def parse_options(argv: list[str], now: dt.datetime) -> Options:
    args = build_parser().parse_args(argv)
    names = read_names(args.names) if args.names else None
    if args.dry_run:
        if args.gym and not UUID_RE.fullmatch(args.gym):
            raise UsageError("--gym must be a uuid")
    else:
        if args.gym_name:
            raise UsageError("--gym-name is only for --dry-run")
        if not args.gym or not UUID_RE.fullmatch(args.gym.strip().lower()):
            raise UsageError("--gym <gym uuid> is required")
    count = args.count
    if names is not None:
        if count is not None and count != len(names):
            raise UsageError("--count does not match the number of names")
        count = len(names)
    if count is None or not 1 <= count <= MAX_COUNT:
        raise UsageError(f"--count must be 1-{MAX_COUNT}")
    gym_name = clean_name(args.gym_name) if args.gym_name else None
    if args.dry_run and gym_name is None:
        gym_name = "Sample Gym"
    stamp = now.strftime("%Y%m%d-%H%M")
    gym_id = args.gym.strip().lower() if args.gym else None
    short = (gym_id or "sample")[:8]
    out = args.out or Path.home() / "azm-invites" / f"invites-{short}-{stamp}.pdf"
    return Options(
        gym_id=gym_id,
        count=count,
        names=names,
        logo_path=args.logo,
        out=out.expanduser(),
        permissions=(args.edit_targets, args.edit_plan, args.build_own_plan),
        dry_run=args.dry_run,
        gym_name=gym_name,
    )


# --------------------------------------------------------------------------
# Output file
# --------------------------------------------------------------------------
def check_output_path(path: Path) -> Path:
    """The cards hold live codes: never inside the repository, never overwrite."""
    resolved = path.expanduser().resolve()
    if resolved == REPO_ROOT or REPO_ROOT in resolved.parents:
        raise UsageError("the PDF holds live codes: choose a path outside the repository")
    if resolved.suffix.lower() != ".pdf":
        raise UsageError("the output file must end in .pdf")
    if resolved.exists():
        raise UsageError("the output file already exists; choose another name")
    return resolved


def write_private_file(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)


# --------------------------------------------------------------------------
# QR with the gym logo in the centre
# --------------------------------------------------------------------------
def load_logo(data: bytes):
    """A PNG/JPEG logo as an RGBA image, or UsageError. Size, type and pixel
    count are checked before and after decoding."""
    from PIL import Image

    if len(data) > MAX_LOGO_BYTES:
        raise UsageError("the logo is larger than 512 KB")
    if not (data.startswith(b"\x89PNG\r\n\x1a\n") or data.startswith(b"\xff\xd8\xff")):
        raise UsageError("the logo must be a PNG or JPEG file")
    Image.MAX_IMAGE_PIXELS = MAX_LOGO_PIXELS
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
        return image.convert("RGBA")
    except Exception:  # corrupt, truncated, decompression bomb…
        raise UsageError("the logo could not be read as an image")


def make_qr(url: str, logo=None, logo_fraction: float = LOGO_SIDE_DEFAULT):
    """The QR for [url] as an RGB image. Error correction H; the logo box is
    [logo_fraction] of the symbol's side and never more than 20 %. The result
    is decoded again and must give back exactly [url]."""
    import qrcode
    import zxingcpp
    from PIL import Image, ImageDraw

    if not 0 < logo_fraction <= LOGO_SIDE_MAX:
        raise ValueError("the logo box may cover at most 20 % of the QR side")
    qr = qrcode.QRCode(
        error_correction=qrcode.constants.ERROR_CORRECT_H, box_size=16, border=4
    )
    qr.add_data(url)
    qr.make(fit=True)
    image = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    box = qr.box_size
    symbol_side = qr.modules_count * box
    quiet = qr.border * box

    if logo is not None:
        side = int(symbol_side * logo_fraction)
        side -= side % 2  # even, so it centres exactly
        padding = max(4, side // 12)
        inner = side - 2 * padding
        fitted = logo.copy()
        fitted.thumbnail((inner, inner))
        tile = Image.new("RGB", (side, side), "white")
        ImageDraw.Draw(tile).rounded_rectangle(
            (0, 0, side - 1, side - 1), radius=padding * 2, fill="white"
        )
        tile.paste(fitted, ((side - fitted.width) // 2, (side - fitted.height) // 2), fitted)
        offset = quiet + (symbol_side - side) // 2
        image.paste(tile, (offset, offset))
        assert side <= symbol_side * LOGO_SIDE_MAX

    decoded = [r.text for r in zxingcpp.read_barcodes(image)]
    if decoded != [url]:
        raise RuntimeError("the QR with its logo could not be read back; use a simpler logo")
    return image


# --------------------------------------------------------------------------
# PDF
# --------------------------------------------------------------------------
@dataclasses.dataclass(frozen=True)
class Card:
    code: str
    name: str
    expires: str  # YYYY-MM-DD


_FONTS_READY = False


def _register_fonts() -> None:
    global _FONTS_READY
    if _FONTS_READY:
        return
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    for name, path in {
        "Inter": FONT_DIR / "Inter" / "Inter-400.ttf",
        "Inter-Bold": FONT_DIR / "Inter" / "Inter-700.ttf",
        "Cairo": FONT_DIR / "Cairo" / "Cairo-400.ttf",
        "Cairo-Bold": FONT_DIR / "Cairo" / "Cairo-700.ttf",
    }.items():
        pdfmetrics.registerFont(TTFont(name, str(path)))
    _FONTS_READY = True


def _text_image(text: str, bold: bool, size_pt: float, color: tuple[float, float, float]):
    """Arabic (and mixed) text drawn by Pillow with HarfBuzz/FriBiDi (libraqm):
    joined letters, right-to-left order, as an RGBA image at 8x scale. Returns
    (image, width_pt, height_pt). reportlab alone cannot shape Arabic."""
    from PIL import Image, ImageDraw, ImageFont, features

    if not features.check("raqm"):
        raise UsageError("this Pillow build cannot shape Arabic (libraqm missing)")
    scale = 8
    path = FONT_DIR / "Cairo" / ("Cairo-700.ttf" if bold else "Cairo-400.ttf")
    font = ImageFont.truetype(str(path), int(size_pt * scale), layout_engine=ImageFont.Layout.RAQM)
    left, top, right, bottom = font.getbbox(text, direction="rtl", language="ar")
    pad = scale
    image = Image.new("RGBA", (right - left + 2 * pad, bottom - top + 2 * pad), (0, 0, 0, 0))
    rgb = tuple(int(c * 255) for c in color)
    ImageDraw.Draw(image).text(
        (pad - left, pad - top), text, font=font, fill=rgb + (255,), direction="rtl", language="ar"
    )
    return image, image.width / scale, image.height / scale


def _draw_line(pdf, text: str, bold: bool, size: float, color, cx: float, y: float, max_width: float) -> None:
    """One centred line, shrunk until it fits [max_width] points. Arabic goes
    through [_text_image]; Latin text is drawn as real PDF text."""
    from reportlab.lib.utils import ImageReader
    from reportlab.pdfbase.pdfmetrics import stringWidth

    pdf.setFillColorRGB(*color)
    if _ARABIC.search(text):
        image, width, height = _text_image(text, bold, size, color)
        shrink = min(1.0, max_width / width)
        w, h = width * shrink, height * shrink
        pdf.drawImage(ImageReader(image), cx - w / 2, y - 0.25 * h, w, h, mask="auto")
        return
    font = "Inter-Bold" if bold else "Inter"
    while size > 5 and stringWidth(text, font, size) > max_width:
        size -= 0.25
    pdf.setFont(font, size)
    pdf.drawCentredString(cx, y, text)


def render_pdf(gym_name: str, cards: list[Card], qr_for: Callable[[str], object], sample: bool) -> bytes:
    """Four cards per A4 page (2 x 2), big enough to scan from a pinboard.
    Returns the PDF bytes."""
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.units import mm
    from reportlab.lib.utils import ImageReader
    from reportlab.pdfgen import canvas

    _register_fonts()
    buf = io.BytesIO()
    pdf = canvas.Canvas(buf, pagesize=A4, pageCompression=1)
    pdf.setTitle("Azm invites")
    page_w, page_h = A4
    margin = 10 * mm
    card_w = (page_w - 2 * margin) / 2
    card_h = (page_h - 2 * margin) / 2
    per_page = 4
    black, grey = (0.0, 0.0, 0.0), (0.35, 0.35, 0.35)

    for index, card in enumerate(cards):
        slot = index % per_page
        if index and slot == 0:
            pdf.showPage()
        col, row = slot % 2, slot // 2
        x = margin + col * card_w
        y = page_h - margin - (row + 1) * card_h
        mid = x + card_w / 2
        inner = card_w - 14 * mm

        pdf.setStrokeColorRGB(0.6, 0.6, 0.6)
        pdf.setDash(2, 2)
        pdf.rect(x + 2 * mm, y + 2 * mm, card_w - 4 * mm, card_h - 4 * mm)
        pdf.setDash()

        _draw_line(pdf, gym_name, True, 15, black, mid, y + card_h - 13 * mm, inner)
        _draw_line(pdf, card.name, False, 11, grey, mid, y + card_h - 19.5 * mm, inner)

        qr_size = 64 * mm
        pdf.drawImage(
            ImageReader(qr_for(card.code)), mid - qr_size / 2, y + card_h - 24 * mm - qr_size,
            qr_size, qr_size,
        )

        # The code, letter by letter: no text state (character spacing) leaks
        # into the lines below.
        pdf.setFillColorRGB(*black)
        pdf.setFont("Inter-Bold", 26)
        advance = 8.2 * mm
        start_x = mid - advance * (len(card.code) - 1) / 2
        for i, char in enumerate(card.code):
            pdf.drawCentredString(start_x + i * advance, y + 40 * mm, char)

        lines = [
            "Scan with your phone camera, or type this code in Azm.",
            "امسح الكود بكاميرا الموبايل أو اكتبه في تطبيق عزم.",
            f"Single use · expires {card.expires} · keep it private",
            f"يُستخدم مرة واحدة · ينتهي في {card.expires} · لا تشاركه",
        ]
        if sample:
            lines[2] = "SAMPLE CARD · this code does not work"
            lines[3] = "نموذج فقط · هذا الكود غير صالح"
        line_y = y + 31 * mm
        for text in lines:
            _draw_line(pdf, text, False, 8, grey, mid, line_y, inner)
            line_y -= 4.2 * mm
        _draw_line(pdf, join_url(card.code), False, 6.5, grey, mid, y + 9 * mm, inner)

    pdf.showPage()
    pdf.save()
    return buf.getvalue()


# --------------------------------------------------------------------------
# Supabase (REST). The key goes in the `apikey` header only.
# --------------------------------------------------------------------------
Transport = Callable[[str, str, dict, Optional[bytes]], tuple[int, bytes]]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """urllib would re-send our headers, the secret key included, to wherever a
    redirect points. Supabase's API never redirects, so any redirect is an error."""

    def redirect_request(self, *args, **kwargs):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def urllib_transport(method: str, url: str, headers: dict, body: Optional[bytes]) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with _OPENER.open(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return response.status, response.read(8 * 1024 * 1024)
    except urllib.error.HTTPError as error:
        return error.code, error.read(64 * 1024)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ApiError("cannot reach Supabase (network error or timeout)")


class Api:
    def __init__(self, base_url: str, key: str, transport: Transport = urllib_transport):
        self._base = base_url
        self._key = key
        self._transport = transport

    def _safe(self, text: str) -> str:
        text = text.replace(self._key, "***")
        return text if re.fullmatch(r"[A-Za-z0-9_ .,:'\-]{0,120}", text) else ""

    def call(self, method: str, path: str, payload=None, extra_headers: Optional[dict] = None):
        headers = {"apikey": self._key, "content-type": "application/json", "accept": "application/json"}
        headers.update(extra_headers or {})
        body = json.dumps(payload).encode() if payload is not None else None
        status, raw = self._transport(method, self._base + path, headers, body)
        try:
            data = json.loads(raw) if raw else None
        except ValueError:
            data = None
        if not 200 <= status < 300:
            detail = ""
            if isinstance(data, dict):
                detail = self._safe(str(data.get("message") or data.get("code") or ""))
            raise ApiError(f"Supabase answered {status}" + (f": {detail}" if detail else ""))
        return data

    def gym(self, gym_id: str) -> dict:
        rows = self.call("GET", f"/rest/v1/gyms?id=eq.{gym_id}&deleted_at=is.null&select=name,logo_path")
        if not isinstance(rows, list) or len(rows) != 1:
            raise UsageError("no such gym")
        return rows[0]

    def logo(self, logo_path: str) -> Optional[bytes]:
        if not re.fullmatch(r"[0-9a-f-]{36}/logo\.(png|jpe?g)", logo_path or ""):
            return None
        status, raw = self._transport(
            "GET", f"{self._base}/storage/v1/object/gym-logos/{logo_path}", {"apikey": self._key}, None
        )
        return raw if status == 200 else None

    def create_invites(self, gym_id: str, count: int, names: Optional[list[str]], perms) -> list[dict]:
        rows = self.call("POST", "/rest/v1/rpc/admin_create_invites", {
            "p_gym_id": gym_id,
            "p_count": count,
            "p_names": names,
            "p_can_edit_targets": perms[0],
            "p_can_edit_plan": perms[1],
            "p_can_build_own_plan": perms[2],
        })
        if not isinstance(rows, list) or len(rows) != count:
            raise ApiError("unexpected answer from admin_create_invites")
        for row in rows:
            if not (isinstance(row, dict) and CODE_RE.fullmatch(str(row.get("code", "")))
                    and UUID_RE.fullmatch(str(row.get("invite_id", "")))):
                raise ApiError("unexpected answer from admin_create_invites")
        return rows

    def revoke(self, invite_ids: list[str], now: dt.datetime) -> None:
        ids = ",".join(i for i in invite_ids if UUID_RE.fullmatch(i))
        if ids:
            self.call("PATCH", f"/rest/v1/invites?id=in.({ids})", {"revoked_at": now.isoformat()},
                      {"prefer": "return=minimal"})


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def run(argv: list[str], env: dict[str, str], transport: Transport = urllib_transport,
        now: Optional[dt.datetime] = None, out=sys.stdout) -> int:
    now = now or dt.datetime.now(dt.timezone.utc)
    opts = parse_options(argv, now)
    if os.environ.get("GITHUB_ACTIONS") or env.get("GITHUB_ACTIONS") or env.get("CI"):
        raise UsageError("refusing to run in CI: run this on your own computer")
    out_path = check_output_path(opts.out)

    api: Optional[Api] = None
    gym_name = opts.gym_name or ""
    logo = None
    if not opts.dry_run:
        url, key = check_environment(env)
        api = Api(url, key, transport)
        gym = api.gym(opts.gym_id)
        gym_name = clean_name(gym["name"])
    if opts.logo_path is not None:
        try:
            logo = load_logo(opts.logo_path.read_bytes())
        except OSError:
            raise UsageError("cannot read the logo file")
    elif api is not None and gym.get("logo_path"):
        data = api.logo(gym["logo_path"])
        logo = load_logo(data) if data else None
    if logo is None:
        print("note: no logo, the QR is drawn without one", file=out)

    names = opts.names or [f"Trainee {i}" for i in range(1, opts.count + 1)]
    qr_cache: dict[str, object] = {}

    def qr_for(code: str):
        if code not in qr_cache:
            qr_cache[code] = make_qr(join_url(code), logo)
        return qr_cache[code]

    # Dry run first: every failure that can be found before codes exist is found
    # now, because a code can never be shown a second time.
    expires_preview = (now + dt.timedelta(days=7)).strftime("%Y-%m-%d")
    render_pdf(gym_name, [Card("SAMP2E", names[0], expires_preview)], qr_for, sample=True)

    if opts.dry_run:
        cards = [Card("SAMP2E", n, expires_preview) for n in names]
        write_private_file(out_path, render_pdf(gym_name, cards, qr_for, sample=True))
        print(f"dry run: {len(cards)} sample cards written to {out_path}", file=out)
        return 0

    assert api is not None
    rows = api.create_invites(opts.gym_id, opts.count, opts.names, opts.permissions)
    try:
        cards = [
            Card(r["code"], r["display_name"], str(r["expires_at"])[:10]) for r in rows
        ]
        write_private_file(out_path, render_pdf(gym_name, cards, qr_for, sample=False))
    except BaseException:
        # Codes that were never printed are useless: take them back.
        try:
            api.revoke([r["invite_id"] for r in rows], now)
            print("failed while drawing the cards; the new invites were revoked", file=out)
        except ApiError:
            print("failed while drawing the cards; revoke these invites in the dashboard", file=out)
        raise
    print(f"created {len(rows)} invites for “{gym_name}” (single use, expire {cards[0].expires})", file=out)
    print(f"cards: {out_path}", file=out)
    print("The PDF holds live codes. Print it, then delete the file; do not send or upload it.", file=out)
    return 0


def main() -> int:
    try:
        return run(sys.argv[1:], dict(os.environ))
    except UsageError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except ApiError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except Exception as error:  # print the error's type only: its text could carry values
        print(f"error: {type(error).__name__} while creating the cards", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
