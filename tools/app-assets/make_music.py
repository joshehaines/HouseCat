#!/usr/bin/env python3
"""HouseCat's background music, composed and synthesised from scratch (no samples, no third-party audio, so nothing
to license). Josh, 19 Oct: "quiet cute background music".

Each track is a seamless loop: notes that ring past the end are folded onto the start and the reverb is circular,
so the last sample runs straight into the first. Writes stereo 44.1 kHz 16-bit WAV masters, all at the same
A-weighted loudness; tools/app-assets/build_app_audio.sh turns them into App/Audio's AAC. Deterministic: the same
script writes the same files.

Needs numpy and scipy (a throwaway venv will do: python3 -m venv /tmp/v && /tmp/v/bin/pip install numpy scipy).
Run from the repo root: /tmp/v/bin/python tools/app-assets/make_music.py assets/audio music_windowsill music_lullaby
(no names: all the candidates Josh heard, the kalimba and the moon harp too).
"""
import sys
import os
import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt, bilinear_zpk, zpk2sos
from scipy.io import wavfile

SR = 44100
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """'C4' -> 60, 'Bb3' -> 58, 'F#5' -> 78."""
    letter, rest = name[0], name[1:]
    n = NOTE_NAMES[letter]
    while rest and rest[0] in "#b":
        n += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return n + 12 * (int(rest) + 1)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def seq(text, start=0.0, vel=0.6):
    """'C5/1 R/.5 E5+G5/2 | ...' -> [(beat, beats, [midi], vel)]. Bars ('|') are only for reading."""
    out, beat = [], start
    for tok in text.replace("|", " ").split():
        v = vel
        if "!" in tok:
            tok, accent = tok.split("!")
            v = float(accent)
        pitch, dur = tok.split("/")
        dur = float(dur)
        if pitch != "R":
            out.append((beat, dur, [midi(p) for p in pitch.split("+")], v))
        beat += dur
    return out, beat


# ---------------------------------------------------------------------------------------------------------------
# Instruments: each returns a mono note (numpy array) for frequency f, held for `held` seconds, at velocity v (0-1).

def _t(seconds):
    return np.arange(int(seconds * SR)) / SR


def _attack(t, seconds):
    return np.clip(t / seconds, 0, 1) ** 0.5 if seconds > 0 else np.ones_like(t)


def _release(t, held, seconds):
    env = np.ones_like(t)
    after = t > held
    env[after] = np.exp(-(t[after] - held) / seconds)
    return env


def _fade_end(x, seconds=0.06):
    k = min(len(x), int(seconds * SR))
    x[len(x) - k:] *= np.linspace(1, 0, k)
    return x


def _noise_burst(n, lo, hi, decay, rng):
    noise = rng.standard_normal(n)
    sos = butter(2, [lo, min(hi, SR / 2 - 100)], btype="band", fs=SR, output="sos")
    burst = sosfilt(sos, noise)
    return burst * np.exp(-np.arange(n) / SR / decay)


def felt_piano(f, held, v, rng):
    """A soft, felted upright: inharmonic partials, two strings beating gently, a dark hammer and a short damper."""
    length = held + 1.6
    t = _t(length)
    out = np.zeros_like(t)
    B = 0.00032
    darkness = 0.55 - 0.3 * v                      # softer playing, darker tone
    sustain = 3.2 * (262 / f) ** 0.45
    for n in range(1, 18):
        fn = n * f * np.sqrt(1 + B * n * n)
        if fn > 9000:
            break
        amp = (1 / n ** 1.15) * np.exp(-(n - 1) * darkness)
        slow = sustain / n ** 0.75
        fast = 0.35 / n ** 0.4
        env = 0.45 * np.exp(-t / fast) + 0.55 * np.exp(-t / slow)
        beat = 0.06 * n * (1 + 0.3 * rng.random())
        phase = rng.random() * 2 * np.pi
        out += amp * env * (np.sin(2 * np.pi * (fn - beat) * t + phase) + np.sin(2 * np.pi * (fn + beat) * t + phase))
    out *= _attack(t, 0.004) * _release(t, held, 0.28)
    thump = np.zeros_like(t)
    k = int(0.06 * SR)
    thump[:k] = _noise_burst(k, 60, 900 + 1.5 * f, 0.012, rng)
    out = out * 0.5 + thump * 0.25
    return out * (0.35 + 0.65 * v)


def music_box(f, held, v, rng):
    """A comb tine: a clear fundamental, the tine's own high modes dying fast, a little shimmer and a pluck."""
    f = f * 2 ** (rng.uniform(-3, 3) / 1200)           # music boxes are never quite in tune
    tau = 2.0 * (523 / f) ** 0.55
    t = _t(min(4.5 * tau, 7.0))
    out = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    out += 0.28 * np.sin(2 * np.pi * f * 1.0016 * t + 1.3) * np.exp(-t / (tau * 0.8))   # shimmer
    out += 0.10 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / (tau * 0.35))
    for ratio, amp, dec in ((6.267, 0.22, 0.10), (17.55, 0.06, 0.025)):
        if f * ratio < 16000:
            out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / dec)
    out *= _attack(t, 0.0015)
    k = int(0.01 * SR)
    out[:k] += _noise_burst(k, 3000, 12000, 0.0015, rng) * 0.25
    return out * (0.3 + 0.7 * v)


def glock(f, held, v, rng):
    """A soft celesta-like bell for sprinkles: bar modes, quick to fade."""
    t = _t(2.2)
    tau = 1.1 * (1047 / f) ** 0.5
    out = np.zeros_like(t)
    for ratio, amp, dec in ((1, 1, tau), (2.756, 0.25, tau * 0.3), (5.404, 0.08, tau * 0.12)):
        if f * ratio < 16000:
            out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / dec)
    return out * _attack(t, 0.002) * (0.3 + 0.7 * v)


def kalimba(f, held, v, rng):
    """A thumb piano: a round tine, its overtone near the sixth harmonic, a thumb's soft pluck and a bend."""
    tau = 1.3 * (440 / f) ** 0.5
    t = _t(min(4.5 * tau, 5.0))
    bend = 1 - 0.006 * np.exp(-t / 0.03)            # the tine settles a few cents down after the thumb
    phase = 2 * np.pi * np.cumsum(f * bend) / SR
    out = np.sin(phase) * np.exp(-t / tau)
    out += 0.07 * np.sin(2 * phase) * np.exp(-t / (tau * 0.4))
    if f * 5.93 < 16000:
        out += 0.22 * np.sin(5.93 * phase) * np.exp(-t / 0.07)
    out *= _attack(t, 0.002)
    k = int(0.02 * SR)
    out[:k] += _noise_burst(k, 200, 2500, 0.004, rng) * 0.35
    return out * (0.3 + 0.7 * v)


def harp(f, held, v, rng):
    """A nylon harp string: harmonics shaped by where it was plucked, the top ones fading first."""
    base = 3.0 * (262 / f) ** 0.4
    t = _t(min(4 * base, 7.0))
    out = np.zeros_like(t)
    p = 0.18
    for n in range(1, 24):
        if n * f > 8000:
            break
        amp = abs(np.sin(np.pi * n * p)) / n ** 1.4
        dec = base / (1 + 0.22 * (n - 1) ** 1.3)
        out += amp * np.sin(2 * np.pi * n * f * t + rng.random() * 6.28) * np.exp(-t / dec)
    out *= _attack(t, 0.003)
    return out * (0.3 + 0.7 * v)


def round_bass(f, held, v, rng):
    """A soft plucked bass: mostly fundamental, a touch of second, gently damped when let go."""
    length = held + 0.6
    t = _t(length)
    out = np.sin(2 * np.pi * f * t) * np.exp(-t / 1.6)
    out += 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / 0.5)
    out += 0.12 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t / 0.2)
    out *= _attack(t, 0.012) * _release(t, held, 0.15)
    return out * (0.3 + 0.7 * v)


def warm_pad(f, held, v, rng):
    """Strings heard through a wall: detuned soft saws, a slow swell and a slow fade."""
    length = held + 2.5
    t = _t(length)
    out = np.zeros_like(t)
    for detune in (-5, 0, 5):
        fd = f * 2 ** (detune / 1200)
        ph = rng.random() * 6.28
        for n in range(1, 9):
            if n * fd > 5000:
                break
            out += (1 / n) * np.exp(-n / 2.2) * np.sin(2 * np.pi * n * fd * t + ph * n)
    swell = np.clip(t / 1.6, 0, 1) ** 2
    out *= swell * _release(t, held, 1.1) * (1 + 0.08 * np.sin(2 * np.pi * 0.23 * t))
    return out * 0.25 * (0.3 + 0.7 * v)


def ocarina(f, held, v, rng):
    """A clay ocarina: nearly a pure tone, a breath around it, vibrato arriving late."""
    length = held + 0.5
    t = _t(length)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 4.8 * t) * np.clip((t - 0.35) / 0.6, 0, 1)
    phase = 2 * np.pi * np.cumsum(f * vib) / SR
    tone = np.sin(phase) + 0.08 * np.sin(2 * phase) + 0.03 * np.sin(3 * phase)
    breath = _noise_burst(len(t), f * 0.8, f * 3, 1e9, rng) * 0.04
    env = np.clip(t / 0.09, 0, 1) * _release(t, held, 0.18) * (1 - 0.15 * np.clip(t / max(held, 0.1), 0, 1))
    return (tone + breath) * env * (0.3 + 0.7 * v)


def shaker(f, held, v, rng):
    """A brush on a shaker, very far back."""
    n = int(0.08 * SR)
    return _noise_burst(n, 5000, 11000, 0.018, rng) * v


INSTRUMENTS = dict(piano=felt_piano, musicbox=music_box, glock=glock, kalimba=kalimba, harp=harp,
                   bass=round_bass, pad=warm_pad, ocarina=ocarina, shaker=shaker)


# ---------------------------------------------------------------------------------------------------------------
# The room the music is played in.

def impulse_response(seconds, rt60, brightness, seed):
    """Stereo reverb: decorrelated noise tails per band (the top fading first) and a few early reflections."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    bands = ((40, 500, 1.0), (500, 2500, 0.85), (2500, 6000, 0.55 * brightness), (6000, 14000, 0.3 * brightness))
    for lo, hi, scale in bands:
        sos = butter(2, [lo, hi], btype="band", fs=SR, output="sos")
        decay = np.exp(-6.9 * t / (rt60 * scale))
        for ch in range(2):
            ir[:, ch] += sosfilt(sos, rng.standard_normal(n)) * decay * (0.6 if lo >= 2500 else 1.0)
    ir[: int(0.012 * SR)] = 0                         # pre-delay
    for ms, gain in ((17, 0.5), (23, 0.4), (31, 0.35), (43, 0.25), (57, 0.2)):
        i = int(ms / 1000 * SR)
        ir[i, rng.integers(0, 2)] += gain * 3
    ir /= np.sqrt((ir ** 2).sum(axis=0, keepdims=True))
    return ir


def a_weighted_db(x):
    """Loudness as an ear hears quiet music (A-weighting), in dB of full scale."""
    f1, f2, f3, f4 = 20.598997, 107.65265, 737.86223, 12194.217
    z = [0, 0, 0, 0]
    p = [-2 * np.pi * f1] * 2 + [-2 * np.pi * f2, -2 * np.pi * f3] + [-2 * np.pi * f4] * 2
    k = (2 * np.pi * f4) ** 2 * 10 ** (1.9997 / 20)
    zd, pd, kd = bilinear_zpk(z, p, k, SR)
    sos = zpk2sos(zd, pd, kd)
    y = sosfilt(sos, x.mean(axis=1) if x.ndim == 2 else x)
    return 10 * np.log10((y ** 2).mean() + 1e-20)


def circular_filter(x, fn):
    """Applies fn to a looping signal without a seam: runs it over three copies and keeps the middle one."""
    n = len(x)
    y = fn(np.concatenate([x, x, x]))
    return y[n:2 * n]


# ---------------------------------------------------------------------------------------------------------------
class Track:
    def __init__(self, bpm, beats, seed=1):
        self.bpm = bpm
        self.length = int(round(beats * 60 / bpm * SR))
        self.buf = np.zeros((self.length + 10 * SR, 2))
        self.rng = np.random.default_rng(seed)

    def sec(self, beat):
        return beat * 60 / self.bpm

    def add(self, inst, events, gain=1.0, pan=0.0, transpose=0, humanise=0.008, spread=0.0):
        """Places notes. pan -1..1; spread pans each note a little by pitch so chords open out."""
        fn = INSTRUMENTS[inst]
        fade = lambda x: _fade_end(x)
        for beat, dur, notes, vel in events:
            for i, m in enumerate(notes):
                m = m + transpose
                held = self.sec(dur)
                note = fade(fn(hz(m), held, vel, self.rng) * gain)
                start = int(round((self.sec(beat) + self.rng.uniform(0, humanise)) * SR))
                p = np.clip(pan + spread * (m - 66) / 18, -1, 1)
                left, right = np.cos((p + 1) * np.pi / 4), np.sin((p + 1) * np.pi / 4)
                end = min(start + len(note), len(self.buf))
                self.buf[start:end, 0] += note[: end - start] * left
                self.buf[start:end, 1] += note[: end - start] * right

    def finish(self, reverb=0.3, rt60=2.2, brightness=1.0, lowpass=9000, wobble=0.0, target_dba=-26.0):
        n = self.length
        dry = self.buf[:n].copy()
        tail = self.buf[n:]
        k = min(len(tail), n)
        dry[:k] += tail[:k]
        ir = impulse_response(min(rt60 * 1.6, 5.0), rt60, brightness, seed=7)
        wet = np.zeros_like(dry)
        for ch in range(2):
            twice = np.concatenate([dry[:, ch], dry[:, ch]])
            wet[:, ch] = fftconvolve(twice, ir[:, ch])[n:2 * n]
        mix = dry + reverb * wet
        if wobble > 0:                                     # tape wow: a slow, looping drift in pitch
            idx = np.arange(n)
            cycles = max(1, round(n / SR / 2.1))
            delay = wobble * SR * (1 + np.sin(2 * np.pi * cycles * idx / n))
            pos = (idx - delay) % n
            for ch in range(2):
                ext = np.concatenate([mix[:, ch], mix[:1, ch]])
                mix[:, ch] = np.interp(pos, np.arange(n + 1), ext)
        sos_lp = butter(2, lowpass, btype="low", fs=SR, output="sos")
        sos_hp = butter(2, 45, btype="high", fs=SR, output="sos")
        for ch in range(2):
            mix[:, ch] = circular_filter(mix[:, ch], lambda s: sosfilt(sos_hp, sosfilt(sos_lp, s)))
        mix *= 10 ** ((target_dba - a_weighted_db(mix)) / 20)
        peak = np.abs(mix).max()
        if peak > 0.89:                                    # gentle soft clip only on the odd peak
            mix = np.tanh(mix / 0.89) * 0.89
        return mix


# ---------------------------------------------------------------------------------------------------------------
# The tracks.

def chords_pattern(chords, pattern, beats_per_bar, vel=0.4):
    """chords: list of per-bar chord lists like [['F2','C3','A3','E4'], ...] (a bar may hold two: (beats, notes)).
    pattern: list of (beat, beats, index into the chord) for one bar's broken chord."""
    events = []
    for bar, chord in enumerate(chords):
        parts = chord if isinstance(chord[0], tuple) else [(beats_per_bar, chord)]
        at = 0.0
        for length, notes in parts:
            if at > 0 and not any(beat == at and idx == 0 for beat, _, idx, _ in pattern):
                events.append((bar * beats_per_bar + at, length, [midi(notes[0])], 0.45 * vel / 0.4))
            for beat, dur, idx, v in pattern:
                if at <= beat < at + length:
                    events.append((bar * beats_per_bar + beat, dur, [midi(notes[idx % len(notes)])], v * vel / 0.4))
            at += length
    return events


def windowsill():
    """Day: a felt piano by the window, F major, 74 bpm, 24 bars. Celesta sprinkles on the way round again."""
    bpm, bars = 74, 24
    T = Track(bpm, bars * 4, seed=11)
    Fmaj7 = ["F2", "C3", "A3", "E4", "C4"]
    Am7 = ["A2", "E3", "C4", "G4", "E4"]
    Bbmaj7 = ["Bb2", "F3", "D4", "A4", "F4"]
    C = ["C3", "G3", "E4", "C5", "G4"]
    Csus = ["C3", "G3", "F4", "C5", "G4"]
    Dm7 = ["D3", "A3", "F4", "C5", "A4"]
    Gm7 = ["G2", "D3", "Bb3", "F4", "D4"]
    FA = ["A2", "F3", "C4", "A4", "F4"]
    chart = [Fmaj7, Am7, Bbmaj7, [(2, Csus), (2, C)], Fmaj7, Am7, Bbmaj7, [(2, Gm7), (2, C)],
             Dm7, Am7, Bbmaj7, FA, Gm7, Am7, Bbmaj7, [(2, Csus), (2, C)],
             Fmaj7, Am7, Bbmaj7, [(2, Csus), (2, C)], Dm7, Bbmaj7, Gm7, [(2, Csus), (2, C)]]
    # root, fifth, tenth, then the colour note and back: a slow rocking under the tune
    lh = [(0, 2.5, 0, 0.5), (0.5, 1.5, 1, 0.34), (1, 1, 2, 0.3), (2, 2, 1, 0.38), (2.5, 1.5, 3, 0.3), (3, 1, 4, 0.28)]
    T.add("piano", chords_pattern(chart, lh, 4, vel=0.4), gain=0.55, spread=0.5, humanise=0.012)
    tune = """
      R/.5 C5/.5 A4/.5 C5/.5 F5/1.5 E5/.5 | E5/1 C5/1 A4/2 | R/.5 D5/.5 C5/.5 D5/.5 F5/1.5 E5/.5 | D5/.5 E5/.5 F5/1 E5/2 |
      R/.5 C5/.5 A4/.5 C5/.5 F5/1.5 G5/.5 | A5/1 G5/.5 E5/.5 C5/2 | D5/1 F5/1 A5/1 G5/.5 F5/.5 | G5/1.5 F5/.5 E5/2 |
      A4/1.5 C5/.5 D5/1 F5/1 | E5/2 R/.5 C5/.5 D5/.5 E5/.5 | F5/1.5 D5/.5 Bb4/1 A4/1 | C5/3 R/1 |
      Bb4/.5 C5/.5 D5/1 F5/1.5 D5/.5 | E5/1.5 C5/.5 A4/2 | D5/1 C5/1 Bb4/1 A4/1 | G4/1.5 A4/.5 Bb4/1 C5/1 |
      R/.5 C5/.5 A4/.5 C5/.5 F5/1.5 E5/.5 | E5/1 C5/1 A4/2 | R/.5 D5/.5 C5/.5 D5/.5 F5/1.5 E5/.5 | D5/.5 E5/.5 F5/1 E5/2 |
      R/.5 A4/.5 D5/.5 F5/.5 A5/1.5 G5/.5 | F5/1 D5/1 F5/2 | D5/1 Bb4/1 G4/1 A4/.5 Bb4/.5 | C5/1.5 D5/.5 E5/2 |
    """
    melody, end = seq(tune, vel=0.62)
    assert abs(end - bars * 4) < 1e-6, end
    T.add("piano", melody, gain=0.8, pan=0.08, humanise=0.01)
    sprinkle, _ = seq("""R/64 R/2 C6/.5 A5/.5 F6/1 | R/4 | R/2 D6/.5 F6/.5 A6/1 | R/4 | R/2 C6/1 F6/1 | R/4 | R/3 F6/.5 D6/.5 | R/4""",
                      vel=0.35)
    T.add("glock", sprinkle, gain=0.22, pan=0.35)
    return T.finish(reverb=0.32, rt60=2.3, brightness=0.8, lowpass=8000)


def lullaby():
    """Night: a music box waltz with a hush of strings under it, Bb major, 66 bpm, 32 bars of 3/4."""
    bpm, bars, tr = 66, 32, -2
    T = Track(bpm, bars * 3, seed=23)
    C = ["C4", "E4", "G4"]
    Am = ["A3", "C4", "E4"]
    F = ["F3", "A3", "C4"]
    G = ["G3", "B3", "D4"]
    Em = ["E3", "G3", "B3"]
    Dm = ["D3", "F3", "A3"]
    chart = [C, Am, F, G, C, Am, Dm, G,
             C, Em, F, C, F, C, G, C,
             Am, Em, F, C, Dm, Am, F, G,
             C, Am, F, G, Em, Am, Dm, G]
    # the low tine on one, then two higher on two and three
    acc = [(0, 3, 0, 0.5), (1, 1, 1, 0.3), (1, 1, 2, 0.26), (2, 1, 1, 0.26), (2, 1, 2, 0.22)]
    T.add("musicbox", chords_pattern(chart, acc, 3, vel=0.4), gain=0.45, transpose=tr, spread=0.4, humanise=0.006)
    tune = """
      G5/2 E5/1 | E5/1 D5/1 C5/1 | C5/1 F5/1 A5/1 | G5/3 |
      G5/2 E5/1 | E5/1 D5/1 C5/1 | F5/1.5 E5/.5 D5/1 | D5/3 |
      E5/1 G5/1 C6/1 | B5/2 G5/1 | A5/1.5 G5/.5 F5/1 | E5/3 |
      F5/1 A5/1 C6/1 | G5/2 E5/1 | D5/1 E5/.5 D5/.5 B4/1 | C5/3 |
      C5/1 E5/1 A5/1 | G5/2 B4/1 | A5/1.5 G5/.5 F5/1 | E5/3 |
      D5/1 F5/1 A5/1 | G5/1 E5/1 C5/1 | A5/1 G5/1 F5/1 | D5/1 E5/1 F5/1 |
      E5/2 G5/1 | A5/1 G5/1 E5/1 | F5/1 A5/1 C6/1 | B5/1.5 A5/.5 G5/1 |
      G5/2 E5/1 | C5/1.5 B4/.5 A4/1 | D5/1 F5/1 A5/1 | G5/1 F5/1 D5/1 |
    """
    melody, end = seq(tune, vel=0.6)
    assert abs(end - bars * 3) < 1e-6, end
    T.add("musicbox", melody, gain=0.7, pan=0.05, transpose=tr)
    pad = [(i * 3, 3, [midi(n) for n in (ch[0], ch[2])], 0.5) for i, ch in enumerate(chart)]
    T.add("pad", pad, gain=0.3, transpose=tr - 12, spread=0.3)
    return T.finish(reverb=0.42, rt60=2.8, brightness=0.7, lowpass=7500)


def kalimba_afternoon():
    """Day, lo-fi: kalimba over a round bass, a shaker far off, the tape drifting a little. C major, 80 bpm."""
    bpm, bars = 80, 24
    T = Track(bpm, bars * 4, seed=37)
    Cmaj7 = ["C3", "E4", "G4", "B4", "E5"]
    Em7 = ["E3", "D4", "G4", "B4", "E5"]
    Fmaj7 = ["F3", "E4", "A4", "C5", "F5"]
    G6 = ["G3", "D4", "E4", "B4", "D5"]
    Am7 = ["A3", "E4", "G4", "C5", "E5"]
    Dm7 = ["D3", "F4", "A4", "C5", "D5"]
    chart = [Cmaj7, Em7, Fmaj7, G6, Cmaj7, Em7, Fmaj7, G6,
             Am7, Em7, Fmaj7, Cmaj7, Dm7, Em7, Fmaj7, G6,
             Cmaj7, Em7, Fmaj7, G6, Am7, Em7, Dm7, G6]
    # a lazy ostinato, plucked by two thumbs: never every eighth
    arp = [(0, 1, 1, 0.42), (0.75, 1, 2, 0.3), (1.5, 1, 3, 0.34), (2.5, 1, 4, 0.3), (3, 1, 2, 0.28), (3.5, 1, 3, 0.25)]
    T.add("kalimba", chords_pattern(chart, arp, 4, vel=0.4), gain=0.5, spread=0.6, humanise=0.015)
    bass = [(i * 4, 1.5, [midi(ch[0]) - 12], 0.55) for i, ch in enumerate(chart)]
    bass += [(i * 4 + 2.5, 1, [midi(ch[0]) - 12 + (7 if i % 2 else 12)], 0.4) for i, ch in enumerate(chart)]
    T.add("bass", bass, gain=0.55)
    tune = """
      R/4 | R/4 | R/4 | R/4 |
      E5/.75 G5/.75 A5/.5 G5/2 | R/.5 B5/.5 A5/.5 G5/.5 E5/2 | R/.5 C6/.75 A5/.75 G5/2 | R/.5 E5/.5 G5/.5 D5/1.5 R/1 |
      C6/.75 B5/.75 A5/.5 E5/2 | R/.5 G5/.5 B5/.5 G5/.5 E5/2 | R/.5 A5/.5 C6/.5 E6/1 D6/1.5 | B5/.75 G5/.75 E5/2.5 |
      F5/.75 A5/.75 C6/.5 A5/2 | R/.5 G5/.5 B5/.5 D6/.5 B5/2 | R/.5 A5/.75 G5/.75 F5/2 | R/.5 E5/.5 D5/.5 E5/1.5 R/1 |
      E5/.75 G5/.75 A5/.5 G5/2 | R/.5 B5/.5 A5/.5 G5/.5 E5/2 | R/.5 C6/.75 A5/.75 G5/2 | R/.5 E5/.5 G5/.5 D5/1.5 R/1 |
      C6/.75 B5/.75 A5/.5 E5/2 | R/.5 G5/.5 B5/.5 G5/.5 E5/2 | R/.5 F5/.5 A5/.5 C6/1 A5/1.5 | B5/.75 D6/.75 G5/2.5 |
    """
    melody, end = seq(tune, vel=0.7)
    assert abs(end - bars * 4) < 1e-6, end
    T.add("kalimba", melody, gain=0.75, pan=-0.1, transpose=0)
    shakes = []
    for b in range(bars * 2):
        shakes.append((b * 2 + 0.5, 0.25, [60], 0.35))
        shakes.append((b * 2 + 1.5, 0.25, [60], 0.5))
        shakes.append((b * 2 + 1.75, 0.25, [60], 0.2))
    T.add("shaker", shakes, gain=0.08, pan=0.4, humanise=0.02)
    return T.finish(reverb=0.25, rt60=1.8, brightness=0.6, lowpass=6000, wobble=0.0012)


def moon_harp():
    """Night: a harp rolling slow chords, an ocarina on top, strings under. Eb major, 60 bpm, 16 bars."""
    bpm, bars, tr = 60, 16, 3
    T = Track(bpm, bars * 4, seed=53)
    Cmaj7 = ["C3", "G3", "B3", "E4", "G4"]
    Am7 = ["A2", "E3", "G3", "C4", "E4"]
    Fmaj7 = ["F2", "C3", "A3", "E4", "A4"]
    Gsus = ["G2", "D3", "C4", "F4", "G4"]
    G = ["G2", "D3", "B3", "D4", "G4"]
    Em7 = ["E3", "B3", "D4", "G4", "B4"]
    CE = ["E3", "C4", "G4", "B4", "E5"]
    Dm7 = ["D3", "A3", "C4", "F4", "A4"]
    chart = [Cmaj7, Am7, Fmaj7, [(2, Gsus), (2, G)], Cmaj7, Em7, Fmaj7, [(2, Gsus), (2, G)],
             Am7, Em7, Fmaj7, CE, Dm7, Em7, Fmaj7, [(2, Gsus), (2, G)]]
    roll = [(0.0, 3, 0, 0.5), (0.12, 3, 1, 0.38), (0.24, 3, 2, 0.36), (0.36, 3, 3, 0.36), (0.48, 3, 4, 0.33),
            (2.0, 2, 2, 0.3), (2.12, 2, 3, 0.28), (2.24, 2, 4, 0.26)]
    T.add("harp", chords_pattern(chart, roll, 4, vel=0.4), gain=0.5, transpose=tr, spread=0.6, humanise=0.01)
    pad = []
    for i, ch in enumerate(chart):
        parts = ch if isinstance(ch[0], tuple) else [(4, ch)]
        at = 0
        for length, notes in parts:
            pad.append((i * 4 + at, length, [midi(notes[1]), midi(notes[3])], 0.5))
            at += length
    T.add("pad", pad, gain=0.35, transpose=tr, spread=0.4)
    tune = """
      E5/3 D5/1 | C5/2 E5/1 G5/1 | A5/3 G5/1 | F5/2 D5/2 |
      E5/3 G5/1 | B5/2 A5/1 G5/1 | A5/1.5 G5/.5 F5/1 E5/1 | D5/4 |
      C5/2 E5/2 | G5/3 E5/1 | F5/1 A5/1 C6/2 | B5/2 G5/2 |
      F5/2 A5/2 | G5/3 E5/1 | E5/2 F5/1 A5/1 | G5/2 R/2 |
    """
    melody, end = seq(tune, vel=0.55)
    assert abs(end - bars * 4) < 1e-6, end
    T.add("ocarina", melody, gain=0.32, pan=0.1, transpose=tr)
    return T.finish(reverb=0.45, rt60=3.0, brightness=0.65, lowpass=7000)


TRACKS = {"music_windowsill": windowsill, "music_lullaby": lullaby,
          "music_kalimba": kalimba_afternoon, "music_moon_harp": moon_harp}


def main():
    out = sys.argv[1]
    names = sys.argv[2:] or list(TRACKS)
    os.makedirs(out, exist_ok=True)
    for name in names:
        mix = TRACKS[name]()
        wavfile.write(os.path.join(out, name + ".wav"), SR, (np.clip(mix, -1, 1) * 32767).astype(np.int16))
        print(f"{name}: {len(mix) / SR:.1f} s, peak {20 * np.log10(np.abs(mix).max()):.1f} dB, "
              f"{a_weighted_db(mix):.1f} dB(A)")


if __name__ == "__main__":
    main()
