"""Original synthesized soundtrack + UI sound effects for the Azm promo (120 BPM, A minor)."""
import numpy as np
from scipy.signal import butter, sosfilt
from scipy.io import wavfile

SR = 44100
D = 103.0
N = int(SR * D)
BEAT = 0.5
rng = np.random.default_rng(4)
L = np.zeros(N)
R = np.zeros(N)
side = np.ones(N)  # sidechain envelope (filled by kicks)


def t_arr(n):
    return np.arange(n) / SR


def put(sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= N:
        return
    sig = sig[: N - i]
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    L[i:i + len(sig)] += sig * gain * l
    R[i:i + len(sig)] += sig * gain * r


def lp(x, f, order=2):
    return sosfilt(butter(order, f, 'low', fs=SR, output='sos'), x)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, 'high', fs=SR, output='sos'), x)


def bp(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], 'band', fs=SR, output='sos'), x)


def saw(f, dur, detune=0.0):
    t = t_arr(int(dur * SR))
    ph = (t * f * (1 + detune)) % 1.0
    return 2 * ph - 1


def env_adsr(n, a=.01, d=.1, s=.7, r=.2):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(na, 1)
    e[:na] = np.linspace(0, 1, na)
    e[na:na + nd] = np.linspace(1, s, len(e[na:na + nd]))
    if nr > 0:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def kick(t, g=1.0):
    n = int(.45 * SR)
    tt = t_arr(n)
    f = 45 + 110 * np.exp(-tt * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-tt * 7.5)
    s += .3 * np.exp(-tt * 300) * rng.standard_normal(n) * .3
    put(s, t, .95 * g)
    i = int(t * SR)
    m = int(.28 * SR)
    seg = side[i:i + m]
    side[i:i + m] = np.minimum(seg, 1 - .6 * np.exp(-np.linspace(0, 1, len(seg)) * 4)[: len(seg)])


def clap(t, g=1.0):
    n = int(.3 * SR)
    tt = t_arr(n)
    no = rng.standard_normal(n)
    e = np.exp(-tt * 18)
    for k in (0.0, .012, .024):
        e += np.where(tt >= k, np.exp(-(tt - k) * 120), 0) * .6
    s = bp(no, 900, 4000) * e
    put(s, t, .35 * g, -.1)
    put(s, t + .01, .25 * g, .2)


def hat(t, g=1.0, open_=False):
    n = int((.25 if open_ else .06) * SR)
    tt = t_arr(n)
    s = hp(rng.standard_normal(n), 7000) * np.exp(-tt * (12 if open_ else 70))
    put(s, t, .16 * g, .35 if open_ else -.3)


def bass(t, f, dur, g=1.0):
    s = saw(f, dur) * .6 + saw(f, dur, .004) * .4
    s = lp(s, 380)
    s += np.sin(2 * np.pi * f * t_arr(len(s))) * .6
    s *= env_adsr(len(s), .005, .08, .8, .06)
    put(s, t, .42 * g)


def note(n):
    return 440 * 2 ** ((n - 69) / 12)


CH = {  # bar chords (midi)
    'Am': ([57, 60, 64, 69], 45), 'F': ([53, 57, 60, 65], 41), 'C': ([55, 60, 64, 67], 48), 'G': ([55, 59, 62, 67], 43),
}
PROG = ['Am', 'F', 'C', 'G']


def pad(t, chord, dur, g=1.0, cutoff=2200):
    notes, _ = CH[chord]
    s = np.zeros(int(dur * SR))
    for m in notes:
        for dt in (-.006, .0, .007):
            s += saw(note(m), dur, dt)
    s = lp(s / 12, cutoff)
    s *= env_adsr(len(s), .25, .3, .85, .5)
    put(s, t, .30 * g, -.25)
    put(s[::-1][::-1], t + .012, .30 * g, .25)


def pluck(t, f, g=1.0, pan=0.0):
    n = int(.35 * SR)
    s = saw(f, .35) * .6 + np.sin(2 * np.pi * f * 2 * t_arr(n)) * .3
    s = lp(s, 3500) * np.exp(-t_arr(n) * 11)
    put(s, t, .16 * g, pan)


def riser(t0, t1, g=1.0):
    n = int((t1 - t0) * SR)
    tt = np.linspace(0, 1, n)
    no = rng.standard_normal(n)
    out = np.zeros(n)
    blocks = 40
    for b in range(blocks):
        a, z = b * n // blocks, (b + 1) * n // blocks
        f = 400 + 7000 * (b / blocks) ** 2
        out[a:z] = bp(no[a:z], f, min(f * 1.6, 18000))
    out *= tt ** 2
    put(out, t0, .35 * g)


def impact(t, g=1.0):
    n = int(2.5 * SR)
    tt = t_arr(n)
    f = 38 + 80 * np.exp(-tt * 10)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 2.2)
    s += lp(rng.standard_normal(n), 1500) * np.exp(-tt * 5) * .5
    put(s, t, .9 * g)
    kick(t, .6)


def whoosh(t, dur=.5, g=1.0, pan=0.0):
    n = int(dur * SR)
    tt = np.linspace(0, 1, n)
    s = bp(rng.standard_normal(n), 600, 5000) * np.sin(np.pi * tt) ** 2
    put(s, t - dur * .6, .22 * g, pan)


def tapfx(t, g=1.0, f=1800):
    n = int(.08 * SR)
    tt = t_arr(n)
    s = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 70) + np.sin(2 * np.pi * f * 1.5 * tt) * np.exp(-tt * 90) * .4
    put(s, t, .22 * g, .1)


def ding(t, g=1.0):
    n = int(1.2 * SR)
    tt = t_arr(n)
    s = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * d) * a for f, d, a in [(1318.5, 3, 1), (1975.5, 4, .5), (2637, 6, .25)])
    put(s, t, .2 * g)
    s2 = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * d) * a for f, d, a in [(1760, 3, 1), (2637, 4, .4)])
    put(s2, t + .14, .18 * g)


def blip(t, f, g=1.0):
    n = int(.18 * SR)
    tt = t_arr(n)
    s = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 18)
    put(s, t, .2 * g)


def sparkle(t, g=1.0):
    for k in range(14):
        blip(t + k * .045 + rng.random() * .02, 2000 + rng.random() * 3000, .35 * g)


# ---------------- arrangement ----------------
def bar_t(b):
    return b * 2.0


# intro 0-8: pad + plucks
for b in range(4):
    pad(bar_t(b), PROG[b % 4], 2.1, .8, 1200 + b * 300)
arp = [69, 72, 76, 72]
for i in range(8, 32):
    pluck(i * .25, note(arp[i % 4] + (0 if (i // 8) % 2 == 0 else -4)), .5 + i / 64, .3 if i % 2 else -.3)
riser(5.0, 8.0, 1.0)
whoosh(3.45, .7, .7)
impact(8.0)


def groove(b0, b1, full=True, hats16=False):
    for b in range(b0, b1):
        t0 = bar_t(b)
        ch = PROG[b % 4]
        pad(t0, ch, 2.05, .75 if full else .55)
        root = CH[ch][1]
        for q in range(4):
            tq = t0 + q * BEAT
            if full or q % 2 == 0:
                kick(tq)
            if q in (1, 3):
                clap(tq, .9 if full else .6)
            hat(tq + .25, 1.0, open_=full and q == 3)
            if hats16:
                hat(tq + .125, .55)
                hat(tq + .375, .55)
            # bass: off-beat eighths
            bass(tq + .25, note(root), .22, .95)
            if q == 0:
                bass(tq, note(root), .2, .7)
        if full:
            mel = [76, 74, 72, 74] if b % 2 == 0 else [72, 71, 69, 67]
            for k, m in enumerate(mel):
                pluck(t0 + k * .5 + .0, note(m), .55, (-.4, .4)[k % 2])


groove(4, 7, full=False)          # 8-14 problem
groove(7, 31, full=True, hats16=False)  # 14-62 app
for b in (16, 17, 18, 19, 24, 25, 26, 27):  # extra energy in some bars
    for q in range(4):
        hat(bar_t(b) + q * BEAT + .125, .5)
        hat(bar_t(b) + q * BEAT + .375, .5)
riser(60.0, 62.0, .9)
impact(62.0, .6)
# breakdown 62-66
for b in (31, 32):
    pad(bar_t(b), PROG[b % 4], 2.1, 1.0, 900)
for i in range(16):
    pluck(62 + i * .25, note([69, 72, 76, 79][i % 4]), .45, .3 if i % 2 else -.3)
riser(64.0, 66.0, 1.1)
impact(66.0, 1.0)
groove(33, 46, full=True, hats16=True)   # 66-92 dashboard
riser(90.2, 92.0, .8)
groove(46, 48, full=False)               # 92-96 recap
riser(94.0, 95.7, 1.0)
impact(95.7, 1.1)
pad(95.7, 'Am', 7.0, 1.1, 1600)
for i in range(12):
    pluck(95.7 + i * .5, note([69, 76, 72, 81][i % 4]), .4 * (1 - i / 14), .3 if i % 2 else -.3)

# ---------------- sound effects ----------------
for t in (14.0, 22.85, 35.3, 43.35, 45.3, 49.8, 57.6, 61.5, 66.0, 73.9, 80.0, 86.0, 91.5):
    whoosh(t, .55, .9)
for t in (22.35, 25.3, 26.45, 32.7, 33.45, 34.7, 44.85, 46.3, 47.85):
    tapfx(t)
for t in (68.45, 70.6, 75.35, 76.55, 87.35, 88.75, 89.95, 91.15):
    tapfx(t, .8, 2400)
ding(30.85)
sparkle(35.95)
sparkle(72.65, .7)
for k in range(8):
    blip(50.75 + .7 * (k + 1), note(72 + [0, 2, 4, 5, 7, 9, 11, 12][k]), .9)
for i, t in enumerate((17.4, 17.9, 18.4, 18.9, 19.4)):
    blip(t, 1200 + i * 150, .45)
for t in (38.2, 39.5, 40.9):
    blip(t, 880, .6)
blip(78.15, 1568, .6); blip(78.3, 2093, .5)
for k in range(12):
    blip(76.8 + k * .05, 1500 + k * 60, .25)
for t in np.arange(69.0, 70.3, .09):
    tapfx(float(t), .25, 3200)

# ---------------- mix ----------------
# apply sidechain to everything but the drums is approximated by applying to all, softened
sc = .55 + .45 * side
L *= sc
R *= sc
fade_in = np.minimum(1, t_arr(N) / .5)
fade_out = np.clip((D - t_arr(N)) / 1.6, 0, 1)
L *= fade_in * fade_out
R *= fade_in * fade_out
mx = np.stack([L, R], 1)
mx = np.tanh(mx * 1.1)
mx /= np.max(np.abs(mx)) / .89
wavfile.write('music.wav', SR, (mx * 32767).astype(np.int16))
print('ok', mx.shape)
