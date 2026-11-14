# Azm promo video (motion graphics)

A 103-second, 1920×1080 motion-graphics video of every feature of the app and
the captain's dashboard, in Egyptian Arabic, made to show gym owners and
captains what Azm does. Everything is drawn from the brand: the approved logo
animation (`docs/design/motion/splash_animation.dc.html`), the level figures,
the Design System tokens (glass cards, `#22C55E`, trend colours), Inter +
Cairo, the real Arabic strings from `lib/l10n/app_ar.arb` and
`dashboard/src/i18n/ar.ts`, and the exercise drawings in `assets/exercises/`.

The video file is not in git (about 50 MB). Build it:

```bash
docs/brand/promo_video/build.sh          # → docs/brand/promo_video/build/Azm_Promo_1080p.mp4
docs/brand/promo_video/build.sh still 37.2   # one frame at 37.2 s → build/stills/
```

Needs node with Playwright (Chromium), python3 with numpy, scipy and Pillow,
and ffmpeg. Rendering takes about 6 minutes on 4 cores.

## How it works
- `index.html`: every scene as HTML/CSS (1920×1080, RTL).
- `timeline.js`: every movement is a paused Web Animation; `__seek(t)` sets
  the whole page to time `t`, so each frame is exact (no real-time playback).
- `render.js`: Playwright steps through the frames at 30 fps and pipes them to
  ffmpeg.
- `music.py`: an original synthesized track (120 BPM, A minor; one bar = 2 s,
  so scene changes land on bar lines) plus UI sounds on every tap, the rest
  notification, reps and clicks.

## Storyboard
| Time (s) | Scene |
|---|---|
| 0–8 | Logo animation → «عزم · AZM» → «تمرينك الجاي.. جاهز قبل ما توصل الجيم» |
| 8–14 | The problem: «آخر مرة شِلت كام؟» with notebook notes crossed out → «عزم فاكر عنك.» |
| 14–23 | 01 Next workout: Today screen, last weight and ↑ زوّد / → ثبّت / ↓ قلّل / أول مرة |
| 23–35 | 02 One-tap logging, 03 rest timer + "rest over" notification, supersets, saved after every tap |
| 35–43 | 04 Finish summary, new records, levels (beginner → intermediate → pro) |
| 43–50 | 05 Exercise library, pictures, how-to video and the floating mini player |
| 50–57 | 06 Move games: the camera counts push-ups, the Stack tower, no recording |
| 57–62 | 07 Backup: history comes back on a new phone; settings |
| 62–66 | «ودلوقتي.. دورك يا كابتن» |
| 66–74 | 08 Dashboard: members, add trainees, QR invite cards, the phone scans and joins |
| 74–80 | 09 Templates: edit once, apply to 12 trainees, «الكابتن حدّث خطتك» on the phone |
| 80–86 | 10 Trainee progress: KPIs and the best-weight chart with a new record |
| 86–92 | 11 Gym colour: the app follows the gym's colour (blue, orange, purple, green) |
| 92–103 | Recap of all features → logo, «جيمك.. في جيب كل متدرب», azmm.pages.dev |

Names, numbers and "Power Gym" are made up for the demo. The exercise
drawings are Everkinetic's (CC BY-SA 4.0); the credit is on the last frame.
To change a text, edit `index.html`; to change timing, edit the times in
`timeline.js` (and the matching sound times in `music.py`).
