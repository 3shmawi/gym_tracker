# Journey series renderer («من الصفر لحد النهارده»)

Renders the build-in-public episodes planned in
`docs/social/journey_series.md` (facts and sources:
`docs/social/journey_timeline.md`): vertical 1080×1920, 30 fps, 33–41 s,
Egyptian Arabic, original generated music at −15 LUFS, plus a 1080×1920 cover
per episode. Built on the promo-video approach (`docs/brand/promo_video/`):
HTML drawn frame by frame by Playwright, piped to ffmpeg.

The videos are not in git; they go to `build/journey/` (ignored).

## Render an episode

```bash
tool/journey_video/build.sh 03              # → build/journey/out/Azm_Journey_03.mp4 + _cover.jpg
tool/journey_video/build.sh 00 01 02        # several; JOBS=4 runs 4 at a time (default 2)
tool/journey_video/build.sh all
tool/journey_video/build.sh stills 03       # only stills of the key moments + contact sheet + cover (fast)
```

Needs node with Playwright (Chromium), python3 with numpy and Pillow, and
ffmpeg. One episode takes about 4–6 minutes on one core. Code uses the
system's JetBrains Mono (falls back to DejaVu Sans Mono).

Before posting, look at `build/journey/stills/sheet_<ep>.jpg`: no text cut
off, Arabic reads right to left, numbers not flipped, nothing secret.

## Files
| File | What |
|---|---|
| `episodes.js` | **The episodes, as data.** One object per episode: header (number, title, dates), cover, CTA, and a list of scenes with durations. Every fact has its source in a comment. Edit text and timing here. |
| `engine.js` | Builds an episode on the template: scene types, word-by-word Arabic (split on spaces only, so letters stay joined), counters, typed code, the PR timeline, intro/outro, header with «حلقة n من 11». `__seek(t)` sets the page to any exact time. |
| `journey.html` | The template: tokens (brand `#22C55E`, `#07120C`, trend colours), Cairo + Inter, layout. |
| `prs.js` | The 117 merged PRs with their day on `main`, for the timeline. |
| `render.js` | Playwright: `plan`, `video`, `stills`, `cover`; serves `build/journey/` on a local port so the promo iframe is same-origin. |
| `music.py` | numpy-only track per episode: one theme (120 BPM, minor, 1 bar = 2 s), key/progression/arpeggio from the episode's `seed`/`key`, a whoosh and hit on every cut, a tick on on-screen events. |
| `mux.py` | Two-pass loudnorm to −15 LUFS (true peak −1.5), AAC 192k, faststart. |
| `build.sh` | Prepares `build/journey/` (fonts, icon, goldens and store shots as JPG, the promo for episode 11) and runs the rest. |

## Scene types (in `episodes.js`)
`hook`, `say` (text, word by word; `*x*` = accent colour) · `counters`
(numbers that count up) · `shot` (a real screen in a phone; label says so) ·
`fan` (three screens) · `code` (typed, highlighted; `+ `/`- ` lines are a
diff) · `diagram` (a chain of boxes; `kind: 'bad' | 'good'`) · `options`
(✕/✓ list) · `split` (before/after) · `chips` · `steps` · `timeline` (every
merged PR as a square on its day; `highlight` PR ranges) · `promo` (a part
of the brand promo video, `from` seconds).

## Rules (from the series brief)
- Only facts with a source in the repo; a beat without one stays out.
- No secrets, e-mails, contributor names or internal URLs on screen. Code
  shown is copied from the named commit and reviewed.
- Screens come from the widget-test goldens (`test/**/goldens/`, Arabic,
  dark) and `store/`; their demo data (gym names, numbers) is the test's.
- Reels safe zone: key text between y 220 and y 1540; text ≥ 36 px.
