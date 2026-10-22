# Few Turns — Audio

All music and sound effects in `assets/audio/music/` and `assets/audio/sfx/` are
**original and fully synthesized** by `tools/synth_audio.py`. The instruments and chord loops are shared with Single Shot; every melody is Few Turns' own (all seeds are shifted by `SEED_SHIFT`), and each chapter uses the track whose mood suits its colours. There are no
samples, recordings or third-party material. They are released with the
project under CC0-style terms (public domain dedication), so you can ship,
modify and redistribute them freely.

Format: 16-bit PCM WAV, mono, 44100 Hz.

## Regenerating

```sh
python3 -m venv .venv && .venv/bin/pip install numpy scipy
.venv/bin/python tools/synth_audio.py              # everything (about 15 s)
.venv/bin/python tools/synth_audio.py --only pop ch3   # a subset, by file stem
.venv/bin/python tools/synth_audio.py --check      # analyse existing files only
```

The script is deterministic: it uses fixed seeds, so every rerun produces
bit-identical files. Each run prints an analysis table with duration, peak,
RMS, DC offset and clip count for every file, plus loop-seam metrics for the
music and an FFT pitch check for `pop.wav`.

## Music (`assets/audio/music/`)

Every track loops **sample-exactly** over the whole file. Notes that ring past
the loop point are folded back onto the start. Reverb and delay are applied as
circular convolutions, so the file is the exact steady state of an endless
loop. Each file starts on an upward zero crossing and has no fade at the
seam. Each file also has a RIFF `smpl` chunk with a forward loop over the
whole file (start 0, end = last sample, inclusive), which Godot's WAV importer
picks up when the loop mode is "Detect From WAV".

> **Godot note:** `audio_manager.gd` currently sets `loop_mode = LOOP_FORWARD`
> at runtime. If the importer does not set loop points, also set
> `loop_begin = 0` and `loop_end = <frame count>` (the sample count below).
> Otherwise set Loop Mode to Forward in the import dock.

Harmony: every track uses only chords from {C, Am, F, G, Dm, Em, Fmaj7, Cmaj7,
Am7, Dm7, G6, Csus2}. That keeps the C-major-pentatonic target pops (C D E G A)
consonant over any track. Mixes peak at -6 dBFS, with RMS around -16 to -18 dBFS.

| File | Title | BPM | Bars (4/4) | Loop length | Samples | Key / progression | Character |
|---|---|---|---|---|---|---|---|
| `menu.wav` | Home | 72 | 20 | **66.6667 s** | 2 940 000 | C major: Cmaj7 · Am7 · Fmaj7 · G6 | Warm detuned pad, sparse kalimba motif, soft bass, occasional bell |
| `ch1.wav` | Path | 84 | 24 | **68.5714 s** | 3 024 000 | C major: C · G · Am · F · Csus2 · Em · F · G | Soft piano-like pluck arpeggios (quarters then eighths), piano melody, light pad |
| `ch2.wav` | Signs | 90 | 24 | **64.0000 s** | 2 822 400 | C major / F-lydian colour: Fmaj7 · C · Dm7 · Am7 (×2), Fmaj7 · Em · Dm7 · G6 | FM glass-bell arpeggios with dotted-eighth delay, shimmering pad, bell melody |
| `ch3.wav` | Bank | 76 | 24 | **75.7895 s** | 3 342 316 | A minor / C major: Am7 · Fmaj7 · Cmaj7 · G6 / Dm7 · Am7 · Fmaj7 · Em | Airy and sky-blue: soft plucks drifting over a wide pad, with slow bells |
| `ch4.wav` | Gate | 78 | 20 | **61.5385 s** | 2 713 846 | A minor / C major: Am7 · Fmaj7 · C · G6 / Dm7 · Am7 · Fmaj7 · Csus2 (last phrase ends Am7 · Fmaj7 · Fmaj7 · Csus2) | Chapter 6, warm and earthy (sage green). Soft woody marimba eighth-note ostinato, low-passed warm pad, kalimba melody, soft bass, and a quiet rising C6-E6-G6 "unlock" chime every 8 bars |
| `ch5.wav` | Spin | 88 | 24 | **65.4545 s** | 2 886 545 | C major, phrases A B A C A C: A = Fmaj7 · G6 · Em · Am7, B = Dm7 · G · Cmaj7 · Am7, C = Fmaj7 · G6 · Cmaj7 · Csus2 | Grand final chapter (rose/terracotta). Electric-piano 3-note cycle on a 16th grid (3-against-4, so the accents rotate each bar), a dotted-eighth e-piano counter-cycle from bar 5, wide pad, bell melody, very soft kick from bar 9 |
| `ch6.wav` | Shift | 96 | 24 | **60.0000 s** | 2 646 000 | A minor: Am · F · C · G | 16th-note pluck arpeggiator with 8-bar brightness LFO, very soft kick + shaker, pad |
| `ch7.wav` | Crumble | 104 | 28 | **64.6154 s** | 2 849 538 | C major: C · Em · Am · F / Dm7 · G6 · Cmaj7 · Am7 (last phrase F · G6 · C · Csus2) | Chapter 7, golden-hour amber at night. Twinkling 16th-note FM bell arpeggios with gaps, a muted-pluck eighth pulse, light syncopated bass, very soft kick and shaker (from bar 5), kalimba melody |
| `ch8.wav` | Count | 100 | 28 | **67.2000 s** | 2 963 520 | C major / A minor: F · G · Em · Am / C · G · Am · F | Finale: layered 16th plucks + 8th bell arps, soft four-on-the-floor kick, pulsing bass, wide pad |
| `ch9.wav` | Pair | 70 | 20 | **68.5714 s** | 3 024 000 | A minor: Am · Dm · Em · Am / Am7 · F · Dm7 · Em | Sub-bass drone, dark low-passed pad, distant reverb-heavy plucks, low bells |

File sizes are 5.2 to 6.0 MB each (mono 44.1 kHz). Stereo would have doubled that, so the tracks are mono.

## Sound effects (`assets/audio/sfx/`)

Each file is trimmed of leading and trailing silence, starts with a 16-sample
fade-in and ends with a 6 ms fade-out.

| File | Purpose | Duration | Peak (dBFS) | Notes |
|---|---|---|---|---|
| `pop.wav` | Target pop | 0.595 s | -3 | Marimba/kalimba bar at **C5 = 523.25 Hz** (FFT-verified, error < 0.01 Hz). Only harmonic partials (1, 2, 4, 10), so it stays in tune at any `pitch_scale` (0.5x to 2.5x), plus a soft bubble/click transient. |
| `bounce.wav` | Orb hits wall | 0.120 s | -9 | Soft woody "tok" (low-passed) |
| `bounce_glass.wav` | Orb hits glass | 0.250 s | -4 | Short glassy "tink" at E6 |
| `glass_break.wav` | Glass pane shatters | 0.600 s | -4 | Scattered delicate tinkles and a light air burst; RMS kept low (-23 dBFS) |
| `bumper.wav` | Round bumper | 0.200 s | -4 | Springy blip, pitch bends up |
| `portal.wav` | Enters portal | 0.344 s | -4 | Airy noise through a rising resonant band-pass sweep |
| `absorb.wav` | Void block swallows orb | 0.400 s | -3 | Low "thoom" falling 165 Hz to 55 Hz |
| `split.wav` | Prism split | 0.350 s | -4 | Chorused G6/C7 "shing" with air |
| `shield.wav` | Armour shield cracks | 0.250 s | -4 | Soft metallic clink (inharmonic partials) |
| `launch.wav` | Orb fired | 0.200 s | -4 | Airy "fwip" and a small low thump |
| `fizzle.wav` | Orb dissolves | 0.400 s | -5 | Descending pentatonic sparkle with fading hiss |
| `win.wav` | Level cleared | 1.600 s | -3 | Bell arpeggio C5-E5-G5-C6 over a soft C-major pad swell |
| `star.wav` | Star appears | 0.500 s | -3 | Bell ding at **C6 = 1046.5 Hz** (harmonic, re-pitchable) |
| `fail.wav` | Out of shots | 0.800 s | -5 | Gentle G4 to E4 two-note tone |
| `aim_tick.wav` | Aim adjust | 0.030 s | -18 | Tiny C7 tick |
| `ui_tap.wav` | Button tap | 0.060 s | -4 | Rounded click |
| `ui_back.wav` | Back / close | 0.070 s | -6 | Softer, lower click |
| `ui_toggle.wav` | Toggle | 0.100 s | -5 | Two-tone blip, A5 then E6 |
| `unlock.wav` | Unlock | 0.900 s | -3 | Rising pentatonic chime C6 to C7 with shimmer |
| `hint.wav` | Hint shown | 0.596 s | -5 | Soft tremolo shimmer cluster |
| `undo.wav` | Undo / rewind | 0.250 s | -5 | Reversed swoosh |

## Synthesis summary

- **Instruments:** additive kalimba and marimba, 2-operator FM bells, an FM
  electric piano with a short tine partial, an
  additive piano/pluck whose upper harmonics decay faster (sounds like a
  closing low-pass), detuned wavetable pads, sine sub-drone, pitch-swept sine
  kick and high-passed noise shaker.
- **Space:** an algorithmic diffuse reverb (seeded noise split into bands, with
  a separate RT60 per band and sparse early reflections) and a feedback delay
  with a low-pass in the loop. Both are computed as exact frequency-domain
  responses.
- **Composition:** fixed chord progressions. Melodies are generated with a
  seeded RNG: chord tones on strong beats, C-major pentatonic or chord tones
  elsewhere, mostly stepwise, with rhythm motifs reused per phrase and timing
  and velocity humanised slightly.
