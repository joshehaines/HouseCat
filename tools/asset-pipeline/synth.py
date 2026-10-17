"""Procedural sound set for HouseCat (v1, code-synthesised). python3 synth.py -> audio/*.wav + audio/manifest.json
UI and ambience are intended as shippable; the cat vocals (meows, chirp, trill, grumble) are placeholders until real
recordings or licensed CC0 clips replace them."""
import os, json
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(7)
os.makedirs('audio', exist_ok=True)
MAN = {}

def t_(d): return np.arange(int(SR * d)) / SR
def env_adsr(n, a=0.005, d=0.05, s=0.6, r=0.1):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    s_len = max(0, n - a - d - r)
    e = np.concatenate([np.linspace(0, 1, a, endpoint=False), np.linspace(1, s, d, endpoint=False),
                        np.full(s_len, s), np.linspace(s, 0, r)])
    return np.pad(e, (0, max(0, n - len(e))))[:n]
def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], 'band'); return signal.lfilter(b, a, x)
def lp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), 'low'); return signal.lfilter(b, a, x)
def hp(x, f, order=2):
    b, a = signal.butter(order, f / (SR / 2), 'high'); return signal.lfilter(b, a, x)
def reverb(x, size=0.25, mix=0.18):
    n = int(SR * size); ir = rng.standard_normal(n) * np.exp(-np.linspace(0, 6, n)); ir = lp(ir, 5000)
    wet = signal.fftconvolve(x, ir); wet = np.pad(wet, (0, max(0, len(x) + n - len(wet))))[:len(x) + n]
    wet /= (np.abs(wet).max() + 1e-9)
    dry = np.pad(x, (0, n)); return dry * (1 - mix) + wet * mix * np.abs(x).max()
def bell(f, d, partials=((1, 1), (2.76, .5), (5.4, .25), (8.9, .12)), decay=4.0):
    t = t_(d); y = sum(a * np.sin(2 * np.pi * f * p * t) * np.exp(-t * decay * p ** 0.5) for p, a in partials)
    fade = np.clip((d - t) / 0.03, 0, 1)
    return y * np.minimum(1, t / 0.002) * fade
def seq(parts):
    """parts: list of (start_s, array) -> mixed"""
    end = max(int(s * SR) + len(a) for s, a in parts); out = np.zeros(end)
    for s, a in parts: i = int(s * SR); out[i:i + len(a)] += a
    return out
def loopify(x, xf=0.5):
    """Seamless loop: the last xf seconds are cross-faded into the start, then dropped from the end."""
    n = int(xf * SR); w = np.linspace(0, 1, n)
    start = x[-n:] * (1 - w) + x[:n] * w
    return np.concatenate([start, x[n:-n]])
def save(name, x, kind, note, peak=0.8, loop=False):
    x = np.asarray(x, np.float64); x = x - np.mean(x)
    x = x / (np.abs(x).max() + 1e-9) * peak
    if not loop:
        f = min(len(x) // 4, int(0.01 * SR)); x[-f:] *= np.linspace(1, 0, f)
    wavfile.write(f'audio/{name}.wav', SR, (x * 32767).astype(np.int16))
    MAN[name] = {'kind': kind, 'seconds': round(len(x) / SR, 2), 'loop': loop, 'source': 'procedural (synth.py)', 'note': note}

# ---------- cat voice (formant synthesis; placeholders) ----------
def glottal(f0):
    ph = np.cumsum(f0 / SR); saw = 2 * (ph % 1) - 1
    jitter = 1 + 0.01 * rng.standard_normal(len(f0)); return saw * jitter
def formant_filter(src, F, bw=(90, 120, 160)):
    """F: array (n, 3) of formant frequencies over time; processed in 10 ms frames."""
    out = np.zeros_like(src); hop = int(0.01 * SR); zi = [None] * 3
    for i in range(0, len(src), hop):
        seg = src[i:i + hop]; k = min(i // hop, len(F) - 1); acc = np.zeros_like(seg)
        for j in range(3):
            f = F[k, j]; r = np.exp(-np.pi * bw[j] / SR); th = 2 * np.pi * f / SR
            b, a = [1 - r], [1, -2 * r * np.cos(th), r * r]
            if zi[j] is None: zi[j] = signal.lfilter_zi(b, a) * 0
            y, zi[j] = signal.lfilter(b, a, seg, zi=zi[j]); acc += y * (1.0, 0.7, 0.4)[j]
        out[i:i + hop] = acc
    return out
def meow(d=0.6, f_start=520, f_peak=820, f_end=480, peak_at=0.35, vowels=('m', 'i', 'a', 'u'), breath=0.04):
    n = int(d * SR); tt = np.linspace(0, 1, n)
    f0 = np.where(tt < peak_at, f_start + (f_peak - f_start) * np.sin(tt / peak_at * np.pi / 2),
                  f_peak + (f_end - f_peak) * ((tt - peak_at) / (1 - peak_at)) ** 1.3)
    f0 *= 1 + 0.015 * np.sin(2 * np.pi * 6 * tt * d)
    V = {'m': (350, 1200, 2600), 'i': (700, 2600, 3600), 'a': (1100, 1900, 3200), 'u': (600, 1100, 2800), 'r': (700, 1400, 2200)}
    frames = int(d / 0.01) + 1; keys = np.linspace(0, frames - 1, len(vowels))
    F = np.stack([np.interp(np.arange(frames), keys, [V[v][j] for v in vowels]) for j in range(3)], 1)
    y = formant_filter(glottal(f0), F) + breath * hp(rng.standard_normal(n), 2500)
    return y * env_adsr(n, 0.04, 0.1, 0.85, d * 0.35)

save('cat_meow_short', reverb(meow(0.45)), 'cat', 'placeholder: replace with a recorded meow')
save('cat_meow_long', reverb(meow(1.1, 480, 760, 420, 0.3, ('m', 'i', 'a', 'a', 'u'))), 'cat', 'placeholder')
save('cat_meow_question', reverb(meow(0.6, 460, 600, 900, 0.5, ('m', 'a', 'i'))), 'cat', 'placeholder: rising end')
ch = meow(0.12, 900, 1300, 1100, 0.4, ('m', 'i')); save('cat_chirp', reverb(seq([(0, ch), (0.16, ch * 0.8)])), 'cat', 'placeholder')
tr_n = int(0.5 * SR); trill = meow(0.5, 600, 700, 650, 0.5, ('m', 'r', 'r', 'u')) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t_(0.5)))[:tr_n]
save('cat_trill', reverb(trill), 'cat', 'placeholder: rolled r')
gr = meow(0.9, 180, 210, 170, 0.5, ('m', 'u', 'r', 'u')) * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 22 * t_(0.9))))[:int(0.9 * SR)]
save('cat_grumble', reverb(lp(gr, 1800)), 'cat', 'placeholder: low growl-grumble')

# purr: ~26 Hz pulses of low noise, inhale/exhale alternating, loopable
def purr(d=6.0):
    t = t_(d); rate = 26 + 1.5 * np.sin(2 * np.pi * 0.11 * t)
    ph = np.cumsum(rate / SR); pulse = np.clip(np.sin(2 * np.pi * ph), 0, None) ** 3
    noise = lp(rng.standard_normal(len(t)), 420); tone = np.sin(2 * np.pi * np.cumsum(rate * 2) / SR) * 0.3
    breath = 0.65 + 0.35 * np.sin(2 * np.pi * t / 2.0)                   # 2 s breath cycle
    return lp((noise + tone) * pulse * breath, 900)
save('cat_purr_loop', loopify(purr(6.5)), 'cat', 'procedural purr, seamless loop', loop=True)
def breathing(d=8.0):
    t = t_(d); cyc = (t % 4.0) / 4.0
    amp = np.where(cyc < 0.4, np.sin(np.pi * cyc / 0.4), np.where(cyc < 0.85, np.sin(np.pi * (cyc - 0.4) / 0.45) * 0.7, 0))
    return bp(rng.standard_normal(len(t)), 250, 1600) * amp ** 1.5
save('cat_sleep_breathing', loopify(breathing(8.5)), 'cat', 'procedural, seamless loop', peak=0.5, loop=True)
def thump(f=70, d=0.18):
    t = t_(d); return (np.sin(2 * np.pi * f * t * (1 - 0.4 * t / d)) * np.exp(-t * 28) + 0.3 * lp(rng.standard_normal(len(t)), 600) * np.exp(-t * 60))
z = seq([(0.0, thump()), (0.11, thump(64) * .8), (0.2, thump(75) * .9), (0.29, thump(60) * .7), (0.52, thump(68)), (0.61, thump(72) * .8), (0.7, thump(58) * .9), (0.79, thump(66) * .6)])
save('cat_zoomies_thumps', z, 'cat', 'procedural paw thumps')

# ---------- world ----------
def creak(d=0.9, f0=180):
    t = t_(d); f = f0 + 60 * np.sin(2 * np.pi * 0.7 * t) + 25 * rng.standard_normal(len(t)).cumsum() / SR * 40
    pulses = (np.sin(2 * np.pi * np.cumsum(f) / SR) > 0.95).astype(float)
    return bp(pulses + 0.05 * rng.standard_normal(len(t)), 300, 3000) * env_adsr(len(t), 0.05, 0.2, 0.7, 0.3)
latch = lambda: bp(rng.standard_normal(int(0.04 * SR)), 1500, 6000) * np.exp(-t_(0.04) * 120)
save('door_open', reverb(seq([(0, latch()), (0.08, creak())]), 0.4), 'world', 'latch click + hinge creak')
save('door_close', reverb(seq([(0, creak(0.4, 220) * 0.6), (0.38, thump(90, 0.3) * 1.2), (0.4, latch())]), 0.4), 'world', 'swing + thud + latch')
def rain(d=10):
    n = int(d * SR); base = bp(rng.standard_normal(n), 400, 9000) * 0.25
    drops = np.zeros(n); idx = rng.integers(0, n - 2000, int(d * 220))
    for i in idx:
        L = rng.integers(200, 900); drops[i:i + L] += rng.uniform(.2, 1) * np.sin(2 * np.pi * rng.uniform(1500, 5000) * np.arange(L) / SR) * np.exp(-np.arange(L) / (L / 5))
    return base + 0.5 * drops
save('rain_loop', loopify(rain(10.5)), 'world', 'steady rain on glass, seamless loop', loop=True)
def wind(d=12):
    n = int(d * SR); t = t_(d); g = 0.55 + 0.45 * np.sin(2 * np.pi * 0.08 * t) * np.sin(2 * np.pi * 0.031 * t + 1)
    x = rng.standard_normal(n); out = np.zeros(n); hop = 2048
    for i in range(0, n, hop):
        fc = 300 + 500 * g[i]; seg = x[max(0, i - 4096):i + hop]; y = bp(seg, fc * 0.6, fc * 1.6)
        out[i:i + hop] = y[-len(out[i:i + hop]):]
    return out * g
save('wind_loop', loopify(wind(12.5), 1.0), 'world', 'gusting wind, seamless loop', loop=True)
def fire(d=10):
    n = int(d * SR); base = lp(rng.standard_normal(n), 600) * 0.6
    cr = np.zeros(n); idx = rng.integers(0, n - 500, int(d * 35))
    for i in idx:
        L = rng.integers(40, 400); cr[i:i + L] += rng.uniform(.3, 1.4) * hp(rng.standard_normal(L), 2000) * np.exp(-np.arange(L) / (L / 4))
    return base + cr
save('fire_crackle_loop', loopify(fire(10.5)), 'world', 'hearth crackle, seamless loop', loop=True)
def bird_call(f0, d=0.25):
    t = t_(d); f = f0 * (1 + 0.35 * np.sin(2 * np.pi * rng.uniform(6, 14) * t)) * (1 + 0.2 * t / d)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / d) ** 2
birds = np.zeros(int(12 * SR))
for _ in range(38):
    s = rng.uniform(0, 11.4); c = bird_call(rng.uniform(2500, 5200), rng.uniform(.08, .35)) * rng.uniform(.2, .9)
    i = int(s * SR); birds[i:i + len(c)] += c
save('dawn_birds_loop', loopify(reverb(birds, 0.6, 0.3)[:len(birds)] + 0.03 * lp(rng.standard_normal(len(birds)), 800), 0.8), 'world', 'dawn chorus, seamless loop', peak=0.6, loop=True)
cr = np.zeros(int(10 * SR))
for k in range(3):
    f = 4200 + 600 * k; per = 0.62 + 0.15 * k; s = rng.uniform(0, per)
    while s < 9.8:
        c = np.sin(2 * np.pi * f * t_(0.12)) * (np.sin(2 * np.pi * 45 * t_(0.12)) > 0) * np.sin(np.pi * t_(0.12) / 0.12)
        i = int(s * SR); cr[i:i + len(c)] += c * (0.5 + 0.2 * k); s += per * rng.uniform(.9, 1.1)
save('night_crickets_loop', loopify(cr + 0.02 * lp(rng.standard_normal(len(cr)), 500)), 'world', 'crickets, seamless loop', peak=0.5, loop=True)
save('snow_hush_loop', loopify(lp(rng.standard_normal(int(10.5 * SR)), 900) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.1 * t_(10.5)))), 'world', 'soft muffled air, seamless loop', peak=0.35, loop=True)

# ---------- UI ----------
C5, E5, G5, C6, E6, G6, A5, D6 = 523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0, 880.0, 1174.7
save('ui_tap', bp(rng.standard_normal(int(0.03 * SR)), 2000, 7000) * np.exp(-t_(0.03) * 160) + 0.4 * np.sin(2 * np.pi * 1800 * t_(0.03)) * np.exp(-t_(0.03) * 120), 'ui', 'soft tick', peak=0.6)
save('ui_place_item', reverb(seq([(0, thump(110, 0.2)), (0.01, bp(rng.standard_normal(int(0.08 * SR)), 300, 2500) * np.exp(-t_(0.08) * 50) * .5)]), 0.2, .12), 'ui', 'wooden set-down thunk')
save('ui_bean_chime', reverb(seq([(0, bell(G6, .5) * .7), (0.06, bell(C6 * 2, .6) * .5)]), .4), 'ui', 'two-note coin chime')
for i, (nm, notes) in enumerate([('common', [C5, E5]), ('uncommon', [C5, E5, G5]), ('rare', [C5, E5, G5, C6]), ('legendary', [C5, E5, G5, C6, E6, G6])]):
    pop = bp(rng.standard_normal(int(.08 * SR)), 500, 4000) * np.exp(-t_(.08) * 40)
    parts = [(0, pop)] + [(0.12 + k * 0.07, bell(f, 1.0 + 0.2 * i) * (0.6 + 0.08 * k)) for k, f in enumerate(notes)]
    if nm == 'legendary':
        parts.append((0.6, sum(bell(f, 1.8, decay=2) for f in (C6, E6, G6)) * 0.4))
    save(f'ui_gift_open_{nm}', reverb(seq(parts), .6, .25), 'ui', f'gift reveal, {nm}')
save('ui_level_up', reverb(seq([(k * 0.09, bell(f, 1.2) * .7) for k, f in enumerate([C5, E5, G5, C6, E6])] + [(0.5, sum(bell(f, 1.6, decay=2) for f in (C6, E6, G6)) * .5)]), .7, .3), 'ui', 'rising arpeggio + chord')
save('ui_streak_milestone', reverb(seq([(0, bell(G5, 1)), (0.12, bell(C6, 1)), (0.24, bell(E6, 1.4)), (0.24, bell(G5 * 2, 1.4) * .5)]), .6, .3), 'ui', 'bright three-note fanfare')
save('ui_pass_tier', reverb(seq([(0, bell(E5, .8)), (0.1, bell(A5, 1.0)), (0.2, bell(D6 * 0.75 * 2, 1.2) * .6)]), .5, .25), 'ui', 'tier-up ping')
save('ui_purchase_confirm', reverb(seq([(0, bell(C6, .6) * .8), (0.08, bell(G6, .9) * .7), (0.0, thump(160, .15) * .4)]), .4, .2), 'ui', 'register-style confirm')

json.dump(MAN, open('audio/manifest.json', 'w'), indent=1)
print(len(MAN), 'sounds')
