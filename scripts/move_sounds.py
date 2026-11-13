#!/usr/bin/env python3
"""Makes the Move games sounds (assets/audio/move_*.wav) from plain tones.

Our own work, no samples: released as CC0 1.0 (public domain). Run it
again to change a sound; the output is the same every time.

    python3 scripts/move_sounds.py
"""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"


def note(freq, length, start=0.0, decay=18.0, level=0.5):
    """A soft glassy pluck: a sine and its octave, fading fast."""
    def sample(t):
        t -= start
        if t < 0 or t > length:
            return 0.0
        attack = min(1.0, t / 0.004)  # 4 ms: no click
        env = attack * math.exp(-decay * t)
        tone = math.sin(2 * math.pi * freq * t)
        tone += 0.35 * math.sin(2 * math.pi * freq * 2 * t)
        return level * env * tone / 1.35
    return sample


def write(name, length, notes):
    frames = bytearray()
    for i in range(int(RATE * length)):
        t = i / RATE
        v = sum(n(t) for n in notes)
        v = max(-1.0, min(1.0, v))
        frames += struct.pack("<h", int(v * 32767 * 0.8))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


# A block lands: one short note.
write("move_rep.wav", 0.16, [note(880, 0.16)])
# Every fifth block: two notes going up.
write("move_five.wav", 0.42, [
    note(784, 0.2, decay=12),
    note(1175, 0.3, start=0.11, decay=10),
])
