"""Original synthesized music for one journey episode (numpy only).

Same theme for the whole series (120 BPM, minor, one bar = 2 s, the sound of
docs/brand/promo_video/music.py); each episode changes key, progression and
arpeggio from its seed. Scene cuts from the page's plan get a whoosh and a hit,
on-screen events a soft tick. Loudness is set later by mux.py (two-pass
loudnorm to -15 LUFS).

usage: python3 music.py plan.json out.wav
"""
import json
import sys

import numpy as np

SR = 44100
BEAT = 0.5
plan = json.load(open(sys.argv[1]))
D = plan['D']
N = int(SR * D)
rng = np.random.default_rng(plan['seed'])
L = np.zeros(N)
R = np.zeros(N)
side = np.ones(N)


def t_arr(n):
    return np.arange(n) / SR


def put(sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N or i < 0:
        return
    sig = sig[: N - i]
    L[i:i + len(sig)] += sig * gain * np.cos((pan + 1) * np.pi / 4)
    R[i:i + len(sig)] += sig * gain * np.sin((pan + 1) * np.pi / 4)


def fft_filter(x, lo=None, hi=None):
    """Brick-ish band filter in the frequency domain with soft edges."""
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    m = np.ones_like(f)
    if hi:
        m *= 1 / (1 + (f / hi) ** 4)
    if lo:
        m *= 1 / (1 + (lo / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(X * m, n)


def env(n, a=.01, r=.2):
    e = np.ones(n)
    na, nr = max(1, int(a * SR)), min(n, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(f, dur, det=0.0):
    ph = (t_arr(int(dur * SR)) * f * (1 + det)) % 1.0
    return 2 * ph - 1


def mtof(m):
    return 440 * 2 ** ((m - 69) / 12)


def kick(t, g=1.0):
    n = int(.42 * SR)
    tt = t_arr(n)
    f = 46 + 105 * np.exp(-tt * 30)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7.5)
    put(s, t, .9 * g)
    i, m = int(t * SR), int(.26 * SR)
    seg = side[i:i + m]
    side[i:i + m] = np.minimum(seg, 1 - .55 * np.exp(-np.linspace(0, 4, len(seg))))


def hat(t, g=1.0, open_=False):
    n = int((.18 if open_ else .05) * SR)
    s = fft_filter(rng.standard_normal(n), lo=7000) * np.exp(-t_arr(n) * (18 if open_ else 70))
    put(s, t, .16 * g, pan=.25)


def clap(t, g=1.0):
    n = int(.25 * SR)
    tt = t_arr(n)
    e = np.exp(-tt * 20)
    for k in (0, .011, .022):
        e += np.where(tt >= k, np.exp(-(tt - k) * 110), 0) * .5
    put(fft_filter(rng.standard_normal(n), lo=900, hi=6000) * e, t, .22 * g, pan=-.1)


def whoosh(t_cut, dur=.45, g=1.0):
    n = int(dur * SR)
    no = rng.standard_normal(n)
    sweep = np.linspace(0, 1, n) ** 2
    s = fft_filter(no, lo=400, hi=9000) * sweep * np.exp(-np.linspace(0, 1, n) * .2)
    put(s, t_cut - dur, .2 * g, pan=.2)
    put(s[::-1] * .35, t_cut, .2 * g, pan=-.2)


def hit(t, g=1.0):
    n = int(1.2 * SR)
    tt = t_arr(n)
    s = np.sin(2 * np.pi * 42 * tt) * np.exp(-tt * 3) * .8
    s += fft_filter(rng.standard_normal(n), hi=2500) * np.exp(-tt * 9) * .25
    put(s, t, .5 * g)


def tick(t, g=1.0):
    n = int(.09 * SR)
    tt = t_arr(n)
    s = np.sin(2 * np.pi * 1800 * tt) * np.exp(-tt * 60) + .5 * np.sin(2 * np.pi * 2700 * tt) * np.exp(-tt * 80)
    put(s, t, .07 * g, pan=float(rng.uniform(-.4, .4)))


def riser(t0, t1, g=1.0):
    n = int((t1 - t0) * SR)
    s = fft_filter(rng.standard_normal(n), lo=600, hi=8000) * np.linspace(0, 1, n) ** 2.5
    put(s, t0, .22 * g)


# ---------- harmony ----------
key = 57 + plan.get('key', 0)  # A minor + offset
PROGS = [[0, -4, 3, -2], [0, 3, -2, -4], [0, -4, -7, -2], [0, 5, 3, -2]]
prog = PROGS[plan['seed'] % len(PROGS)]
ARPS = [[0, 7, 12, 15, 12, 7, 3, 7], [0, 3, 7, 12, 7, 3, 7, 10], [12, 7, 3, 7, 15, 12, 7, 3], [0, 7, 10, 12, 15, 12, 10, 7]]
arp = ARPS[(plan['seed'] // 2) % len(ARPS)]
outro_t = D - 4.0
start = plan['intro']


def chord_at(bar):
    r = prog[bar % len(prog)]
    minor = r in (0, 5, -7)
    return r, [0, 3 if minor else 4, 7]


bars = int(np.ceil(D / 2.0))
for b in range(bars):
    t0 = b * 2.0
    root, tri = chord_at(b)
    # pad (whole song, softer under the intro)
    pad = np.zeros(int(2.0 * SR))
    for iv in tri:
        f = mtof(key - 12 + root + iv)
        for det in (-.004, .004):
            pad += saw(f, 2.0, det)
    pad = fft_filter(pad, hi=1400) * env(len(pad), .25, .3)
    put(pad, t0, .045 if t0 < start else .06, pan=.0)
    # bass on 8ths after the intro, until the outro
    if start <= t0 < outro_t:
        for k in range(4):
            tb = t0 + k * BEAT
            n = int(.42 * SR)
            f = mtof(key - 24 + root)
            s = (np.sin(2 * np.pi * f * t_arr(n)) + .35 * fft_filter(saw(f, .42), hi=600)) * env(n, .005, .2)
            put(s, tb, .32)
    # arpeggio (16ths) from the intro end to the end
    if t0 + 2.0 > start:
        for k in range(16):
            ta = t0 + k * .125
            if ta < start or ta >= D - .3:
                continue
            note = key + root + arp[k % len(arp)] + (12 if k >= 8 and b % 2 else 0)
            n = int(.2 * SR)
            s = fft_filter(saw(mtof(note), .2), hi=2800 + 1200 * np.sin(b)) * np.exp(-t_arr(n) * 16)
            put(s, ta, .055, pan=.35 if k % 2 else -.35)

# ---------- drums ----------
t = start
while t < outro_t - 1e-6:
    beat = int(round((t - start) / BEAT))
    kick(t)
    hat(t + BEAT / 2, open_=beat % 4 == 3)
    if beat % 2 == 1:
        clap(t)
    t += BEAT

# ---------- events ----------
riser(.2, start, .9)
hit(start, 1.0)
for c in plan['cuts'][1:]:
    if c < D - .1:
        whoosh(c, g=.9)
        hit(c, .45)
for h in plan['hits']:
    tick(h)

# ---------- mix ----------
mix = np.stack([L * side, R * side], 1)
fade = int(1.4 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
mix[: int(.02 * SR)] *= np.linspace(0, 1, int(.02 * SR))[:, None]
mix /= max(1e-9, np.abs(mix).max()) / .89
pcm = (mix * 32767).astype('<i2')
with open(sys.argv[2], 'wb') as fh:
    import wave
    w = wave.open(fh, 'wb')
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
    w.close()
print('music', sys.argv[2], f'{D:.1f}s')
