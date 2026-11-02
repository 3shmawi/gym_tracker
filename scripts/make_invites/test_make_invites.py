"""Tests for make_invites.py. Run (from the repo root, inside the venv that
run.sh builds, or any venv with requirements.txt installed):

    python -m unittest discover -s scripts/make_invites -v

No network and no real secrets: the server is a fake transport, and the
"secret key" below is made up.
"""

import contextlib
import datetime as dt
import io
import json
import os
import random
import re
import stat
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_invites as mi  # noqa: E402

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
FAKE_KEY = "fake-key-for-tests-0123456789abcdef"
FAKE_URL = "https://abcdefghijklmnopqrst.supabase.co"
GYM_ID = "d0000000-0000-4000-8000-00000000000a"
NOW = dt.datetime(2026, 11, 2, 12, 0, tzinfo=dt.timezone.utc)
ENV = {"SUPABASE_URL": FAKE_URL, "SUPABASE_SECRET_KEY": FAKE_KEY}


def random_code(rng: random.Random) -> str:
    return "".join(rng.choice(ALPHABET) for _ in range(6))


def png_bytes(size=(200, 200), color=(10, 110, 60, 255)) -> bytes:
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGBA", size, color).save(buf, "PNG")
    return buf.getvalue()


class FakeServer:
    """Stands in for Supabase. Records every request."""

    def __init__(self, count_override=None, status=200, body=None, logo_path=None):
        self.requests = []
        self.rng = random.Random(7)
        self.count_override = count_override
        self.status = status
        self.body = body
        self.logo_path = logo_path
        self.codes = []

    def __call__(self, method, url, headers, body):
        self.requests.append((method, url, dict(headers), body))
        if self.status != 200:
            return self.status, json.dumps(self.body or {}).encode()
        if "/rest/v1/gyms" in url:
            return 200, json.dumps([{"name": "Heroes Gym", "logo_path": self.logo_path}]).encode()
        if "/storage/v1/object/gym-logos/" in url:
            return 200, png_bytes()
        if "/rpc/admin_create_demo_invite" in url:
            code = random_code(self.rng)
            self.codes.append(code)
            return 200, json.dumps({"invite_id": "f0000000-0000-4000-8000-0000000000dd", "code": code}).encode()
        if "/rpc/admin_create_invites" in url:
            payload = json.loads(body)
            n = self.count_override or payload["p_count"]
            names = payload["p_names"]
            rows = []
            for i in range(n):
                code = random_code(self.rng)
                self.codes.append(code)
                rows.append({
                    "membership_id": f"e0000000-0000-4000-8000-{i:012d}",
                    "display_name": names[i] if names else f"Trainee {i + 1}",
                    "invite_id": f"f0000000-0000-4000-8000-{i:012d}",
                    "code": code,
                    "expires_at": "2026-11-09T12:00:00+00:00",
                })
            return 200, json.dumps(rows).encode()
        if method == "PATCH":
            return 204, b""
        return 404, b"{}"


def run_cli(argv, env=ENV, server=None, now=NOW):
    out = io.StringIO()
    code = 0
    server = server or FakeServer()
    try:
        code = mi.run(argv, env, transport=server, now=now, out=out)
    except mi.UsageError as error:
        code = 2
        out.write(f"error: {error}")
    except mi.ApiError as error:
        code = 1
        out.write(f"error: {error}")
    return code, out.getvalue(), server


class CodesAndLinks(unittest.TestCase):
    def test_link_is_the_path_form_the_apps_claim(self):
        self.assertEqual(mi.join_url("ABC234"), "https://azmm.pages.dev/join/ABC234")

    def test_only_well_formed_codes_become_links(self):
        for bad in ["", "abc234", "ABC23", "ABC2345", "ABC230", "ABC23O", "ABC231", "ABC23I", "ABC23L",
                    "ABC23?", "ABC234\n", "A" * 10000, "../../x", "<script>", "'; drop--", None, 123456, b"ABC234"]:
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    mi.join_url(bad)


class Environment(unittest.TestCase):
    def test_accepts_a_good_environment(self):
        self.assertEqual(mi.check_environment(ENV), (FAKE_URL, FAKE_KEY))
        self.assertEqual(mi.check_environment({**ENV, "SUPABASE_URL": FAKE_URL + "/"})[0], FAKE_URL)
        self.assertEqual(mi.check_environment({**ENV, "SUPABASE_URL": "http://127.0.0.1:54321"})[0],
                         "http://127.0.0.1:54321")

    def test_refuses_to_run_in_ci(self):
        for var in ("GITHUB_ACTIONS", "CI"):
            with self.subTest(var=var):
                with self.assertRaises(mi.UsageError):
                    mi.check_environment({**ENV, var: "true"})

    def test_refuses_odd_urls_and_keys_without_echoing_them(self):
        urls = ["", "http://abcdefghijklmnopqrst.supabase.co", "https://evil.example",
                "https://abcdefghijklmnopqrst.supabase.co.evil.example", "https://abcdefghijklmnopqrst.supabase.co@evil.example",
                "https://abcdefghijklmnopqrst.supabase.co/rest", "http://evil.example:54321", "file:///etc/passwd"]
        for url in urls:
            with self.subTest(url=url):
                with self.assertRaises(mi.UsageError) as ctx:
                    mi.check_environment({**ENV, "SUPABASE_URL": url})
                self.assertNotIn(FAKE_KEY, str(ctx.exception))
        for key in ["", " ", FAKE_KEY + "\n", " " + FAKE_KEY, "short", "a b" * 20, "x" * 500]:
            with self.subTest(key=key):
                with self.assertRaises(mi.UsageError) as ctx:
                    mi.check_environment({**ENV, "SUPABASE_SECRET_KEY": key})
                if key.strip():
                    self.assertNotIn(key.strip(), str(ctx.exception))


class Arguments(unittest.TestCase):
    def parse(self, *argv):
        return mi.parse_options(list(argv), NOW)

    def test_there_is_no_way_to_pass_the_key_or_url_on_the_command_line(self):
        for flag in ("--key", "--secret", "--secret-key", "--token", "--url", "--supabase-url", "--ke"):
            with self.subTest(flag=flag), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    self.parse("--gym", GYM_ID, "--count", "1", flag, "value")
        options = [action.option_strings for action in mi.build_parser()._actions]
        for strings in options:
            for s in strings:
                self.assertFalse(re.search(r"key|secret|token|url|password", s), s)

    def test_hostile_values_are_refused(self):
        bad = [
            ("--gym", "not-a-uuid", "--count", "1"),
            ("--gym", GYM_ID + "'; --", "--count", "1"),
            ("--gym", "../../etc", "--count", "1"),
            ("--gym", GYM_ID, "--count", "0"),
            ("--gym", GYM_ID, "--count", "-5"),
            ("--gym", GYM_ID, "--count", "201"),
            ("--count", "5"),
            ("--gym", GYM_ID),
            ("--gym", GYM_ID, "--count", "1", "--gym-name", "x"),
        ]
        for argv in bad:
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises((mi.UsageError, SystemExit)):
                    self.parse(*argv)
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                self.parse("--gym", GYM_ID, "--count", "ten")

    def test_a_good_command_line(self):
        o = self.parse("--gym", GYM_ID.upper(), "--count", "20", "--edit-targets", "--build-own-plan")
        self.assertEqual((o.gym_id, o.count, o.permissions), (GYM_ID, 20, (True, False, True)))
        self.assertTrue(str(o.out).endswith("invites-d0000000-20261102-1200.pdf"))

    def test_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "names.txt"
            path.write_text("  Ali\u202e  Hassan \nMona\n\n\x07Sara\u200f\n", encoding="utf-8")
            self.assertEqual(mi.read_names(path), ["Ali Hassan", "Mona", "Sara"])
            o = self.parse("--gym", GYM_ID, "--names", str(path))
            self.assertEqual(o.count, 3)
            with self.assertRaises(mi.UsageError):
                self.parse("--gym", GYM_ID, "--names", str(path), "--count", "4")
            path.write_text("x" * 41, encoding="utf-8")
            with self.assertRaises(mi.UsageError):
                mi.read_names(path)
            path.write_text("\n  \n", encoding="utf-8")
            with self.assertRaises(mi.UsageError):
                mi.read_names(path)
            path.write_bytes(b"\xff\xfe\x00bad")
            with self.assertRaises(mi.UsageError):
                mi.read_names(path)
            path.write_text("\n".join(f"n{i}" for i in range(201)), encoding="utf-8")
            with self.assertRaises(mi.UsageError):
                mi.read_names(path)
            with self.assertRaises(mi.UsageError):
                mi.read_names(Path(tmp) / "missing.txt")


class OutputFile(unittest.TestCase):
    def test_never_inside_the_repository_and_never_overwrites(self):
        with self.assertRaises(mi.UsageError):
            mi.check_output_path(mi.REPO_ROOT / "cards.pdf")
        with self.assertRaises(mi.UsageError):
            mi.check_output_path(mi.REPO_ROOT / "scripts" / ".." / "x.pdf")
        with tempfile.TemporaryDirectory() as tmp:
            ok = Path(tmp) / "cards.pdf"
            self.assertEqual(mi.check_output_path(ok), ok.resolve())
            with self.assertRaises(mi.UsageError):
                mi.check_output_path(Path(tmp) / "cards.txt")
            ok.write_bytes(b"x")
            with self.assertRaises(mi.UsageError):
                mi.check_output_path(ok)
            link = Path(tmp) / "link.pdf"
            link.symlink_to(mi.REPO_ROOT / "evil.pdf")
            with self.assertRaises(mi.UsageError):
                mi.check_output_path(link)

    def test_file_is_private(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sub" / "a.pdf"
            mi.write_private_file(path, b"%PDF")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            with self.assertRaises(FileExistsError):
                mi.write_private_file(path, b"again")


class Logo(unittest.TestCase):
    def test_a_normal_logo_loads(self):
        self.assertEqual(mi.load_logo(png_bytes()).size, (200, 200))

    def test_bad_logos_are_refused(self):
        from PIL import Image

        big = io.BytesIO()
        Image.new("1", (20000, 20000)).save(big, "PNG")  # tiny file, 400 million pixels
        cases = {
            "too big": b"\x89PNG\r\n\x1a\n" + b"0" * (mi.MAX_LOGO_BYTES + 1),
            "not an image": b"<svg xmlns='http://www.w3.org/2000/svg'/>",
            "php": b"<?php system($_GET['c']); ?>",
            "empty": b"",
            "truncated png": png_bytes()[:60],
            "corrupt jpeg": b"\xff\xd8\xff" + b"garbage" * 10,
            "decompression bomb": big.getvalue(),
        }
        for name, data in cases.items():
            with self.subTest(name), self.assertRaises(mi.UsageError):
                mi.load_logo(data)


class QrCode(unittest.TestCase):
    def test_decodes_with_the_logo_at_three_sizes(self):
        import zxingcpp

        logo = mi.load_logo(png_bytes((300, 300), (200, 30, 30, 255)))
        url = mi.join_url("ABC234")
        for fraction in (0.10, mi.LOGO_SIDE_DEFAULT, mi.LOGO_SIDE_MAX):
            with self.subTest(fraction=fraction):
                image = mi.make_qr(url, logo, fraction)  # raises if it cannot be read back
                result = zxingcpp.read_barcodes(image)
                self.assertEqual([r.text for r in result], [url])
                self.assertEqual(result[0].ec_level, "H")

    def test_decodes_at_every_code_alphabet_corner(self):
        for code in ("AAAAAA", "999999", "ZZZZZZ", "222222", "HJKMNP"):
            mi.make_qr(mi.join_url(code), mi.load_logo(png_bytes()))

    def test_a_logo_over_20_percent_of_the_side_is_refused(self):
        logo = mi.load_logo(png_bytes())
        for fraction in (0.2001, 0.25, 0.5, 1, 0, -1):
            with self.subTest(fraction=fraction), self.assertRaises(ValueError):
                mi.make_qr(mi.join_url("ABC234"), logo, fraction)

    def test_works_without_a_logo(self):
        mi.make_qr(mi.join_url("ABC234"))

    def test_survives_damage_up_to_what_level_h_promises(self):
        import zxingcpp
        from PIL import ImageDraw

        image = mi.make_qr(mi.join_url("ABC234"), mi.load_logo(png_bytes()))
        w, h = image.size
        # A scratch over 8 % of the area, away from the centre and the finder patterns.
        ImageDraw.Draw(image).rectangle((w * 0.35, h * 0.62, w * 0.65, h * 0.90), fill="white")
        self.assertEqual([r.text for r in zxingcpp.read_barcodes(image)], [mi.join_url("ABC234")])


class Pdf(unittest.TestCase):
    def pages(self, data: bytes) -> int:
        return len(re.findall(rb"/Type /Page\b(?!s)", data))

    def test_four_cards_per_page_with_arabic_and_long_names(self):
        cards = [mi.Card("ABC234", n, "2026-11-09") for n in
                 ["محمد أشماوي", "x" * 40, "Sara", "يوسف", "Omar", "Ali ‮ evil"]]
        qr = lambda code: mi.make_qr(mi.join_url(code))  # noqa: E731
        data = mi.render_pdf("جيم الأبطال Heroes", cards, qr, sample=False)
        self.assertTrue(data.startswith(b"%PDF"))
        self.assertEqual(self.pages(data), 2)

    def test_a_hostile_name_is_only_text(self):
        cards = [mi.Card("ABC234", "'; drop table invites; --", "2026-11-09"),
                 mi.Card("ABC235", "<script>alert(1)</script>", "2026-11-09"),
                 mi.Card("ABC236", "(unbalanced ) ( parentheses \\", "2026-11-09")]
        data = mi.render_pdf("<b>Gym</b>", cards, lambda c: mi.make_qr(mi.join_url(c)), sample=False)
        self.assertEqual(self.pages(data), 1)


class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "cards.pdf"

    def tearDown(self):
        self.tmp.cleanup()

    def test_dry_run_needs_no_environment_and_no_network(self):
        def no_network(*_args):
            raise AssertionError("the dry run must not touch the network")

        out = io.StringIO()
        code = mi.run(["--dry-run", "--count", "5", "--out", str(self.out)], {}, no_network, NOW, out)
        self.assertEqual(code, 0)
        self.assertTrue(self.out.read_bytes().startswith(b"%PDF"))

    def test_happy_path(self):
        server = FakeServer()
        code, text, _ = run_cli(["--gym", GYM_ID, "--count", "9", "--edit-targets", "--out", str(self.out)], server=server)
        self.assertEqual(code, 0, text)
        data = self.out.read_bytes()
        self.assertTrue(data.startswith(b"%PDF"))
        self.assertEqual(len(re.findall(rb"/Type /Page\b(?!s)", data)), 3)
        self.assertEqual(stat.S_IMODE(self.out.stat().st_mode), 0o600)

        rpc = [r for r in server.requests if r[1].endswith("/rpc/admin_create_invites")]
        self.assertEqual(len(rpc), 1)
        self.assertEqual(json.loads(rpc[0][3]), {
            "p_gym_id": GYM_ID, "p_count": 9, "p_names": None,
            "p_can_edit_targets": True, "p_can_edit_plan": False, "p_can_build_own_plan": False,
        })
        # the key travels in the apikey header only, and only to the project URL
        for _method, url, headers, _body in server.requests:
            self.assertTrue(url.startswith(FAKE_URL))
            self.assertEqual(headers["apikey"], FAKE_KEY)
            self.assertNotIn("authorization", {k.lower() for k in headers})

    def test_nothing_secret_is_printed(self):
        server = FakeServer()
        code, text, _ = run_cli(["--gym", GYM_ID, "--count", "4", "--out", str(self.out)], server=server)
        self.assertEqual(code, 0)
        self.assertNotIn(FAKE_KEY, text)
        for secret in server.codes:
            self.assertNotIn(secret, text)

    def test_the_gym_logo_is_fetched_from_storage_when_none_is_given(self):
        server = FakeServer(logo_path=f"{GYM_ID}/logo.png")
        code, _text, _ = run_cli(["--gym", GYM_ID, "--count", "1", "--out", str(self.out)], server=server)
        self.assertEqual(code, 0)
        self.assertTrue(any("/storage/v1/object/gym-logos/" in r[1] for r in server.requests))

    def test_refuses_in_ci_before_any_request(self):
        server = FakeServer()
        code, text, _ = run_cli(["--gym", GYM_ID, "--count", "1", "--out", str(self.out)],
                                env={**ENV, "GITHUB_ACTIONS": "true"}, server=server)
        self.assertEqual(code, 2)
        self.assertEqual(server.requests, [])
        self.assertFalse(self.out.exists())

    def test_server_errors_never_echo_the_key(self):
        for status, body in [(401, {"message": f"bad key {FAKE_KEY}"}), (500, {"message": "<html>" + "x" * 500}),
                             (403, {"code": "42501", "message": "permission denied for function"}), (404, None)]:
            with self.subTest(status=status):
                code, text, server = run_cli(["--gym", GYM_ID, "--count", "1", "--out", str(self.out)],
                                             server=FakeServer(status=status, body=body))
                self.assertEqual(code, 1)
                self.assertNotIn(FAKE_KEY, text)
                self.assertNotIn("<html>", text)
                self.assertFalse(self.out.exists())

    def test_a_surprising_server_answer_is_refused(self):
        code, text, _ = run_cli(["--gym", GYM_ID, "--count", "3", "--out", str(self.out)],
                                server=FakeServer(count_override=2))
        self.assertEqual(code, 1)
        self.assertFalse(self.out.exists())

    def test_invites_are_revoked_when_the_cards_cannot_be_drawn(self):
        server = FakeServer()
        real = mi.render_pdf
        calls = {"n": 0}

        def flaky(*args, **kwargs):
            calls["n"] += 1
            if calls["n"] == 2:  # the first call is the pre-flight check
                raise RuntimeError("disk on fire")
            return real(*args, **kwargs)

        mi.render_pdf = flaky
        try:
            with self.assertRaises(RuntimeError):
                run_cli(["--gym", GYM_ID, "--count", "2", "--out", str(self.out)], server=server)
        finally:
            mi.render_pdf = real
        patches = [r for r in server.requests if r[0] == "PATCH"]
        self.assertEqual(len(patches), 1)
        self.assertIn("f0000000-0000-4000-8000-000000000000", patches[0][1])
        self.assertFalse(self.out.exists())

    def test_the_preflight_stops_a_bad_logo_before_any_code_exists(self):
        server = FakeServer()
        bad = Path(self.tmp.name) / "logo.png"
        bad.write_bytes(b"not an image")
        code, _text, _ = run_cli(["--gym", GYM_ID, "--count", "2", "--logo", str(bad), "--out", str(self.out)],
                                 server=server)
        self.assertEqual(code, 2)
        self.assertFalse(any(r[1].endswith("/rpc/admin_create_invites") for r in server.requests))


class Redirects(unittest.TestCase):
    def test_the_key_is_never_sent_to_a_redirect_target(self):
        import http.server
        import threading

        seen = []

        class Target(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen.append(self.headers.get("apikey"))
                self.send_response(200)
                self.end_headers()

            def log_message(self, *args):
                pass

        target = http.server.HTTPServer(("127.0.0.1", 0), Target)

        class Redirector(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", f"http://127.0.0.1:{target.server_port}/steal")
                self.end_headers()

            def log_message(self, *args):
                pass

        redirector = http.server.HTTPServer(("127.0.0.1", 0), Redirector)
        for server in (target, redirector):
            threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            status, _ = mi.urllib_transport(
                "GET", f"http://127.0.0.1:{redirector.server_port}/x", {"apikey": FAKE_KEY}, None
            )
        finally:
            target.shutdown()
            redirector.shutdown()
        self.assertEqual(status, 302)
        self.assertEqual(seen, [], "the key reached the redirect target")


class DemoCard(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "demo.pdf"

    def tearDown(self):
        self.tmp.cleanup()

    def test_makes_one_card_and_prints_no_code(self):
        server = FakeServer()
        code, text, _ = run_cli(["--demo", "--gym", GYM_ID, "--out", str(self.out)], server=server)
        self.assertEqual(code, 0, text)
        self.assertTrue(self.out.read_bytes().startswith(b"%PDF"))
        self.assertEqual(len(re.findall(rb"/Type /Page\b(?!s)", self.out.read_bytes())), 1)
        calls = [r for r in server.requests if r[1].endswith("/rpc/admin_create_demo_invite")]
        self.assertEqual(json.loads(calls[0][3]), {"p_gym_id": GYM_ID})
        self.assertFalse(any(r[1].endswith("/rpc/admin_create_invites") for r in server.requests))
        for secret in server.codes + [FAKE_KEY]:
            self.assertNotIn(secret, text)

    def test_refuses_options_that_do_not_apply(self):
        for extra in (["--count", "3"], ["--names", "x.txt"], ["--edit-plan"], ["--dry-run"]):
            with self.subTest(extra=extra):
                code, _text, server = run_cli(["--demo", "--gym", GYM_ID, "--out", str(self.out)] + extra)
                self.assertIn(code, (2,))
                self.assertEqual(server.requests, [])

    def test_needs_a_gym_and_never_runs_in_ci(self):
        self.assertEqual(run_cli(["--demo", "--out", str(self.out)])[0], 2)
        server = FakeServer()
        code, _text, _ = run_cli(["--demo", "--gym", GYM_ID, "--out", str(self.out)],
                                 env={**ENV, "CI": "true"}, server=server)
        self.assertEqual(code, 2)
        self.assertEqual(server.requests, [])

    def test_the_new_demo_code_is_revoked_if_the_card_cannot_be_drawn(self):
        server = FakeServer()
        real = mi.render_pdf
        calls = {"n": 0}

        def flaky(*args, **kwargs):
            calls["n"] += 1
            if calls["n"] == 2:
                raise RuntimeError("disk on fire")
            return real(*args, **kwargs)

        mi.render_pdf = flaky
        try:
            with self.assertRaises(RuntimeError):
                run_cli(["--demo", "--gym", GYM_ID, "--out", str(self.out)], server=server)
        finally:
            mi.render_pdf = real
        self.assertEqual(len([r for r in server.requests if r[0] == "PATCH"]), 1)
        self.assertFalse(self.out.exists())


class SourceRules(unittest.TestCase):
    """docs/security.md → 'CI and secrets': what the tooling must never do."""

    here = Path(__file__).resolve().parent

    def test_no_tracing_no_verbose_no_secret_in_files(self):
        for name in ("run.sh", "make_invites.py"):
            text = (self.here / name).read_text(encoding="utf-8")
            self.assertIsNone(re.search(r"set -[a-z]*x|xtrace|curl -v|--verbose", text), name)
            self.assertIsNone(re.search(r"sb_secret_[A-Za-z0-9_-]{10,}|eyJ[A-Za-z0-9_-]{20,}\.", text), name)

    def test_the_key_is_only_read_from_the_environment(self):
        text = (self.here / "make_invites.py").read_text(encoding="utf-8")
        self.assertIn('env.get("SUPABASE_SECRET_KEY")', text)
        self.assertNotIn("print(key", text)
        self.assertNotIn("traceback", text)

    def test_the_wrapper_is_pinned_and_refuses_ci(self):
        text = (self.here / "run.sh").read_text(encoding="utf-8")
        self.assertIn("--require-hashes", text)
        self.assertIn("python\" -I", text)
        self.assertIn("GITHUB_ACTIONS", text)

    def test_every_requirement_is_pinned_with_hashes(self):
        text = (self.here / "requirements.txt").read_text(encoding="utf-8")
        entries = re.findall(r"^([A-Za-z0-9_.-]+)(==\S+)? \\\n((?:\s+--hash=sha256:[0-9a-f]{64}(?: \\)?\n?)+)", text, re.M)
        self.assertGreaterEqual(len(entries), 5)
        for name, version, _hashes in entries:
            self.assertTrue(version.startswith("=="), name)


if __name__ == "__main__":
    unittest.main()
