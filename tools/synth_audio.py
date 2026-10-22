#!/usr/bin/env python3
"""
Few Turns -- procedural audio synthesizer.

Generates ALL of Few Turns's music and sound effects from scratch (pure synthesis,
no samples, no third-party material). Output is 16-bit PCM WAV:

    assets/audio/music/{menu,ch1..ch9}.wav              (mono, 44100 Hz, seamless loops)
    assets/audio/sfx/*.wav                               (mono, 44100 Hz, one-shots)

Usage (from the project root):

    python3 -m venv .venv && .venv/bin/pip install numpy scipy
    .venv/bin/python tools/synth_audio.py            # everything
    .venv/bin/python tools/synth_audio.py --only pop menu   # a subset (by file stem)
    .venv/bin/python tools/synth_audio.py --check    # analyse existing files only

The script is fully deterministic (fixed RNG seeds): rerunning produces
bit-identical files. Runtime is well under a minute on a laptop.

Loop technique (music): every track is rendered for its loop length L plus a
tail T. The tail is folded (overlap-added) back onto the start, so notes that
ring past the loop point continue seamlessly on the next pass. Reverb, delay
and master EQ are applied as *circular* convolutions over the loop (via FFT),
which yields the exact periodic steady state of an endlessly repeating loop.
Finally the loop is rotated by a few samples so it begins on an upward zero
crossing. The WAV also carries a RIFF 'smpl' chunk with a forward loop
covering the whole file, which Godot's importer picks up ("Detect From WAV").

Released with the project under CC0-style terms (public domain dedication).
"""
import argparse
import os
import struct
import sys
import time

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_MUSIC = os.path.join(ROOT, "assets", "audio", "music")
OUT_SFX = os.path.join(ROOT, "assets", "audio", "sfx")
TAU = 2.0 * np.pi


# =============================================================================
# Basic helpers
# =============================================================================
def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def db_to_lin(d):
    return 10.0 ** (d / 20.0)


def lin_to_db(x):
    return 20.0 * np.log10(max(x, 1e-12))


def tax(dur):
    return np.arange(int(round(dur * SR))) / SR


def smooth_attack(t, a):
    """Raised-cosine attack envelope (0 -> 1 over `a` seconds)."""
    if a <= 0:
        return np.ones_like(t)
    x = np.clip(t / a, 0.0, 1.0)
    return 0.5 - 0.5 * np.cos(np.pi * x)


def fade_tail(y, sec):
    n = min(len(y), int(sec * SR))
    if n > 1:
        y[-n:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n))
    return y


def lp(x, fc, order=2):
    fc = min(fc, SR * 0.45)
    sos = signal.butter(order, fc, "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hp(x, fc, order=2):
    sos = signal.butter(order, fc, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def svf_sweep(x, f_curve, q=0.7, mode="bp"):
    """Chamberlin state-variable filter with a per-sample cutoff curve.
    Pure-python loop: only used on short SFX buffers."""
    low = band = 0.0
    out = np.zeros_like(x)
    damp = 1.0 / q
    fc = np.clip(f_curve, 20, SR / 6.5)
    fcoef = 2.0 * np.sin(np.pi * fc / SR)
    for i in range(len(x)):
        f = fcoef[i]
        low += f * band
        high = x[i] - low - damp * band
        band += f * high
        out[i] = band if mode == "bp" else (low if mode == "lp" else high)
    return out


# =============================================================================
# Instruments (all return float64 mono arrays, peak roughly <= 1)
# =============================================================================
_cache = {}


def cached(key, fn):
    if key not in _cache:
        _cache[key] = fn()
    return _cache[key]


def additive(f, dur, partials, attack=0.003, release=0.05, phase_seed=None):
    """partials: iterable of (ratio, amp, tau_seconds)."""
    t = tax(dur)
    y = np.zeros_like(t)
    rng = np.random.default_rng(phase_seed) if phase_seed is not None else None
    for r, a, tau in partials:
        fr = f * r
        if fr >= SR * 0.45 or a == 0:
            continue
        ph = rng.uniform(0, TAU) if rng is not None else 0.0
        y += a * np.sin(TAU * fr * t + ph) * np.exp(-t / tau)
    y *= smooth_attack(t, attack)
    return fade_tail(y, release)


def kalimba(m, dur=3.0, bright=1.0):
    def make():
        f = mtof(m)
        tau = 1.3 * (523.25 / f) ** 0.25
        y = additive(f, dur, [(1.0, 1.0, tau), (2.0, 0.035, tau * 0.35),
                              (3.0, 0.03, 0.18), (5.95, 0.16 * bright, 0.06),
                              (8.8, 0.04 * bright, 0.025)], attack=0.0015)
        # soft tine click
        rng = np.random.default_rng(int(m * 7) + 11)
        n = int(0.004 * SR)
        click = lp(rng.standard_normal(n), 3500) * np.exp(-np.arange(n) / (0.0012 * SR))
        y[:n] += 0.05 * bright * click
        return y
    return cached(("kal", m, dur, bright), make)


def bell_fm(m, dur=3.0, ratio=3.5, index=1.4, tau=1.4, tau_i=0.12, shimmer=0.12):
    """2-operator FM bell. Index decays fast so inharmonic sidebands only
    colour the strike; the sustain is a near-pure, in-tune sine."""
    def make():
        f = mtof(m)
        t = tax(dur)
        idx = index * min(1.0, 1600.0 / f) * np.exp(-t / tau_i)
        y = np.sin(TAU * f * t + idx * np.sin(TAU * ratio * f * t))
        y *= np.exp(-t / tau)
        y += shimmer * np.sin(TAU * 2.0 * f * 1.0007 * t) * np.exp(-t / (tau * 0.45))
        y *= smooth_attack(t, 0.002)
        return fade_tail(y, 0.08) / (1 + shimmer)
    return cached(("bell", m, dur, ratio, index, tau, tau_i, shimmer), make)


def pluck(m, dur=2.5, bright=0.5, tau1=None, nh=12, inharm=0.00012, detune_c=0.7,
          hammer=0.0):
    """Additive 'piano/e-piano/pluck' voice: upper harmonics decay faster
    (behaves like a closing low-pass); two slightly detuned strings."""
    def make():
        f = mtof(m)
        t1 = tau1 if tau1 is not None else 1.5 * (261.6 / f) ** 0.35
        parts = []
        for k in range(1, nh + 1):
            amp = k ** -1.3 * np.exp(-(k - 1) * (0.55 - 0.45 * bright))
            fk = k * np.sqrt(1 + inharm * k * k)
            tk = t1 / (1 + 0.55 * (k - 1) * (1.2 - bright * 0.5))
            parts.append((fk, amp, tk))
        y = additive(f, dur, parts, attack=0.0025)
        if detune_c:
            y = 0.5 * y + 0.5 * additive(f * 2 ** (detune_c / 1200), dur, parts,
                                         attack=0.0025)
        if hammer:
            rng = np.random.default_rng(int(m * 13) + 5)
            n = int(0.006 * SR)
            y[:n] += hammer * lp(rng.standard_normal(n), 1800) * np.exp(
                -np.arange(n) / (0.002 * SR))
        return fade_tail(y, 0.1) / 1.2
    return cached(("pluck", m, dur, bright, tau1, nh, inharm, detune_c, hammer), make)


def marimba(m, dur=1.8, bright=1.0):
    """Soft woody marimba bar: fundamental plus tuned 4th and 10th partials
    (harmonic, like the pop SFX) and a tiny low-passed mallet thump."""
    def make():
        f = mtof(m)
        tau = 0.55 * (392.0 / f) ** 0.4
        y = additive(f, dur, [(1.0, 1.0, tau), (2.0, 0.03, tau * 0.3),
                              (4.0, 0.22 * bright, tau * 0.18),
                              (10.0, 0.035 * bright, tau * 0.05)], attack=0.002, release=0.08)
        rng = np.random.default_rng(int(m * 17) + 3)
        n = int(0.006 * SR)
        y[:n] += 0.06 * bright * lp(rng.standard_normal(n), 1200) * np.exp(-np.arange(n) / (0.0018 * SR))
        return y
    return cached(("mar", m, dur, bright), make)


def epiano(m, dur=2.4, bright=0.5, tau=1.3):
    """Rhodes-ish electric piano: soft FM body (ratio 1, decaying index)
    plus a short harmonic 'tine' partial at 14x that only colours the attack."""
    def make():
        f = mtof(m)
        t = tax(dur)
        tt = tau * (261.6 / f) ** 0.3
        idx = (0.4 + 1.1 * bright) * min(1.0, 900.0 / f) * np.exp(-t / 0.35)
        y = np.sin(TAU * f * t + idx * np.sin(TAU * f * t)) * np.exp(-t / tt)
        y += 0.3 * np.sin(TAU * f * 1.0009 * t) * np.exp(-t / (tt * 1.2))  # gentle beating
        if 14 * f < SR * 0.45:
            y += 0.06 * bright * np.sin(TAU * 14 * f * t) * np.exp(-t / 0.02)
        y *= smooth_attack(t, 0.003)
        return fade_tail(y, 0.12) / 1.3
    return cached(("ep", m, dur, bright, tau), make)


def wavetable(amps, size=4096):
    ph = np.arange(size) / size
    tab = np.zeros(size)
    for k, a in enumerate(amps, 1):
        tab += a * np.sin(TAU * k * ph)
    return tab / np.max(np.abs(tab))


TAB_WARM = wavetable([1.0, 0.28, 0.12, 0.06, 0.035, 0.02, 0.012])
TAB_GLASS = wavetable([1.0, 0.18, 0.22, 0.05, 0.10, 0.02, 0.05, 0.0, 0.025])
TAB_SOFT = wavetable([1.0, 0.12, 0.04])


def osc(tab, freq, n, phase0=0.0):
    ph = (phase0 + np.cumsum(np.full(n, freq / SR) if np.isscalar(freq) else freq / SR)) % 1.0
    pos = ph * len(tab)
    i0 = pos.astype(np.int64)
    frac = pos - i0
    return tab[i0 % len(tab)] * (1 - frac) + tab[(i0 + 1) % len(tab)] * frac


def pad_voice(m, hold, attack=1.4, release=2.2, tab=TAB_WARM, detunes=(-6, 0, 6),
              cutoff=1500, trem=0.07, seed=0):
    rng = np.random.default_rng(seed)
    n = int((hold + release) * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    y = np.zeros(n)
    for c in detunes:
        y += osc(tab, f * 2 ** (c / 1200.0), n, rng.uniform())
    y /= len(detunes)
    env = smooth_attack(t, attack)
    rel = np.clip((t - hold) / release, 0, 1)
    env *= 0.5 + 0.5 * np.cos(np.pi * rel)
    env *= 1 + trem * np.sin(TAU * rng.uniform(0.12, 0.25) * t + rng.uniform(0, TAU))
    y = lp(y * env, cutoff, 2)
    return y


def sub_drone(m, hold, attack=2.0, release=2.5):
    n = int((hold + release) * SR)
    t = np.arange(n) / SR
    f = mtof(m)
    y = np.sin(TAU * f * t) + 0.12 * np.sin(TAU * 2 * f * t) + 0.04 * np.sin(TAU * 3 * f * t)
    env = smooth_attack(t, attack) * (0.5 + 0.5 * np.cos(np.pi * np.clip((t - hold) / release, 0, 1)))
    return y * env


def soft_bass(m, dur=3.0, tau=1.2):
    return cached(("bass", m, dur, tau), lambda: additive(
        mtof(m), dur, [(1, 1.0, tau), (2, 0.22, tau * 0.5), (3, 0.06, tau * 0.3)],
        attack=0.012, release=0.3))


def soft_kick():
    def make():
        t = tax(0.35)
        f = 46 + 70 * np.exp(-t / 0.035)
        ph = TAU * np.cumsum(f) / SR
        y = np.sin(ph) * np.exp(-t / 0.13) * smooth_attack(t, 0.002)
        return fade_tail(lp(y, 900), 0.05)
    return cached("kick", make)


def shaker(seed=0):
    def make():
        rng = np.random.default_rng(100 + seed)
        t = tax(0.09)
        y = hp(rng.standard_normal(len(t)), 5500) * smooth_attack(t, 0.012) * np.exp(-t / 0.028)
        return fade_tail(lp(y, 11000), 0.02) * 0.5
    return cached(("shaker", seed), make)


# =============================================================================
# Harmony
# =============================================================================
CHORDS = {  # pitch classes, root first. Only the allowed C-major/A-minor set.
    "C": [0, 4, 7], "Am": [9, 0, 4], "F": [5, 9, 0], "G": [7, 11, 2],
    "Dm": [2, 5, 9], "Em": [4, 7, 11], "Fmaj7": [5, 9, 0, 4], "Cmaj7": [0, 4, 7, 11],
    "Am7": [9, 0, 4, 7], "Dm7": [2, 5, 9, 0], "G6": [7, 11, 2, 4], "Csus2": [0, 2, 7],
}
PENTA = [0, 2, 4, 7, 9]  # C D E G A


def chord_tones(name, lo, hi):
    pcs = CHORDS[name]
    return [m for m in range(lo, hi + 1) if m % 12 in pcs]


def root_in(name, lo):
    r = CHORDS[name][0]
    m = lo + ((r - lo) % 12)
    return m


# =============================================================================
# Reverb / delay (circular, for perfectly periodic loops)
# =============================================================================
def make_ir(seconds=3.5, rt=2.6, predelay=0.025, seed=7, bright=1.0, early=True):
    """Algorithmic diffuse reverb impulse: seeded noise split into bands,
    each band decaying with its own RT60 (highs die faster = air damping),
    plus a handful of sparse early reflections."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    N = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / SR)
    bands = [(0, 200, rt * 1.1), (200, 900, rt), (900, 3000, rt * 0.8 * bright),
             (3000, 7000, rt * 0.55 * bright), (7000, SR, rt * 0.3 * bright)]
    ir = np.zeros(n)
    for lo_, hi_, r in bands:
        mask = ((fr >= lo_) & (fr < hi_)).astype(float)
        ir += np.fft.irfft(N * mask, n) * 10 ** (-3 * t / r)
    ir *= 1 - np.exp(-t / 0.03)  # diffuse build-up
    if early:
        pk = np.max(np.abs(ir))
        for k in range(6):
            d = int((0.007 + 0.011 * k + rng.uniform(0, 0.006)) * SR)
            ir[d] += rng.choice([-1, 1]) * 0.5 * pk * 0.75 ** k
    fade_tail(ir, seconds * 0.15)
    pd = int(predelay * SR)
    ir = np.concatenate([np.zeros(pd), ir])[:n]
    return ir / np.sqrt(np.sum(ir ** 2))


def delay_response(L, delay_s, fb, lp_hz):
    """rfft-domain transfer function of a feedback delay with a one-pole
    low-pass in the loop (closed form -> exact periodic steady state)."""
    k = np.arange(L // 2 + 1)
    w = TAU * k / L
    D = int(round(delay_s * SR))
    a = 1 - np.exp(-TAU * lp_hz / SR)
    lpf = a / (1 - (1 - a) * np.exp(-1j * w))
    z = lpf * np.exp(-1j * w * D)
    return z / (1 - fb * z)


# =============================================================================
# Song engine
# =============================================================================
SEED_SHIFT = 4242


class Song:
    def __init__(self, name, bpm, bars, seed, tail=10.0):
        self.name, self.bpm, self.bars = name, bpm, bars
        self.beat = 60.0 / bpm
        self.L = int(round(bars * 4 * self.beat * SR))
        self.T = int(tail * SR)
        assert self.T < self.L
        self.stems = {}
        # Few Turns shares Single Shot's instruments and chord loops, with its own
        # melodies: every seed is shifted.
        self.rng = np.random.default_rng(seed + SEED_SHIFT)

    @property
    def loop_seconds(self):
        return self.L / SR

    def _buf(self, stem):
        if stem not in self.stems:
            self.stems[stem] = np.zeros(self.L + self.T)
        return self.stems[stem]

    def add(self, stem, beat_pos, sig, gain=1.0, human=0.006, vel_var=0.08):
        """Place `sig` at a position in beats, with seeded humanisation."""
        b = self._buf(stem)
        jit = float(np.clip(self.rng.normal(0, human), -2 * human, 2 * human)) if human else 0.0
        v = float(np.clip(1 + self.rng.normal(0, vel_var), 0.7, 1.25)) if vel_var else 1.0
        i = max(0, int(round((beat_pos * self.beat + jit) * SR)))
        n = min(len(sig), len(b) - i)
        if n > 0:
            b[i:i + n] += sig[:n] * gain * v

    def fold(self, x):
        y = x[:self.L].copy()
        y[:self.T] += x[self.L:self.L + self.T]
        return y

    # ---- common parts ------------------------------------------------------
    def pad_chords(self, stem, prog, lo=55, hi=69, root_lo=48, gain=0.12, **kw):
        bar = 4 * self.beat
        for b, ch in enumerate(prog):
            notes = [root_in(ch, root_lo)] + chord_tones(ch, lo, hi)
            for j, m in enumerate(notes):
                sig = pad_voice(m, bar, seed=b * 31 + j * 7 + len(self.name), **kw)
                self.add(stem, b * 4, sig, gain, human=0, vel_var=0)

    def melody(self, stem, prog, density, lo, hi, voice, gain, bank_sparse, bank_dense,
               motif_len=4):
        """Sparse generated melody: chord tones on strong beats, C-major
        pentatonic / chord tones elsewhere, mostly stepwise, rhythms reused
        per phrase so motifs repeat."""
        rng = self.rng
        prev = (lo + hi) // 2
        motifs = {}
        for b, ch in enumerate(prog):
            d = density[b % len(density)]
            if d == 0:
                continue
            bank = bank_sparse if d == 1 else bank_dense
            key = (d, (b // motif_len) % 2, b % motif_len)
            if key not in motifs:
                motifs[key] = bank[rng.integers(len(bank))]
            for pos, dur in motifs[key]:
                strong = abs(pos - round(pos)) < 1e-6 and int(round(pos)) % 2 == 0
                cands = chord_tones(ch, lo, hi)
                if not strong:
                    cands = sorted(set(cands) | {m for m in range(lo, hi + 1) if m % 12 in PENTA})
                c = np.array(cands)
                w = np.exp(-np.abs(c - prev) / 2.5)
                w[c == prev] *= 0.35
                m = int(rng.choice(c, p=w / w.sum()))
                prev = m
                self.add(stem, b * 4 + pos, voice(m, dur), gain)

    def mixdown(self, spec, ir, delay=None, master_hp=35.0, master_lp=None,
                peak_db=-6.0, drive=1.4):
        """spec: stem -> (gain, reverb_send, delay_send)."""
        L = self.L
        dry = np.zeros(L)
        rin = np.zeros(L)
        din = np.zeros(L)
        for stem, (g, rs, ds) in spec.items():
            if stem not in self.stems:
                continue
            x = self.fold(self.stems[stem]) * g
            dry += x
            rin += x * rs
            din += x * ds
        IR = np.fft.rfft(np.concatenate([ir, np.zeros(L - len(ir))]))
        Y = np.fft.rfft(dry) + np.fft.rfft(rin) * IR
        if delay is not None and np.any(din):
            dt, fb, lph, rev_amt = delay
            Hd = delay_response(L, dt, fb, lph)
            Y += np.fft.rfft(din) * Hd * (1 + rev_amt * IR)
        fr = np.fft.rfftfreq(L, 1 / SR)
        r = fr / master_hp
        Y *= r ** 2 / np.sqrt(1 + r ** 4)  # zero-phase 2nd-order HP magnitude
        if master_lp:
            Y /= np.sqrt(1 + (fr / master_lp) ** 4)
        Y[0] = 0.0
        y = np.fft.irfft(Y, L)
        # gentle memoryless soft-clip to tame crest factor, then normalise
        y /= np.max(np.abs(y))
        y = np.tanh(drive * y) / np.tanh(drive)
        y -= y.mean()
        y *= db_to_lin(peak_db) / np.max(np.abs(y))
        # rotate so the loop starts on an upward zero crossing near t=0
        # (searching -5 ms .. +30 ms, picking the gentlest crossing)
        prev = np.roll(y, 1)
        cand = np.where((prev < 0) & (y >= 0))[0]
        lo_, hi_ = int(0.005 * SR), int(0.030 * SR)
        cand = cand[(cand < hi_) | (cand > L - lo_)]
        if len(cand):
            k = int(cand[np.argmin(np.abs(y[cand] - prev[cand]))])
        else:
            k = 0
        return np.roll(y, -k), k


# =============================================================================
# Rhythm banks (beat position, note length in beats) per 4/4 bar
# =============================================================================
SPARSE = [
    [(0, 3)], [(0, 1.5), (2.5, 1.5)], [(1, 3)], [(0, 2), (3, 1)],
    [(0.5, 1.5), (2, 2)], [(2, 2)], [(0, 1), (1.5, 2.5)],
]
DENSE = [
    [(0, 1), (1, 0.5), (1.5, 1.5), (3, 1)], [(0, 1.5), (1.5, 0.5), (2, 2)],
    [(0, 0.5), (0.5, 1), (2, 1), (3, 1)], [(0, 2), (2, 0.5), (2.5, 1.5)],
    [(0.5, 0.5), (1, 1), (2.5, 0.5), (3, 1)],
]


# =============================================================================
# Tracks
# =============================================================================
def track_menu():
    s = Song("menu", 72, 20, seed=101)
    prog = ["Cmaj7", "Am7", "Fmaj7", "G6"] * 5
    s.pad_chords("pad", prog, gain=0.11, attack=1.8, release=2.6, cutoff=1300)
    for b, ch in enumerate(prog):
        s.add("bass", b * 4, soft_bass(root_in(ch, 36), 4.5, 1.8), 0.5, vel_var=0.03)
        if b % 2 == 1:
            s.add("bass", b * 4 + 2.5, soft_bass(root_in(ch, 36) + 7, 3.0, 1.2), 0.22)
    density = [1, 1, 0, 1, 2, 1, 2, 1, 2, 2, 1, 2, 1, 1, 2, 1, 1, 0, 1, 1]
    s.melody("kal", prog, density, 72, 84, lambda m, d: kalimba(m, 3.2), 0.42, SPARSE, DENSE)
    for b in range(0, 20, 4):
        s.add("bell", b * 4 + 2, bell_fm(84 if (b // 4) % 2 == 0 else 91, 4.0, ratio=1.0, index=0.6, tau=1.6), 0.10)
    ir = make_ir(4.0, 3.0, seed=11)
    y, k = s.mixdown({"pad": (1.0, 0.45, 0.0), "bass": (0.55, 0.15, 0.0),
                      "kal": (1.0, 0.5, 0.35), "bell": (1.0, 0.7, 0.3)},
                     ir, delay=(s.beat * 0.75, 0.38, 3500, 0.5), master_lp=9000)
    return s, y


def track_ch1():  # Dawn
    s = Song("ch1", 84, 24, seed=202)
    prog = ["C", "G", "Am", "F", "Csus2", "Em", "F", "G"] * 3
    s.pad_chords("pad", prog, gain=0.07, attack=1.2, release=2.0, cutoff=1100)
    piano = lambda m, d: pluck(m, 2.6, bright=0.45, hammer=0.04)
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 55, 79)
        pat = [0, 2, 3, 4, 2, 3, 1, 3]
        step = 1.0 if b < 8 else 0.5
        for i in range(int(4 / step)):
            idx = pat[i % len(pat)] if step == 0.5 else pat[(i * 2) % len(pat)]
            m = tones[min(idx, len(tones) - 1)]
            acc = 1.0 if (i * step) % 2 == 0 else (0.8 if (i * step) % 1 == 0 else 0.62)
            s.add("arp", b * 4 + i * step, piano(m, 0), 0.26 * acc)
        s.add("bass", b * 4, pluck(root_in(ch, 36), 3.0, bright=0.2, tau1=1.6), 0.5)
        s.add("bass", b * 4 + 2.5, pluck(root_in(ch, 36) + 12, 2.0, bright=0.2, tau1=1.0), 0.16)
    density = [0] * 8 + [1, 1, 2, 1, 1, 2, 1, 1] + [2, 1, 2, 1, 2, 2, 1, 0]
    s.melody("mel", prog, density, 74, 86, lambda m, d: pluck(m, 3.0, bright=0.6, hammer=0.05), 0.42, SPARSE, DENSE)
    ir = make_ir(3.2, 2.3, seed=12)
    y, k = s.mixdown({"pad": (1.0, 0.4, 0.0), "arp": (1.0, 0.3, 0.12),
                      "bass": (0.6, 0.12, 0.0), "mel": (1.0, 0.4, 0.3)},
                     ir, delay=(s.beat * 0.75, 0.3, 3200, 0.4), master_lp=10000)
    return s, y


def track_ch2():  # Glass
    s = Song("ch2", 90, 24, seed=303)
    A = ["Fmaj7", "C", "Dm7", "Am7"]
    B = ["Fmaj7", "Em", "Dm7", "G6"]
    prog = A + A + B + A + A + B
    s.pad_chords("pad", prog, lo=60, hi=76, root_lo=48, gain=0.07, tab=TAB_GLASS,
                 detunes=(-8, -2, 3, 9), attack=1.5, release=2.4, cutoff=2600, trem=0.12)
    glass = lambda m: bell_fm(m, 2.6, ratio=3.5, index=1.1, tau=0.9, tau_i=0.05)
    pats = [[0, 1, 2, None, 3, 2, None, 1], [0, None, 2, 3, None, 1, 2, None]]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 72, 91)
        pat = pats[(b // 4) % 2]
        for i, idx in enumerate(pat):
            if idx is None or (b < 4 and i % 2):
                continue
            acc = 1.0 if i % 2 == 0 else 0.7
            s.add("arp", b * 4 + i * 0.5, glass(tones[min(idx, len(tones) - 1)]), 0.2 * acc)
        s.add("bass", b * 4, soft_bass(root_in(ch, 36), 4.0, 1.6), 0.45)
    density = [1, 0, 1, 0, 1, 1, 2, 1, 1, 0, 1, 1, 2, 1, 2, 1, 1, 1, 2, 1, 1, 0, 1, 0]
    s.melody("mel", prog, density, 79, 91, lambda m, d: bell_fm(m, 4.0, ratio=1.0, index=0.9, tau=1.5, shimmer=0.2), 0.3, SPARSE, DENSE)
    ir = make_ir(4.0, 3.2, seed=13, bright=1.3)
    y, k = s.mixdown({"pad": (1.0, 0.5, 0.0), "arp": (1.0, 0.35, 0.35),
                      "bass": (0.55, 0.1, 0.0), "mel": (1.0, 0.55, 0.4)},
                     ir, delay=(s.beat * 0.75, 0.42, 5000, 0.5), master_lp=12000)
    return s, y


def track_ch3():  # Void
    s = Song("ch3", 70, 20, seed=404)
    A = ["Am", "Dm", "Em", "Am"]
    B = ["Am7", "F", "Dm7", "Em"]
    prog = A + B + A + B + A
    bar = 4 * s.beat
    for b, ch in enumerate(prog):
        s.add("sub", b * 4, sub_drone(root_in(ch, 33), bar, attack=1.6, release=2.4), 0.5, human=0, vel_var=0)
    s.pad_chords("pad", prog, lo=52, hi=67, root_lo=45, gain=0.1, attack=2.2, release=3.0,
                 cutoff=650, trem=0.1)
    density = [1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0]
    distant = lambda m, d: lp(kalimba(m, 3.5, bright=0.6), 2200)
    s.melody("pl", prog, density, 64, 79, distant, 0.4, SPARSE, SPARSE)
    for b in range(2, 20, 4):
        s.add("bell", b * 4 + 1, bell_fm(root_in(prog[b], 57), 5.0, ratio=1.41, index=0.8, tau=2.0), 0.07)
    ir = make_ir(5.0, 4.0, seed=14, bright=0.7)
    y, k = s.mixdown({"sub": (0.6, 0.0, 0.0), "pad": (1.0, 0.55, 0.0),
                      "pl": (0.8, 0.8, 0.5), "bell": (1.0, 0.8, 0.3)},
                     ir, delay=(s.beat * 1.5, 0.45, 2000, 0.7), master_lp=7000)
    return s, y


def track_ch4():  # Shift
    s = Song("ch4", 96, 24, seed=505)
    prog = ["Am", "F", "C", "G"] * 6
    s.pad_chords("pad", prog, gain=0.07, attack=1.3, release=2.0, cutoff=1200)
    updown = [0, 1, 2, 3, 4, 3, 2, 1]
    acc = [1.0, 0.55, 0.75, 0.55]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 57, 76)
        lfo = 0.5 + 0.5 * np.sin(TAU * b / 8.0)  # brightness LFO, 8-bar period
        br = round(0.25 + 0.4 * lfo, 2)
        for i in range(16):
            m = tones[min(updown[i % 8], len(tones) - 1)]
            s.add("arp", b * 4 + i * 0.25, pluck(m, 1.2, bright=br, tau1=0.35, nh=10, detune_c=0), 0.2 * acc[i % 4], human=0.003)
        s.add("bass", b * 4, soft_bass(root_in(ch, 33), 2.6, 0.9), 0.5)
        s.add("bass", b * 4 + 2, soft_bass(root_in(ch, 33), 2.0, 0.7), 0.35)
        for q in (0, 2):
            s.add("kick", b * 4 + q, soft_kick(), 0.5 if b >= 4 else 0.3, human=0.002, vel_var=0.04)
        for e in range(4):
            s.add("shk", b * 4 + e + 0.5, shaker(e % 2), 0.5, human=0.004)
    density = [0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 0, 1, 0, 2, 1, 1, 0, 1, 1, 0, 0, 1, 0]
    s.melody("mel", prog, density, 72, 84, lambda m, d: kalimba(m, 3.0), 0.35, SPARSE, DENSE)
    ir = make_ir(3.0, 2.2, seed=15)
    y, k = s.mixdown({"pad": (1.0, 0.45, 0.0), "arp": (1.0, 0.25, 0.25),
                      "bass": (0.55, 0.05, 0.0), "kick": (0.5, 0.03, 0.0),
                      "shk": (0.05, 0.2, 0.0), "mel": (1.0, 0.5, 0.35)},
                     ir, delay=(s.beat * 0.75, 0.35, 3000, 0.4), master_lp=10000)
    return s, y


def track_ch5():  # Prism
    s = Song("ch5", 100, 28, seed=606)
    A = ["F", "G", "Em", "Am"]
    B = ["C", "G", "Am", "F"]
    prog = A + B + A + B + A + B + A
    s.pad_chords("pad", prog, lo=55, hi=74, gain=0.065, detunes=(-10, -4, 0, 5, 11),
                 attack=1.0, release=1.8, cutoff=1700, trem=0.08)
    pat16 = [0, 2, 1, 3, 2, 4, 3, 1]
    acc = [1.0, 0.5, 0.7, 0.5]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 60, 79)
        hi_t = chord_tones(ch, 79, 93)
        for i in range(16):
            m = tones[min(pat16[i % 8], len(tones) - 1)]
            s.add("arp", b * 4 + i * 0.25, pluck(m, 1.0, bright=0.5, tau1=0.3, nh=10, detune_c=0), 0.16 * acc[i % 4], human=0.003)
        if b >= 4:
            for i in range(8):
                if i % 3 == 2:
                    continue
                s.add("arp2", b * 4 + i * 0.5 + 0.25, bell_fm(hi_t[(i * 2) % len(hi_t)], 1.6, ratio=3.0, index=0.8, tau=0.5, tau_i=0.04), 0.11)
        for e in range(8):
            s.add("bass", b * 4 + e * 0.5, soft_bass(root_in(ch, 33) + (12 if e % 4 == 3 else 0), 0.7, 0.25), 0.4 if e % 2 == 0 else 0.28, human=0.002)
        for q in range(4):
            s.add("kick", b * 4 + q, soft_kick(), 0.5 if q % 2 == 0 else 0.38, human=0.002, vel_var=0.04)
        for e in range(16):
            if e % 2:
                s.add("shk", b * 4 + e * 0.25, shaker(e % 4 == 3), 0.4 if e % 4 == 2 else 0.25, human=0.003)
    density = [1, 0, 1, 1, 2, 1, 2, 1, 1, 2, 1, 2, 2, 1, 2, 1, 1, 1, 2, 2, 2, 1, 2, 1, 1, 0, 1, 0]
    s.melody("mel", prog, density, 76, 88, lambda m, d: bell_fm(m, 3.0, ratio=1.0, index=0.8, tau=1.1, shimmer=0.2), 0.3, SPARSE, DENSE)
    ir = make_ir(3.4, 2.5, seed=16, bright=1.2)
    y, k = s.mixdown({"pad": (1.0, 0.45, 0.0), "arp": (1.0, 0.25, 0.25),
                      "arp2": (1.0, 0.4, 0.4), "bass": (0.5, 0.05, 0.0),
                      "kick": (0.55, 0.02, 0.0), "shk": (0.05, 0.15, 0.0),
                      "mel": (1.0, 0.5, 0.35)},
                     ir, delay=(s.beat * 0.75, 0.35, 4000, 0.4), master_lp=11000)
    return s, y


def track_ch6():  # Gate
    s = Song("ch6", 78, 20, seed=707)
    A = ["Am7", "Fmaj7", "C", "G6"]
    B = ["Dm7", "Am7", "Fmaj7", "Csus2"]
    prog = A + B + A + B + A[:2] + ["Fmaj7", "Csus2"]
    s.pad_chords("pad", prog, lo=55, hi=71, gain=0.075, attack=1.8, release=2.6,
                 cutoff=900, trem=0.06)
    # woody marimba ostinato in eighths: a gentle up-down figure that "turns
    # the key" (rests open up in the B phrases)
    figs = [[0, None, 1, 2, None, 1, 3, None], [0, 2, None, 1, 3, None, 2, None]]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 60, 76)
        fig = figs[(b // 4) % 2]
        for i, idx in enumerate(fig):
            if idx is None or (b < 2 and i % 2):
                continue
            acc = 1.0 if i % 4 == 0 else (0.75 if i % 2 == 0 else 0.6)
            s.add("mar", b * 4 + i * 0.5, marimba(tones[min(idx, len(tones) - 1)], 1.8, bright=0.8),
                  0.26 * acc, human=0.005)
        s.add("bass", b * 4, soft_bass(root_in(ch, 36), 4.2, 1.5), 0.48, vel_var=0.03)
        if b % 4 == 3:
            s.add("bass", b * 4 + 3, soft_bass(root_in(ch, 36) + 7, 1.6, 0.7), 0.18)
    density = [0, 0, 1, 0, 1, 1, 0, 1, 1, 2, 1, 0, 1, 1, 2, 1, 1, 0, 1, 0]
    s.melody("kal", prog, density, 72, 84, lambda m, d: kalimba(m, 3.0, bright=0.7), 0.36, SPARSE, DENSE)
    # soft "unlock" chime at each phrase start: rising pentatonic 3-note figure
    for b in range(4, 20, 8):
        for k, m in enumerate((84, 88, 91)):
            s.add("bell", b * 4 + 2 + k * 0.5, bell_fm(m, 3.0, ratio=1.0, index=0.5, tau=1.2), 0.06 + 0.01 * k)
    ir = make_ir(3.6, 2.6, seed=17, bright=0.8)
    y, k = s.mixdown({"pad": (1.0, 0.45, 0.0), "mar": (1.0, 0.3, 0.2),
                      "bass": (0.55, 0.1, 0.0), "kal": (1.0, 0.5, 0.35),
                      "bell": (1.0, 0.7, 0.35)},
                     ir, delay=(s.beat * 0.75, 0.32, 2800, 0.45), master_lp=8000)
    return s, y


def track_ch7():  # Spark
    s = Song("ch7", 104, 28, seed=808)
    A = ["C", "Em", "Am", "F"]
    B = ["Dm7", "G6", "Cmaj7", "Am7"]
    prog = A + B + A + B + A + B + ["F", "G6", "C", "Csus2"]
    s.pad_chords("pad", prog, lo=55, hi=72, gain=0.06, detunes=(-7, 0, 7),
                 attack=1.2, release=2.0, cutoff=1300, trem=0.07)
    # twinkling bell arpeggio: 16ths with gaps, rising then falling over 2 bars
    pat = [0, None, 1, 2, None, 3, 2, None, 4, None, 3, 1, None, 2, None, 1]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 76, 93)
        for i, idx in enumerate(pat):
            if idx is None or (b < 4 and i % 4 not in (0, 2)):
                continue
            j = idx if b % 2 == 0 else (4 - idx)
            acc = 1.0 if i % 4 == 0 else 0.62
            s.add("bell", b * 4 + i * 0.25, bell_fm(tones[min(j, len(tones) - 1)], 1.6, ratio=3.0,
                  index=0.7, tau=0.45, tau_i=0.03, shimmer=0.15), 0.12 * acc, human=0.003)
        # light pulse: muted pluck eighths on chord tones
        mid = chord_tones(ch, 60, 72)
        for e in range(8):
            m = mid[(e * 2) % len(mid)] if e % 2 == 0 else mid[1 % len(mid)]
            s.add("pulse", b * 4 + e * 0.5, pluck(m, 0.6, bright=0.3, tau1=0.16, nh=8, detune_c=0),
                  0.14 if e % 2 == 0 else 0.1, human=0.002)
        s.add("bass", b * 4, soft_bass(root_in(ch, 36), 1.8, 0.8), 0.45, human=0.002)
        s.add("bass", b * 4 + 1.5, soft_bass(root_in(ch, 36), 1.0, 0.4), 0.22, human=0.002)
        s.add("bass", b * 4 + 2.5, soft_bass(root_in(ch, 36) + 12, 1.0, 0.35), 0.16, human=0.002)
        if b >= 4:
            for q in (0, 2):
                s.add("kick", b * 4 + q, soft_kick(), 0.32, human=0.002, vel_var=0.04)
            for e in range(4):
                s.add("shk", b * 4 + e + 0.5, shaker(e % 2), 0.35, human=0.004)
    density = [0, 0, 0, 0, 1, 0, 1, 1, 1, 2, 1, 1, 2, 1, 2, 1, 1, 1, 2, 1, 2, 2, 1, 1, 1, 1, 1, 0]
    s.melody("mel", prog, density, 72, 84, lambda m, d: kalimba(m, 2.6, bright=0.8), 0.3, SPARSE, DENSE)
    ir = make_ir(3.4, 2.5, seed=18, bright=1.2)
    y, k = s.mixdown({"pad": (1.0, 0.45, 0.0), "bell": (1.0, 0.4, 0.4),
                      "pulse": (1.0, 0.15, 0.05), "bass": (0.5, 0.05, 0.0),
                      "kick": (0.4, 0.02, 0.0), "shk": (0.04, 0.2, 0.0),
                      "mel": (1.0, 0.5, 0.35)},
                     ir, delay=(s.beat * 0.75, 0.38, 4500, 0.45), master_lp=11000)
    return s, y


def track_ch8():  # Turn
    s = Song("ch8", 88, 24, seed=909)
    A = ["Fmaj7", "G6", "Em", "Am7"]
    B = ["Dm7", "G", "Cmaj7", "Am7"]
    C = ["Fmaj7", "G6", "Cmaj7", "Csus2"]
    prog = A + B + A + C + A + C
    s.pad_chords("pad", prog, lo=55, hi=74, gain=0.065, detunes=(-9, -3, 3, 9),
                 attack=1.4, release=2.2, cutoff=1400, trem=0.08)
    # rotating 3-note cycle on a 16th grid (3-against-4): the cycle phase drifts
    # against the beat so the accent pattern turns every bar
    cyc = [0, 2, 1]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 60, 79)
        for i in range(16):
            n = b * 16 + i
            idx = cyc[n % 3] + (1 if (n // 3) % 4 == 3 else 0)
            m = tones[min(idx, len(tones) - 1)]
            acc = 1.0 if n % 3 == 0 else 0.6
            if i % 4 == 0:
                acc *= 1.15
            s.add("ep", b * 4 + i * 0.25, epiano(m, 1.6, bright=0.35, tau=0.6), 0.12 * acc, human=0.003)
        # counter-cycle: 4-note figure in dotted eighths (another 3:4 layer)
        if b >= 4:
            hi_t = chord_tones(ch, 72, 88)
            for k in range(6):
                pos = k * 0.75
                if pos >= 4:
                    break
                j = [0, 2, 3, 1][(b * 6 + k) % 4]
                s.add("ep2", b * 4 + pos, epiano(hi_t[min(j, len(hi_t) - 1)], 2.0, bright=0.5, tau=0.8),
                      0.1, human=0.003)
        s.add("bass", b * 4, soft_bass(root_in(ch, 36), 3.0, 1.2), 0.48, vel_var=0.03)
        s.add("bass", b * 4 + 2.5, soft_bass(root_in(ch, 36) + 7, 1.6, 0.6), 0.2)
        if b >= 8:
            s.add("kick", b * 4, soft_kick(), 0.3, human=0.002, vel_var=0.04)
            s.add("kick", b * 4 + 2.5, soft_kick(), 0.2, human=0.002, vel_var=0.04)
    density = [0, 0, 0, 0, 1, 1, 1, 0, 1, 2, 1, 1, 2, 1, 2, 1, 1, 2, 1, 1, 2, 1, 1, 0]
    s.melody("mel", prog, density, 74, 86, lambda m, d: bell_fm(m, 3.4, ratio=1.0, index=0.7, tau=1.3, shimmer=0.18), 0.28, SPARSE, DENSE)
    ir = make_ir(4.0, 3.0, seed=19, bright=0.95)
    y, k = s.mixdown({"pad": (1.0, 0.5, 0.0), "ep": (1.0, 0.3, 0.25),
                      "ep2": (1.0, 0.45, 0.4), "bass": (0.55, 0.08, 0.0),
                      "kick": (0.4, 0.02, 0.0), "mel": (1.0, 0.55, 0.35)},
                     ir, delay=(s.beat * 0.75, 0.36, 3500, 0.45), master_lp=9500)
    return s, y


def track_ch9():  # Drift
    s = Song("ch9", 76, 24, seed=1010)
    A = ["Am7", "Fmaj7", "Cmaj7", "G6"]
    B = ["Dm7", "Am7", "Fmaj7", "Em"]
    C = ["Fmaj7", "G6", "Am7", "Csus2"]
    prog = A + A + B + A + C + A
    s.pad_chords("pad", prog, lo=52, hi=72, gain=0.07, detunes=(-8, -2, 4, 9),
                 attack=2.0, release=2.8, cutoff=1200, trem=0.05)
    # gliding kalimba figure: up the chord, then back down, like a platform
    # sliding to the end of its rail and returning
    shape = [0, 1, 2, 3, 2, 1]
    for b, ch in enumerate(prog):
        tones = chord_tones(ch, 57, 81)
        for i in range(6):
            pos = i * (4.0 / 6.0)
            m = tones[min(shape[i] + (b % 2), len(tones) - 1)]
            acc = 1.0 if i in (0, 3) else 0.7
            s.add("kal", b * 4 + pos, kalimba(m, 2.6, bright=0.8), 0.14 * acc, human=0.004)
        s.add("bass", b * 4, soft_bass(root_in(ch, 33), 3.6, 1.6), 0.46, vel_var=0.03)
        if b >= 6 and b % 2 == 1:
            s.add("bass", b * 4 + 3.0, soft_bass(root_in(ch, 33) + 12, 1.2, 0.5), 0.16)
        if b >= 12:
            mt = chord_tones(ch, 69, 86)
            s.add("mar", b * 4 + 1.5, marimba(mt[(b * 3) % len(mt)], 1.6, bright=0.6), 0.1, human=0.003)
    density = [0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 2, 1, 1, 0, 1, 2, 1, 1, 2, 1, 1, 0, 1, 0]
    s.melody("mel", prog, density, 72, 84, lambda m, d: bell_fm(m, 3.8, ratio=2.0, index=0.6, tau=1.6, shimmer=0.2), 0.26, SPARSE, DENSE)
    ir = make_ir(4.5, 3.4, seed=23, bright=0.9)
    y, k = s.mixdown({"pad": (1.0, 0.55, 0.0), "kal": (1.0, 0.35, 0.3),
                      "bass": (0.55, 0.08, 0.0), "mar": (1.0, 0.45, 0.35),
                      "mel": (1.0, 0.6, 0.4)},
                     ir, delay=(s.beat * 1.5, 0.4, 3000, 0.5), master_lp=9000)
    return s, y


# Each chapter gets the track whose mood suits its colours (the functions keep
# the names they were written under).
TRACKS = {"menu": (track_menu, 72, "C major (Cmaj7-Am7-Fmaj7-G6)"),
          "ch1": (track_ch1, 84, "Path: C major (C-G-Am-F-Csus2-Em-F-G)"),
          "ch2": (track_ch2, 90, "Signs: C major / F lydian colour (Fmaj7-C-Dm7-Am7 | Fmaj7-Em-Dm7-G6)"),
          "ch3": (track_ch9, 76, "Bank: A minor / C major (Am7-Fmaj7-Cmaj7-G6 | Dm7-Am7-Fmaj7-Em)"),
          "ch4": (track_ch6, 78, "Gate: A minor / C major (Am7-Fmaj7-C-G6 | Dm7-Am7-Fmaj7-Csus2)"),
          "ch5": (track_ch8, 88, "Spin: C major (Fmaj7-G6-Em-Am7 | Dm7-G-Cmaj7-Am7 | Fmaj7-G6-Cmaj7-Csus2)"),
          "ch6": (track_ch4, 96, "Shift: A minor (Am-F-C-G)"),
          "ch7": (track_ch7, 104, "Crumble: C major (C-Em-Am-F | Dm7-G6-Cmaj7-Am7)"),
          "ch8": (track_ch5, 100, "Count: C major / A minor (F-G-Em-Am | C-G-Am-F)"),
          "ch9": (track_ch3, 70, "Pair: A minor (Am-Dm-Em-Am | Am7-F-Dm7-Em)")}


# =============================================================================
# SFX
# =============================================================================
SFX_IR = None


def small_room(x, wet=0.2, rt=0.9, seconds=1.2):
    global SFX_IR
    if SFX_IR is None:
        SFX_IR = make_ir(seconds, rt, predelay=0.01, seed=21, early=False)
    w = signal.fftconvolve(x, SFX_IR)[:len(x)]
    return x + wet * w * (np.max(np.abs(x)) / (np.max(np.abs(w)) + 1e-12))


def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def sfx_pop():
    f = 523.25
    dur = 0.6
    t = tax(dur)
    # marimba/kalimba bar: strong fundamental, tuned 4th & 10th partials (harmonic -> repitch-safe)
    y = additive(f, dur, [(1.0, 1.0, 0.22), (2.0, 0.06, 0.08), (4.0, 0.28, 0.045),
                          (10.0, 0.05, 0.012)], attack=0.0012, release=0.05)
    # soft "pop": short downward bubble chirp + a little filtered air
    n = int(0.018 * SR)
    tt = np.arange(n) / SR
    chirp = np.sin(TAU * np.cumsum(1400 * np.exp(-tt / 0.006) + 700) / SR) * np.exp(-tt / 0.004)
    y[:n] += 0.22 * chirp
    m = int(0.006 * SR)
    y[:m] += 0.08 * bp(noise(m, 1), 1500, 6000) * np.exp(-np.arange(m) / (0.0015 * SR))
    return y


def sfx_bounce():
    t = tax(0.12)
    f = 220 + 90 * np.exp(-t / 0.012)
    y = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.028)
    y += 0.25 * np.sin(TAU * 2.7 * 220 * t) * np.exp(-t / 0.008)
    m = int(0.003 * SR)
    y[:m] += 0.25 * lp(noise(m, 2), 2500)
    return lp(y * smooth_attack(t, 0.0008), 3000)


def sfx_bounce_glass():
    f = mtof(88)  # E6
    t = tax(0.25)
    y = (np.sin(TAU * f * t) * np.exp(-t / 0.07) + 0.5 * np.sin(TAU * 2.76 * f * t) * np.exp(-t / 0.03)
         + 0.25 * np.sin(TAU * 5.4 * f * t) * np.exp(-t / 0.012))
    return small_room(y * smooth_attack(t, 0.0008), 0.12)


def sfx_glass_break():
    rng = np.random.default_rng(3)
    dur = 0.6
    t = tax(dur)
    y = np.zeros_like(t)
    for k in range(26):
        t0 = 0.4 * (rng.uniform() ** 1.8)
        f = rng.uniform(2200, 7000)
        amp = (1 - t0 / 0.45) * rng.uniform(0.3, 1.0)
        i = int(t0 * SR)
        tt = t[: len(t) - i]
        tau = rng.uniform(0.015, 0.05)
        y[i:] += amp * (np.sin(TAU * f * tt) + 0.4 * np.sin(TAU * f * 1.53 * tt)) * np.exp(-tt / tau) * smooth_attack(tt, 0.0005)
    y += 0.5 * hp(noise(len(t), 4), 3000) * np.exp(-t / 0.05) * smooth_attack(t, 0.002)
    y += 0.4 * np.sin(TAU * mtof(84) * t) * np.exp(-t / 0.12)
    return small_room(y, 0.2)


def sfx_bumper():
    t = tax(0.2)
    f = 300 * (1 + 0.5 * (1 - np.exp(-t / 0.05))) * (1 + 0.03 * np.sin(TAU * 18 * t) * np.exp(-t / 0.06))
    ph = TAU * np.cumsum(f) / SR
    y = (np.sin(ph) + 0.18 * np.sin(2 * ph)) * np.exp(-t / 0.06) * smooth_attack(t, 0.003)
    return lp(y, 4000)


def sfx_portal():
    t = tax(0.35)
    sweep = 400 * (3000 / 400) ** (t / 0.35)
    y = svf_sweep(noise(len(t), 5), sweep, q=3.0)
    env = smooth_attack(t, 0.18) * np.exp(-np.clip(t - 0.18, 0, None) / 0.06)
    y = y / np.max(np.abs(y)) * env
    y += 0.25 * np.sin(TAU * np.cumsum(sweep * 0.5) / SR) * env
    return small_room(y, 0.25)


def sfx_absorb():
    t = tax(0.4)
    f = 55 + 110 * np.exp(-t / 0.08)
    ph = TAU * np.cumsum(f) / SR
    y = (np.sin(ph) + 0.25 * np.sin(2 * ph)) * smooth_attack(t, 0.012) * np.exp(-t / 0.12)
    y += 0.25 * lp(noise(len(t), 6), 400) * np.exp(-t / 0.08)
    return np.tanh(1.5 * y)


def sfx_split():
    t = tax(0.35)
    y = np.zeros_like(t)
    for m in (91, 96):  # G6, C7
        for c in (-12, -4, 4, 12):
            y += np.sin(TAU * mtof(m) * 2 ** (c / 1200) * t + c) * np.exp(-t / 0.12)
    y += 1.5 * hp(noise(len(t), 7), 6000) * np.exp(-t / 0.04)
    y *= smooth_attack(t, 0.002)
    return small_room(lp(y, 12000), 0.2)


def sfx_shield():
    f = mtof(79)  # G5
    t = tax(0.25)
    y = np.zeros_like(t)
    for r, a, tau in [(1, 1, 0.09), (2.76, 0.6, 0.05), (5.40, 0.35, 0.025), (8.93, 0.15, 0.012)]:
        y += a * np.sin(TAU * f * r * t) * np.exp(-t / tau)
    m = int(0.003 * SR)
    y[:m] += 0.3 * bp(noise(m, 8), 2000, 8000)
    return lp(y * smooth_attack(t, 0.0006), 8000)


def sfx_launch():
    t = tax(0.2)
    sweep = 600 * (2600 / 600) ** np.clip(t / 0.12, 0, 1)
    air = svf_sweep(noise(len(t), 9), sweep, q=1.5)
    air = air / np.max(np.abs(air)) * smooth_attack(t, 0.03) * np.exp(-np.clip(t - 0.03, 0, None) / 0.04)
    f = 70 + 60 * np.exp(-t / 0.03)
    thump = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.04) * smooth_attack(t, 0.002)
    return 0.7 * air + 0.6 * thump


def sfx_fizzle():
    t = tax(0.4)
    y = np.zeros_like(t)
    for k, m in enumerate([96, 93, 91, 88, 86, 84]):
        i = int(k * 0.05 * SR)
        tt = t[: len(t) - i]
        y[i:] += 0.8 ** k * np.sin(TAU * mtof(m) * tt) * np.exp(-tt / 0.05) * smooth_attack(tt, 0.001)
    hiss = svf_sweep(noise(len(t), 10), 6000 * (800 / 6000) ** (t / 0.4), q=0.8, mode="lp")
    y += 0.15 * hiss / np.max(np.abs(hiss)) * np.exp(-t / 0.15)
    return small_room(y, 0.2)


def sfx_win():
    dur = 1.6
    t = tax(dur)
    y = np.zeros_like(t)
    for k, m in enumerate([72, 76, 79, 84]):
        b = bell_fm(m, dur, ratio=1.0, index=0.9, tau=0.6 if k < 3 else 0.9, shimmer=0.15)
        i = int(k * 0.11 * SR)
        y[i:] += (0.7 if k < 3 else 0.9) * b[: len(t) - i]
    pad = np.zeros_like(t)
    for m in (60, 64, 67, 72):
        pad += osc(TAB_SOFT, mtof(m), len(t), m * 0.1)
    env = smooth_attack(t, 0.45) * (0.5 + 0.5 * np.cos(np.pi * np.clip((t - 0.5) / 1.1, 0, 1)))
    y += 0.12 * lp(pad * env, 2000)
    return small_room(y, 0.3)


def sfx_star():
    f = mtof(84)  # C6 = 1046.5 Hz
    t = tax(0.5)
    y = additive(f, 0.5, [(1, 1.0, 0.18), (2, 0.25, 0.07), (3, 0.08, 0.04), (4, 0.06, 0.02)], attack=0.001)
    y += 0.15 * np.sin(TAU * 2.76 * f * t) * np.exp(-t / 0.01)
    return small_room(y, 0.18)


def sfx_fail():
    dur = 0.8
    t = tax(dur)
    y = np.zeros_like(t)
    for k, m in enumerate([67, 64]):  # G4 -> E4
        i = int(k * 0.28 * SR)
        tt = t[: len(t) - i]
        tone = (np.sin(TAU * mtof(m) * tt) + 0.15 * np.sin(TAU * 2 * mtof(m) * tt)) * smooth_attack(tt, 0.02)
        tone *= np.exp(-tt / (0.12 if k == 0 else 0.2))
        y[i:] += tone
    return small_room(lp(y, 2500), 0.2)


def sfx_aim_tick():
    t = tax(0.03)
    y = np.sin(TAU * 2093 * t) * np.exp(-t / 0.004) * smooth_attack(t, 0.0005)
    return y


def sfx_ui_tap():
    t = tax(0.06)
    f = 800 + 500 * np.exp(-t / 0.006)
    ph = TAU * np.cumsum(f) / SR
    return (np.sin(ph) + 0.1 * np.sin(2 * ph)) * np.exp(-t / 0.012) * smooth_attack(t, 0.0008)


def sfx_ui_back():
    t = tax(0.07)
    f = 480 + 260 * np.exp(-t / 0.008)
    ph = TAU * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.015) * smooth_attack(t, 0.001)


def sfx_ui_toggle():
    t = tax(0.1)
    y = np.zeros_like(t)
    for k, f in enumerate((880.0, 1318.5)):
        i = int(k * 0.045 * SR)
        tt = t[: len(t) - i]
        y[i:] += np.sin(TAU * f * tt) * np.exp(-tt / 0.012) * smooth_attack(tt, 0.0008)
    return y


def sfx_unlock():
    dur = 0.9
    t = tax(dur)
    y = np.zeros_like(t)
    seq = [84, 86, 88, 91, 93, 96]
    for k, m in enumerate(seq):
        i = int(k * 0.065 * SR)
        b = bell_fm(m, dur, ratio=3.0, index=0.6, tau=0.25 if k < 5 else 0.5, tau_i=0.03)
        y[i:] += 0.6 * b[: len(t) - i]
    sh = hp(noise(len(t), 11), 7000) * smooth_attack(t, 0.25) * np.exp(-np.clip(t - 0.25, 0, None) / 0.15)
    y += 0.08 * sh
    return small_room(y, 0.3)


def sfx_hint():
    dur = 0.6
    t = tax(dur)
    rng = np.random.default_rng(12)
    y = np.zeros_like(t)
    for m in (84, 88, 91, 93, 96, 98):
        trem = 0.5 + 0.5 * np.sin(TAU * rng.uniform(9, 16) * t + rng.uniform(0, TAU))
        y += np.sin(TAU * mtof(m) * t + rng.uniform(0, TAU)) * trem * rng.uniform(0.5, 1.0)
    env = smooth_attack(t, 0.15) * np.exp(-np.clip(t - 0.15, 0, None) / 0.12)
    y = y * env + 0.6 * hp(noise(len(t), 13), 6000) * env * 0.3
    return small_room(lp(y, 12000), 0.3)


def sfx_undo():
    t = tax(0.25)
    sweep = 500 * (3000 / 500) ** (t / 0.25)
    y = svf_sweep(noise(len(t), 14), sweep, q=2.0)
    y = y / np.max(np.abs(y)) * smooth_attack(t, 0.01) * np.exp(-t / 0.06)
    y += 0.3 * np.sin(TAU * np.cumsum(sweep * 0.25) / SR) * np.exp(-t / 0.05)
    y = y[::-1].copy()  # reversed: swells in, cuts off
    return y


# name: (fn, target peak dBFS, purpose)
SFX = {
    "pop": (sfx_pop, -3, "Target pop, C5 (523.25 Hz); re-pitched for combo chains"),
    "bounce": (sfx_bounce, -9, "Orb hits a wall"),
    "bounce_glass": (sfx_bounce_glass, -4, "Orb ricochets off a glass pane"),
    "glass_break": (sfx_glass_break, -4, "Glass pane shatters"),
    "bumper": (sfx_bumper, -4, "Orb hits a round bumper"),
    "portal": (sfx_portal, -4, "Orb enters a portal"),
    "absorb": (sfx_absorb, -3, "Orb swallowed by a void block"),
    "split": (sfx_split, -4, "Orb splits at a prism"),
    "shield": (sfx_shield, -4, "Armoured target's shield cracks"),
    "launch": (sfx_launch, -4, "Orb fired"),
    "fizzle": (sfx_fizzle, -5, "Orb out of bounces, dissolves"),
    "win": (sfx_win, -3, "Level cleared"),
    "star": (sfx_star, -3, "Star appears on results (C6; re-pitched per star)"),
    "fail": (sfx_fail, -5, "Out of shots"),
    "aim_tick": (sfx_aim_tick, -18, "Aim adjust tick"),
    "ui_tap": (sfx_ui_tap, -4, "Button tap"),
    "ui_back": (sfx_ui_back, -6, "Back / close"),
    "ui_toggle": (sfx_ui_toggle, -5, "Toggle switch"),
    "unlock": (sfx_unlock, -3, "Chapter / level unlocked"),
    "hint": (sfx_hint, -5, "Hint shown"),
    "undo": (sfx_undo, -5, "Undo / rewind"),
}


def finalize_sfx(y, peak_db, fade_ms=6.0):
    y = hp(np.asarray(y, float), 18, 1)  # remove DC / sub-sonic drift
    a = np.abs(y)
    thr = np.max(a) * db_to_lin(-60)
    nz = np.where(a > thr)[0]
    y = y[max(0, nz[0] - 8): nz[-1] + 1].copy()
    # tiny fade-in (keeps transients) and fade-out
    k = min(len(y), 16)
    y[:k] *= np.linspace(0, 1, k)
    fade_tail(y, fade_ms / 1000.0)
    y *= db_to_lin(peak_db) / np.max(np.abs(y))
    return y


# =============================================================================
# WAV I/O
# =============================================================================
def to_int16(y, seed):
    rng = np.random.default_rng(seed)
    d = (rng.uniform(-0.5, 0.5, len(y)) + rng.uniform(-0.5, 0.5, len(y)))  # TPDF, 1 LSB
    q = np.round(np.clip(y, -1, 1) * 32767.0 + d)
    return np.clip(q, -32768, 32767).astype("<i2")


def write_wav(path, data16, sr=SR, loop=False):
    data = data16.tobytes()
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, 1, sr, sr * 2, 2, 16)
    chunks = fmt + struct.pack("<4sI", b"data", len(data)) + data
    if len(data) % 2:
        chunks += b"\0"
    if loop:
        n = len(data16)
        smpl = struct.pack("<9I", 0, 0, int(round(1e9 / sr)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n - 1, 0, 0)  # forward loop, whole file (end inclusive)
        chunks += struct.pack("<4sI", b"smpl", len(smpl)) + smpl
    with open(path, "wb") as fh:
        fh.write(struct.pack("<4sI4s", b"RIFF", 4 + len(chunks), b"WAVE") + chunks)


def read_wav(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    pos = 12
    sr = ch = None
    data = None
    while pos + 8 <= len(raw):
        cid, size = struct.unpack("<4sI", raw[pos:pos + 8])
        body = raw[pos + 8: pos + 8 + size]
        if cid == b"fmt ":
            _, ch, sr = struct.unpack("<HHI", body[:8])
        elif cid == b"data":
            data = np.frombuffer(body, "<i2").astype(np.int32)
        pos += 8 + size + (size & 1)
    return sr, ch, data


# =============================================================================
# Analysis
# =============================================================================
def analyse(path, is_loop=False, f0_expect=None):
    sr, ch, d = read_wav(path)
    x = d / 32768.0
    peak = np.max(np.abs(x))
    rms = np.sqrt(np.mean(x ** 2))
    row = {
        "file": os.path.relpath(path, ROOT), "dur": len(d) / sr, "sr": sr, "ch": ch,
        "kb": os.path.getsize(path) / 1024.0, "peak": lin_to_db(peak), "rms": lin_to_db(rms),
        "dc": float(np.mean(x)), "clip": int(np.sum(np.abs(d) >= 32767)),
    }
    if is_loop:
        dd = np.abs(np.diff(d))
        row["jump"] = abs(int(d[-1]) - int(d[0]))
        row["jump_med"] = float(np.median(dd))
        row["jump_p99"] = float(np.percentile(dd, 99))
        d2 = np.abs(np.diff(d, 2))
        row["slope_err"] = abs((int(d[0]) - int(d[-1])) - (int(d[-1]) - int(d[-2])))
        row["slope_p99"] = float(np.percentile(d2, 99))
        row["first_last"] = (int(d[0]), int(d[-1]))
        # steps in the ~3 ms either side of the seam, for comparison
        row["seam_local"] = int(max(np.max(dd[:128]), np.max(dd[-128:])))
    if f0_expect:
        n = 1 << 20
        w = x * np.hanning(len(x))
        S = np.abs(np.fft.rfft(w, n))
        fr = np.fft.rfftfreq(n, 1 / sr)
        band = (fr > f0_expect * 0.7) & (fr < f0_expect * 1.3)
        i = np.argmax(S * band)
        a, b, c = np.log(S[i - 1:i + 2] + 1e-20)
        off = 0.5 * (a - c) / (a - 2 * b + c)
        row["f0"] = (i + off) * sr / n
        row["f0_is_strongest"] = bool(np.argmax(S[fr > 60]) == np.argmax(S[fr > 60] * (np.abs(fr[fr > 60] - row["f0"]) < 3)))
    return row


def print_table(rows):
    print("\n%-34s %7s %6s %3s %8s %7s %7s %9s %4s" % (
        "file", "dur(s)", "sr", "ch", "size_KB", "peak", "rms", "dc", "clip"))
    for r in rows:
        print("%-34s %7.3f %6d %3d %8.1f %7.2f %7.2f %9.6f %4d" % (
            r["file"], r["dur"], r["sr"], r["ch"], r["kb"], r["peak"], r["rms"], r["dc"], r["clip"]))
    for r in rows:
        if "jump" in r:
            print("  loop %-28s |last-first|=%d LSB (median adjacent step %.0f, p99 %.0f); "
                  "slope err=%d (p99 2nd-diff %.0f); first/last=%s; max step within 3 ms of seam=%d" % (
                      os.path.basename(r["file"]), r["jump"], r["jump_med"], r["jump_p99"],
                      r["slope_err"], r["slope_p99"], r["first_last"], r["seam_local"]))
        if "f0" in r:
            print("  pitch %-27s f0=%.3f Hz (target 523.25, err %.3f Hz), fundamental strongest: %s" % (
                os.path.basename(r["file"]), r["f0"], r["f0"] - 523.25, r["f0_is_strongest"]))


# =============================================================================
# Main
# =============================================================================
def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--only", nargs="*", help="file stems to render (e.g. pop menu ch3)")
    ap.add_argument("--check", action="store_true", help="only analyse existing output")
    args = ap.parse_args()
    os.makedirs(OUT_MUSIC, exist_ok=True)
    os.makedirs(OUT_SFX, exist_ok=True)
    want = set(args.only) if args.only else None
    t0 = time.time()
    rows = []
    for name, (fn, bpm, key) in TRACKS.items():
        if want and name not in want:
            continue
        path = os.path.join(OUT_MUSIC, name + ".wav")
        if not args.check:
            ts = time.time()
            s, y = fn()
            write_wav(path, to_int16(y, seed=len(name) * 977 + bpm), loop=True)
            print("music %-5s %3d BPM  %2d bars  loop %.4f s (%d samples)  [%.1fs]" % (
                name, bpm, s.bars, s.loop_seconds, s.L, time.time() - ts))
        if os.path.exists(path):
            rows.append(analyse(path, is_loop=True))
    for i, (name, (fn, pk, _)) in enumerate(SFX.items()):
        if want and name not in want:
            continue
        path = os.path.join(OUT_SFX, name + ".wav")
        if not args.check:
            y = finalize_sfx(fn(), pk)
            write_wav(path, to_int16(y, seed=5000 + i))
        if os.path.exists(path):
            rows.append(analyse(path, f0_expect=523.25 if name == "pop" else None))
    print_table(rows)
    print("\nTotal time %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
