"""Checks the JSON the tool writes, without a video or the model:
    python3 -m unittest tool/pose_record/test_record.py
"""
import json
import math
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace as L

sys.path.insert(0, str(Path(__file__).parent))
import record  # noqa: E402


def body(n=33, **over):
    lms = [L(x=0.5, y=0.5, visibility=0.9) for _ in range(n)]
    for i, lm in over.items():
        lms[int(i[1:])] = lm
    return lms


class FrameJson(unittest.TestCase):
    def test_the_13_joints_in_the_apps_names(self):
        f = record.frame_json(66.67, body())
        self.assertEqual(f["t"], 66.7)
        self.assertEqual(set(f["j"]), set(record.JOINTS))
        self.assertEqual(f["j"]["leftShoulder"], [0.5, 0.5, 0.9])

    def test_nobody_found_is_an_empty_frame(self):
        self.assertEqual(record.frame_json(0, None)["j"], {})
        self.assertEqual(record.frame_json(0, [])["j"], {})

    def test_not_finite_values_are_dropped_and_likelihood_clamped(self):
        f = record.frame_json(
            0,
            body(
                i11=L(x=math.nan, y=0.5, visibility=0.9),
                i12=L(x=0.4, y=math.inf, visibility=0.9),
                i13=L(x=0.4, y=0.4, visibility=1.7),
                i14=L(x=0.4, y=0.4, visibility=None),
            ),
        )
        self.assertNotIn("leftShoulder", f["j"])
        self.assertNotIn("rightShoulder", f["j"])
        self.assertEqual(f["j"]["leftElbow"][2], 1.0)
        self.assertEqual(f["j"]["rightElbow"][2], 0.0)

    def test_short_landmark_lists_skip_missing_joints(self):
        self.assertEqual(set(record.frame_json(0, body(n=12))["j"]), {"nose", "leftShoulder"})

    def test_only_joints_and_times_are_written(self):
        rec = record.recording_json([record.frame_json(0, body())], 0.5625)
        self.assertEqual(set(rec), {"version", "aspect", "frames"})
        self.assertEqual(rec["version"], 1)
        self.assertEqual(set(rec["frames"][0]), {"t", "j"})
        json.dumps(rec)  # serialisable

    def test_never_more_than_the_apps_maximum(self):
        frames = [record.frame_json(i, None) for i in range(record.MAX_FRAMES + 5)]
        self.assertEqual(len(record.recording_json(frames, 1)["frames"]), record.MAX_FRAMES)


if __name__ == "__main__":
    unittest.main()
