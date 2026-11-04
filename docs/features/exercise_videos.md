# Feature: how-to videos (YouTube)

A how-to video on the exercise screen, played in YouTube's own embedded
player inside the app. Nothing is uploaded to or stored by us but the
11-character video id (and optional start/end seconds).

Design: https://claude.ai/artifact/VDxBpGdwNidSZgrGjfARJo (boards 3.1–3.3),
with one change approved by the owner on 2026-11-03: the player spans the full
width and is at least 200×200 (YouTube's minimum, see below); a 320-wide phone
gets black bands above and below.

| Stage | What | Status |
|---|---|---|
| V-A | Link parser + shared test vectors, library videos, the card, the player sheet, privacy, store forms | this change |
| V-B | The gym's own video (table, pgTAP, offline copy) | next |
| V-C | Floating mini player | later (the board's mini player must grow to 200×200) |
| V-D | Outside the app (picture-in-picture): [decision](../decisions/video_outside_app.md): no PiP or background play; the player pauses when the app leaves the screen | done |

## What the trainee sees (board 3.1–3.3)
- Under the exercise's name: **Watch how** and the video card: thumbnail with a
  play button, title, `channel · YouTube` (or `YouTube Shorts`). It never plays
  by itself; play opens the sheet.
- The sheet: "How-to video", close (48×48), the player (full width, ≥ 200
  high; a Short 9:16, centred), the title and channel, **Open in YouTube**.
  Nothing is drawn over the player; YouTube's controls and branding are
  untouched.
- States: loading (skeleton); owner turned embedding off (oEmbed 401) → dimmed
  thumbnail, "The video's owner doesn't allow it to play here" + Open in
  YouTube; removed or private (oEmbed 400/404) → compact "Video unavailable";
  a player error 101/150/152 (also age-restricted) → "This video can only be
  watched on YouTube"; offline with a copy → dimmed thumbnail + "Needs
  internet"; offline, never seen → "There's a video for this exercise. Needs
  internet".
- No duration on the card: oEmbed does not give one, and the YouTube Data API
  would need a key (the board's `[m:ss]` placeholder is left out).

## Where videos come from
Order: the gym's video (V-B), then the library's, then none (pictures and
steps only). Library videos: `lib/features/library/data/exercise_videos.dart`,
approved by the owner on 2026-11-03 from
[`exercise_video_candidates.md`](exercise_video_candidates.md) (Arabic first;
every id checked with oEmbed that day).

## Video links (the parser; the dashboard implements the same rules)
`lib/core/media/youtube_link.dart`; test vectors shared with the dashboard:
[`youtube_link_vectors.json`](youtube_link_vectors.json) (55 cases).
- `https` only; no user info, no port; ≤ 2048 characters; spaces around are
  trimmed. No `%` anywhere (`Uri.parse` decodes `%77` to `w`, so an encoded id
  or path would pass as a different one), no backslash, no space or non-ASCII
  inside.
- Hosts (case-insensitive): `youtube.com`, `www.youtube.com`, `m.youtube.com`,
  `youtu.be`, `youtube-nocookie.com`, `www.youtube-nocookie.com`.
  **Refused:** `music.youtube.com` (music, not how-to) and anything else.
- Paths: `/watch?v=ID`, `youtu.be/ID`, `/shorts/ID`, `/embed/ID` (the only
  path on the nocookie hosts). **Refused:** `/live/ID` (a stream is not a
  how-to clip; a finished one has a `/watch` link), channels, playlists.
- The id: exactly 11 of `[A-Za-z0-9_-]`; given twice → refused.
- Start: `t=` (`90`, `90s`, `1m30s`, `1h2m3s`) or `start=` (seconds), not both;
  end: `end=`. 0 ≤ start < end ≤ 12 h; `t=0` is no start. Other parameters are
  ignored.

## The player (youtube_player_iframe 6.0.2)
- YouTube's IFrame player in a WebView (`webview_flutter`), **privacy-enhanced
  mode** (`youtube-nocookie.com`, the package default, checked by
  `test/security/exercise_video_test.dart`).
- **Referer:** YouTube's Required Minimum Functionality asks WebView apps to
  identify themselves; the package loads the player page with
  `loadHtmlString(baseUrl: origin)`, which sets the Referer, and we pass
  `origin: https://com.mohager.azm` (the form in YouTube's own example).
- **Size:** at least 200×200 (`videoPlayerSize`, tested).
- Plays only after the trainee taps play (the sheet is then visible).
- Never downloads, never blocks ads, never hides YouTube branding.
- Tests use a fake player (`videoSurfaceProvider`): a WebView does not run in
  widget tests.

## Title, thumbnail, offline
- `OEmbedVideoInfoRepository`: `GET https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/shorts/<id>`
  (no key). The `/shorts/` form answers with a vertical size for a Short. Text
  from YouTube is cleaned (control and bidi characters removed, ≤ 200
  characters). 401/403 → embedding off; 400/404 → unavailable; anything else
  or offline → the phone's copy.
- The info is kept in shared preferences (`video.info.<id>`), the thumbnail
  (`https://i.ytimg.com/vi/<id>/hqdefault.jpg`, built from the id) in the
  phone's picture cache (`MediaCache`, owner's choice of 2026-11-03).
- **When it loads:** the thumbnail and title load **when the exercise screen
  opens** (owner's decision of 2026-11-03), so Google receives the device's IP
  address before play. The privacy policy says so.

## Privacy, terms and store forms
- `website/privacy.html` (EN + AR): the app uses YouTube API Services; what is
  sent (IP address when the card loads; viewing handled by YouTube); nothing
  personal sent or received; links to the Google Privacy Policy and the YouTube
  Terms of Service.
- `website/terms.html` (EN + AR): using the videos means agreeing to be bound
  by the YouTube Terms of Service (link).
- Store forms: `docs/release.md` → store forms.

## Analytics events
| Event | When | Properties |
|---|---|---|
| `video_played` | Play on the card | `source` (`library` / `gym`) |
| `video_open_in_youtube` | Open in YouTube (card or sheet) | `source` |
| `video_minimized` | (V-C) the sheet becomes the mini player | `source` |

No video id, title, channel or URL.

## Tests
- `test/core/media/youtube_link_test.dart`: the 55 shared vectors (other
  domains, `javascript:`, `http`, ports, `youtube.com@evil.com`,
  `youtube.com.evil.com`, backslashes, percent-encoding, 2100-character links,
  10/12-character ids, Cyrillic and punycode look-alikes, music, live).
- `test/core/media/video_info_test.dart`: oEmbed request, wide vs Short,
  401/403/404/400, server error and offline, hostile text, malformed id, the
  offline copy, every approved library video valid.
- `test/features/video/exercise_video_test.dart`: the player size rule, every
  card state, the sheet (full width, ≥ 200, problem view, nothing over the
  player), `screensUiTests` for 10 screens (32 variants + goldens each).
- `test/features/library/presentation/library_flows_test.dart`: on the real
  router: the card, play opens the (fake) player, Open in YouTube opens exactly
  `https://www.youtube.com/watch?v=<id>`, embedding off.
- `test/security/exercise_video_test.dart`: URLs only from the id, privacy-
  enhanced mode, the app's origin, thumbnails only from `i.ytimg.com`.
- The integration demo (play, shrink to the mini player, log a set, close)
  comes with V-C (the mini player).

## Docs read (2026-11-03)
- YouTube Required Minimum Functionality (updated 2026-11-01): Referer for
  WebViews (`loadDataWithBaseURL` / `loadHTMLString:baseURL:`), 200×200
  minimum, no overlays, no autoplay before visible.
- YouTube IFrame Player API (updated 2026-10-15): error codes 100, 101, 150,
  153 (missing Referer).
- YouTube Developer Policies (updated 2026-11-01): III.A (privacy policy and
  terms requirements), the background-player rule (for V-D).
- pub.dev: `youtube_player_iframe` 6.0.2 (2026-05-30, 160/160 points) and its
  source (`loadHtmlString` with `baseUrl`, `privacyEnhancedMode` default true,
  `YoutubeError`).
- oEmbed responses checked live for a Short and a normal video, a video with
  embedding off (401) and an unknown id (400).

## Demo & post
Hook: "Forgot how it's done? Watch it right in the app."
Scenario (V-C integration test): open Flat Dumbbell Press → Watch how → play →
Open in YouTube → close.
Captions: EN "A how-to video for every exercise, right next to your sets." ·
AR "فيديو يشرحلك كل تمرين، جنب مجموعاتك على طول."
Hashtags: #Azm #GymApp #Flutter #BuildInPublic
