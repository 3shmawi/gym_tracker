#!/usr/bin/env python3
"""Turns a push-up video into a pose recording (joints and times only).

Move games' tests replay real sets as landmark recordings
(docs/features/move_games.md -> Recordings). This runs on YOUR computer:
the video is read locally, never uploaded, and never written anywhere;
only the 13 joints the detector uses, their times and the model's
confidence end up in the JSON. Never commit the videos.

The model is MediaPipe Pose Landmarker "lite", the same BlazePose family as
Google ML Kit's base pose model in the app (same 33 landmarks), so the
recordings behave like the app's camera. Frames are sampled at 15 per
second, like the app (MlKitPoseSource sends at most 15).

Set up once (Python 3.9-3.12):
    python3 -m venv .venv && .venv/bin/pip install -r tool/pose_record/requirements.txt
Then:
    .venv/bin/python tool/pose_record/record.py my_set.mp4 \\
        --out test/fixtures/move/push_ups/side_left_10.json
and add the file and the reps you counted to
test/fixtures/move/push_ups/manifest.json.
"""
import argparse
import hashlib
import json
import math
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

# The model, pinned by URL and SHA-256 (checked 2026-11-13).
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
)
MODEL_SHA256 = "59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a"

# BlazePose landmark index for each joint the app uses (ML Kit uses the same
# numbering), in PoseJoint's names.
JOINTS = {
    "nose": 0,
    "leftShoulder": 11,
    "rightShoulder": 12,
    "leftElbow": 13,
    "rightElbow": 14,
    "leftWrist": 15,
    "rightWrist": 16,
    "leftHip": 23,
    "rightHip": 24,
    "leftKnee": 25,
    "rightKnee": 26,
    "leftAnkle": 27,
    "rightAnkle": 28,
}

VERSION = 1  # PoseRecording.version in the app
MAX_FRAMES = 30000  # PoseRecording.maxFrames


def _round(v):
    return round(float(v), 4)


def frame_json(t_ms, landmarks):
    """One frame in the app's format. [landmarks] is MediaPipe's list for
    one person (objects with x, y, visibility), or None when nobody was
    found. Anything not finite is dropped, like the app's decoder."""
    joints = {}
    if landmarks:
        for name, index in JOINTS.items():
            if index >= len(landmarks):
                continue
            lm = landmarks[index]
            x, y = float(lm.x), float(lm.y)
            vis = getattr(lm, "visibility", None)
            likelihood = float(vis) if vis is not None else 0.0
            if not all(math.isfinite(v) for v in (x, y, likelihood)):
                continue
            likelihood = min(1.0, max(0.0, likelihood))
            joints[name] = [_round(x), _round(y), _round(likelihood)]
    return {"t": round(float(t_ms), 1), "j": joints}


def recording_json(frames, aspect):
    return {"version": VERSION, "aspect": _round(aspect), "frames": frames[:MAX_FRAMES]}


def model_path(cache_dir):
    """The pinned model, downloaded once and checked every time."""
    path = Path(cache_dir) / "pose_landmarker_lite.task"
    if not path.exists():
        cache_dir = Path(cache_dir)
        cache_dir.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=cache_dir)
        os.close(fd)
        urllib.request.urlretrieve(MODEL_URL, tmp)  # noqa: S310 (https, pinned)
        os.replace(tmp, path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != MODEL_SHA256:
        path.unlink()
        sys.exit(f"The model's SHA-256 is {digest}, expected {MODEL_SHA256}. Deleted it.")
    return str(path)


def record(video, fps, cache_dir):
    import cv2  # comes with mediapipe
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision

    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        sys.exit(f"Can't open {video}")
    # Phone videos carry a rotation tag; OpenCV applies it by default.
    cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    options = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=model_path(cache_dir)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
    )
    frames = []
    aspect = 0.75
    step_ms = 1000.0 / fps
    next_ms = 0.0
    last_ms = -1.0
    with vision.PoseLandmarker.create_from_options(options) as model:
        while len(frames) < MAX_FRAMES:
            ok, image = cap.read()
            if not ok:
                break
            t_ms = cap.get(cv2.CAP_PROP_POS_MSEC)
            if t_ms < next_ms or t_ms <= last_ms:
                continue
            next_ms = t_ms + step_ms * 0.999
            last_ms = t_ms
            h, w = image.shape[:2]
            aspect = w / h
            rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            result = model.detect_for_video(
                mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), int(t_ms)
            )
            people = result.pose_landmarks
            frames.append(frame_json(t_ms, people[0] if people else None))
    cap.release()
    return recording_json(frames, aspect)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("video")
    p.add_argument("--out", required=True, help="the .json recording to write")
    p.add_argument("--fps", type=float, default=15.0, help="frames per second (the app: 15)")
    p.add_argument(
        "--cache",
        default=str(Path.home() / ".cache" / "azm_pose_record"),
        help="where the model is kept",
    )
    args = p.parse_args(argv)
    if not args.out.endswith(".json"):
        sys.exit("--out must be a .json file")
    if not 1 <= args.fps <= 60:
        sys.exit("--fps must be between 1 and 60")
    rec = record(args.video, args.fps, args.cache)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(rec, f, separators=(",", ":"))
        f.write("\n")
    found = sum(1 for fr in rec["frames"] if fr["j"])
    print(f"{args.out}: {len(rec['frames'])} frames, a body in {found}")


if __name__ == "__main__":
    main()
