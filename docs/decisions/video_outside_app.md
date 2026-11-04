# Decision: how-to videos outside the app (stage V-D)

Status: **accepted** (2026-11-04, under the owner's standing go-ahead to
finish the plan; the owner can reopen it).

## Question
While a trainee watches a how-to video, can it keep playing when they leave
the app (system picture-in-picture, or audio in the background), so they can
watch while doing something else on the phone?

## The rule (checked 2026-11-04)
YouTube API Services Developer Policies, page "Last updated 2026-11-01 UTC"
(https://developers.google.com/youtube/terms/developer-policies). Among the
things API clients must not do:

> create, include, or promote features that play content, including audio or
> video components, from a background player, meaning a player that is not
> displayed in the page, tab, or screen that the user is viewing;

and

> modify, build upon, or block any portion or functionality of a YouTube
> player; separate, isolate, or modify the audio or video components of any
> YouTube audiovisual content […]

The embedded player is YouTube's own (`youtube_player_iframe` 6.0.2, see
`docs/features/exercise_videos.md`); every video we show plays through it.

## Options
| | Option | Verdict |
|---|---|---|
| A | System picture-in-picture (Android PiP activity, iOS AVPictureInPicture) | **No.** Once the app is left, the player is not on "the screen that the user is viewing" of our app; it is the background-player case. It would also mean taking the video out of YouTube's player. |
| B | Keep the audio playing in the background (iOS `UIBackgroundModes` audio, an Android media foreground service) | **No.** Exactly "a player that is not displayed". |
| C | The in-app floating mini player (stage V-C, board 4.1–4.3, at least 200×200) | **Yes.** It is still YouTube's player, visible on the screen the trainee is using, inside the app. |
| D | **Open in YouTube** (already on the card and the sheet) | **Yes.** For watching outside our app, YouTube's own app or site does it under YouTube's rules. |

## Decision
- No picture-in-picture and no background playback, now or later, while
  the videos come from YouTube.
- The player **pauses as soon as the app leaves the screen** (any lifecycle
  state but `resumed`: locked, app switcher, another app). This is enforced in
  `YouTubeSurface` (`didChangeAppLifecycleState` → `pauseVideo()`), so it
  doesn't depend on how each platform's WebView behaves.
- Inside the app, the mini player (V-C) is how a video keeps going while the
  trainee logs sets.
- To watch outside the app: **Open in YouTube**.

## Guard rails (tests)
`test/security/exercise_video_test.dart` fails if:
- the surface stops pausing on lifecycle changes;
- `ios/Runner/Info.plist` gains `UIBackgroundModes`;
- the Android manifest gains `supportsPictureInPicture="true"` or
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK`.

## To check on a device (not testable here)
- iOS: a WebView may offer its own picture-in-picture button for HTML5 video
  (notably on iPad). If YouTube's embedded player shows one in our app,
  revisit: turning it off would need a WebView setting, not a change to
  YouTube's player.
- Android: after locking the phone mid-video, the sound must stop.

## If the source changes
Videos the gym uploads to its own storage (not YouTube) would not fall under
these policies; PiP could be reconsidered then, with its own privacy and
storage review.
