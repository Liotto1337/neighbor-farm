#!/usr/bin/env python3
"""Synthesizes all game audio into res://audio/ (16-bit mono WAV).

Standard library only and deterministic (fixed seeds), so the files can be regenerated:
    python3 tools/make_audio.py

With the optional `soundfile` module installed (pip install soundfile numpy) the ambient loop is
written as a compact ambient.ogg; otherwise as ambient.wav with a 'smpl' loop chunk, which
Godot's WAV importer picks up ("Loop Mode: Detect From WAV"). The game loads whichever exists
and forces looping either way.
"""
import math
import os
import random
import struct

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
SR = 44100
SR_AMB = 22050
TAU = math.tau


# ---------------------------------------------------------------- output

def write_ogg(name, samples, sr, peak=0.8):
    """Returns False when soundfile is not available."""
    try:
        import numpy
        import soundfile
    except ImportError:
        return False
    data = numpy.array(samples)
    data *= peak / max(1e-9, float(numpy.abs(data).max()))
    soundfile.write(os.path.join(OUT_DIR, name + ".ogg"), data, sr, format="OGG", subtype="VORBIS")
    print("%-14s %5.2f s (ogg)" % (name, len(samples) / sr))
    return True


def write_wav(name, samples, sr, peak=0.89, loop=False):
    top = max(1e-9, max(abs(x) for x in samples))
    gain = peak / top
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, x * gain)) * 32767)) for x in samples)
    chunks = [b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16)]
    chunks.append(b"data" + struct.pack("<I", len(frames)) + frames)
    if loop:
        # smpl chunk: one forward loop over the whole buffer (end is inclusive).
        smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(samples) - 1, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    body = b"WAVE" + b"".join(chunks)
    with open(os.path.join(OUT_DIR, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)
    print("%-14s %5.2f s" % (name, len(samples) / sr))


# ---------------------------------------------------------------- building blocks

def buf(seconds, sr=SR):
    return [0.0] * int(seconds * sr)


def mix(dst, src, at_seconds=0.0, gain=1.0, sr=SR):
    start = int(at_seconds * sr)
    for i in range(min(len(src), len(dst) - start)):
        dst[start + i] += src[i] * gain


def midi(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def tone(freq_from, freq_to, seconds, attack=0.004, decay=0.1, sr=SR, harmonics=((1, 1.0),)):
    """Sine (plus optional harmonics) with an exponential pitch glide and attack/exp-decay envelope."""
    n = int(seconds * sr)
    out = [0.0] * n
    phase = 0.0
    ratio = freq_to / freq_from
    for i in range(n):
        t = i / sr
        f = freq_from * ratio ** (t / seconds)
        phase += TAU * f / sr
        env = min(1.0, t / attack) * math.exp(-t / decay)
        out[i] = env * sum(a * math.sin(phase * h) for h, a in harmonics)
    return out


def partial_voice(freq, seconds, partials, attack=0.002, sr=SR):
    """Struck bar/bell: (ratio, amplitude, decay seconds) partials."""
    n = int(seconds * sr)
    out = [0.0] * n
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f >= sr * 0.45:
            continue
        w = TAU * f / sr
        for i in range(n):
            t = i / sr
            out[i] += amp * min(1.0, t / attack) * math.exp(-t / decay) * math.sin(w * i)
    return out


def marimba(freq, seconds=0.6, decay=0.35):
    return partial_voice(freq, seconds, ((1.0, 1.0, decay), (3.93, 0.22, decay * 0.25), (9.2, 0.05, decay * 0.08)))


def bell(freq, seconds=1.2, decay=0.5):
    return partial_voice(freq, seconds, ((1.0, 1.0, decay), (2.0, 0.35, decay * 0.6), (3.01, 0.18, decay * 0.4),
                                         (4.17, 0.1, decay * 0.25), (5.43, 0.05, decay * 0.15)))


def noise(seconds, rng, sr=SR):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * sr))]


def lowpass(x, cutoff, sr=SR):
    a = 1.0 - math.exp(-TAU * cutoff / sr)
    y, out = 0.0, [0.0] * len(x)
    for i, v in enumerate(x):
        y += a * (v - y)
        out[i] = y
    return out


def highpass(x, cutoff, sr=SR):
    low = lowpass(x, cutoff, sr)
    return [a - b for a, b in zip(x, low)]


def bandpass(x, center_from, center_to=None, q=1.2, sr=SR):
    """RBJ band-pass biquad; the centre frequency may sweep exponentially."""
    center_to = center_to or center_from
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    n = len(x)
    for i, v in enumerate(x):
        f = center_from * (center_to / center_from) ** (i / max(1, n - 1))
        w = TAU * f / sr
        alpha = math.sin(w) / (2.0 * q)
        a0 = 1.0 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2.0 * math.cos(w) / a0, (1.0 - alpha) / a0
        y = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


def shape(x, attack, decay, sr=SR):
    return [v * min(1.0, (i / sr) / attack) * math.exp(-(i / sr) / decay) for i, v in enumerate(x)]


def reverb(x, wet=0.25, room=1.0, sr=SR, circular=False):
    """Small Schroeder reverb. circular=True treats x as a loop (tail wraps to the start)."""
    combs = [0.0297, 0.0371, 0.0411, 0.0437]
    allpasses = [0.005, 0.0017]
    passes = 2 if circular else 1
    n = len(x)
    src = x * passes if circular else x + [0.0] * int(sr * 1.2 * room)
    total = [0.0] * len(src)
    for d in combs:
        size = int(d * sr * room)
        line = [0.0] * size
        fb, damp, last, j = 0.78, 0.3, 0.0, 0
        for i, v in enumerate(src):
            out = line[j]
            last = out * (1.0 - damp) + last * damp
            line[j] = v + last * fb
            j = (j + 1) % size
            total[i] += out
    for d in allpasses:
        size = int(d * sr)
        line = [0.0] * size
        j = 0
        for i, v in enumerate(total):
            delayed = line[j]
            line[j] = v + delayed * 0.5
            total[i] = delayed - v * 0.5
            j = (j + 1) % size
    if circular:
        return [x[i] * (1.0 - wet) + total[n + i] * wet / len(combs) for i in range(n)]
    dry = x + [0.0] * (len(total) - n)
    return [d * (1.0 - wet) + w * wet / len(combs) for d, w in zip(dry, total)]


def fade_tail(x, seconds=0.02, sr=SR):
    n = min(len(x), int(seconds * sr))
    for i in range(n):
        x[len(x) - 1 - i] *= i / n
    return x


def trim(x, threshold=1e-4):
    top = max(abs(v) for v in x)
    end = len(x)
    while end > 1 and abs(x[end - 1]) < top * threshold:
        end -= 1
    return fade_tail(x[:end])


# ---------------------------------------------------------------- UI sounds

def sfx_click(rng):
    out = tone(1500, 900, 0.05, attack=0.001, decay=0.009)
    mix(out, shape(highpass(noise(0.01, rng), 2000), 0.0005, 0.002), gain=0.25)
    return trim(lowpass(out, 6000))


def sfx_tab(rng):
    out = marimba(midi(79), 0.25, decay=0.07)
    mix(out, marimba(midi(86), 0.2, decay=0.05), 0.035, 0.45)
    return trim(reverb(out, wet=0.15, room=0.6))


def sfx_modal_open(rng):
    out = buf(0.7)
    swoosh = shape(bandpass(noise(0.22, rng), 500, 2400, q=1.5), 0.12, 0.06)
    mix(out, swoosh, gain=0.5)
    mix(out, bell(midi(84), 0.6, decay=0.18), 0.09, 0.35)
    mix(out, bell(midi(91), 0.5, decay=0.12), 0.13, 0.18)
    return trim(reverb(out, wet=0.25, room=0.8))


def sfx_modal_close(rng):
    out = buf(0.5)
    swoosh = shape(bandpass(noise(0.18, rng), 2000, 450, q=1.5), 0.03, 0.06)
    mix(out, swoosh, gain=0.5)
    mix(out, marimba(midi(72), 0.3, decay=0.08), 0.05, 0.35)
    return trim(reverb(out, wet=0.2, room=0.7))


def sfx_deny(rng):
    out = buf(0.35)
    for at in (0.0, 0.11):
        mix(out, tone(240, 200, 0.12, attack=0.004, decay=0.04, harmonics=((1, 1.0), (3, 0.2), (5, 0.06))), at)
    return trim(lowpass(out, 1800))


# ---------------------------------------------------------------- tile sounds

def sfx_plow(rng):
    out = buf(0.35)
    for at, cut in ((0.0, 900), (0.045, 1300), (0.09, 700)):
        grain = shape(lowpass(noise(0.09, rng), cut), 0.002, 0.025)
        mix(out, grain, at, 0.9)
    mix(out, tone(120, 55, 0.12, attack=0.002, decay=0.04), 0.0, 0.8)
    return trim(out)


def sfx_plant(rng):
    out = tone(380, 1000, 0.12, attack=0.003, decay=0.045, harmonics=((1, 1.0), (2, 0.15)))
    mix(out, shape(lowpass(noise(0.03, rng), 2500), 0.001, 0.008), gain=0.35)
    mix(out, marimba(midi(88), 0.25, decay=0.05), 0.05, 0.15)
    return trim(reverb(out, wet=0.15, room=0.5))


def sfx_harvest(rng):
    out = buf(0.9)
    rustle = bandpass(noise(0.18, rng), 3200, 2200, q=0.9)
    rustle = [v * (0.6 + 0.4 * math.sin(i / SR * TAU * 45)) for i, v in enumerate(shape(rustle, 0.01, 0.05))]
    mix(out, rustle, gain=0.55)
    mix(out, marimba(midi(76), 0.5, decay=0.14), 0.02, 0.6)
    mix(out, marimba(midi(83), 0.5, decay=0.16), 0.09, 0.5)
    return trim(reverb(out, wet=0.22, room=0.7))


def sfx_clear(rng):
    out = buf(0.5)
    rustle = shape(bandpass(noise(0.3, rng), 1800, 1100, q=0.8), 0.01, 0.09)
    rustle = [v * (0.5 + 0.5 * abs(math.sin(i / SR * TAU * 23))) for i, v in enumerate(rustle)]
    mix(out, rustle, gain=0.8)
    for at in (0.03, 0.12):
        mix(out, shape(lowpass(noise(0.05, rng), 1500), 0.001, 0.015), at, 0.6)
    return trim(out)


def sfx_tock(rng):
    out = marimba(midi(64), 0.3, decay=0.06)
    mix(out, marimba(midi(57), 0.3, decay=0.08), 0.0, 0.5)
    return trim(out)


# ---------------------------------------------------------------- rewards

def sfx_coin(rng):
    out = buf(1.0)
    mix(out, bell(midi(91), 0.8, decay=0.22), 0.0, 0.7)
    mix(out, bell(midi(96), 0.9, decay=0.3), 0.07, 0.8)
    return trim(reverb(out, wet=0.2, room=0.6))


def sfx_build(rng):
    out = buf(0.7)
    for k, at in enumerate((0.0, 0.14, 0.28)):
        knock = partial_voice(midi(55 + k * 2), 0.2, ((1.0, 1.0, 0.04), (2.76, 0.5, 0.025), (5.4, 0.25, 0.012)))
        mix(out, knock, at, 0.8)
        mix(out, shape(lowpass(noise(0.03, rng), 3000), 0.0005, 0.006), at, 0.3)
    return trim(reverb(out, wet=0.2, room=0.7))


def sfx_level_up(rng):
    out = buf(2.4)
    for k, note in enumerate((72, 76, 79, 84, 88)):
        mix(out, bell(midi(note), 1.4, decay=0.45), k * 0.09, 0.55)
    for note in (72, 76, 79, 84):
        pad = tone(midi(note), midi(note), 1.6, attack=0.15, decay=0.6, harmonics=((1, 1.0), (2, 0.2)))
        mix(out, pad, 0.45, 0.12)
    sparkle = shape(highpass(noise(1.2, rng), 7000), 0.3, 0.3)
    mix(out, sparkle, 0.4, 0.05)
    return trim(reverb(out, wet=0.3, room=1.1))


def sfx_expand(rng):
    out = buf(2.2)
    scale = (72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96)
    for k, note in enumerate(scale):
        mix(out, bell(midi(note), 1.0, decay=0.3), k * 0.045, 0.35 + 0.02 * k)
    mix(out, shape(highpass(noise(0.8, rng), 6000), 0.2, 0.25), 0.1, 0.06)
    return trim(reverb(out, wet=0.35, room=1.2))


# ---------------------------------------------------------------- ambience

def wavetable(harmonics, size=2048):
    return [sum(a * math.sin(TAU * h * i / size) for h, a in harmonics) for i in range(size)]


def ambient(rng):
    """Warm 4-chord pad + sparse kalimba + soft wind, a seamless 48 s loop."""
    sr = SR_AMB
    chord_seconds, overlap = 12.0, 6.0
    chords = [
        (48, 55, 59, 62, 64),  # Cmaj9
        (45, 52, 55, 59, 60),  # Am9
        (41, 48, 52, 57, 60),  # Fmaj9 (no 9th in the bass voicing)
        (43, 50, 55, 57, 62),  # G6/9
    ]
    loop = chord_seconds * len(chords)
    xfade = 4.0
    n_loop, n_x = int(loop * sr), int(xfade * sr)
    table = wavetable(((1, 1.0), (2, 0.22), (3, 0.07), (4, 0.025)))
    size = len(table)
    pad = [0.0] * (n_loop + n_x)
    half = overlap / 2.0
    for k, chord in enumerate(chords):
        start = k * chord_seconds
        for v, note in enumerate(chord):
            amp = 0.9 if v == 0 else 0.55
            for cents in (-4.0, 4.0):
                f = midi(note) * 2.0 ** (cents / 1200.0)
                step = f * size / sr
                trem_rate = rng.uniform(0.07, 0.2)
                trem_phase = rng.uniform(0.0, TAU)
                phase = rng.uniform(0.0, size)
                for i in range(len(pad)):
                    t = i / sr
                    u = (t - start + loop / 2.0) % loop - loop / 2.0
                    if u < -half or u > chord_seconds + half:
                        phase += step
                        continue
                    if u < half:
                        env = math.sin(math.pi / 2.0 * (u + half) / overlap)
                    elif u > chord_seconds - half:
                        env = math.cos(math.pi / 2.0 * (u - chord_seconds + half) / overlap)
                    else:
                        env = 1.0
                    trem = 0.8 + 0.2 * math.sin(TAU * trem_rate * t + trem_phase)
                    pad[i] += amp * env * trem * table[int(phase) % size]
                    phase += step
    # Loop crossfade: blend the overshoot past the loop end into the start (equal power).
    out = pad[:n_loop]
    for i in range(n_x):
        w = math.sin(math.pi / 2.0 * i / n_x)
        out[i] = pad[i] * w + pad[n_loop + i] * math.cos(math.pi / 2.0 * i / n_x)
    out = lowpass(lowpass(out, 1600, sr), 2400, sr)

    # Kalimba: chord tones an octave or two up, at loose random moments, echoed around the loop.
    plucks = [0.0] * n_loop
    t = 1.0
    while t < loop - 0.5:
        chord = chords[int(t // chord_seconds) % len(chords)]
        note = rng.choice(chord[1:]) + rng.choice((12, 24))
        voice = partial_voice(midi(note), 2.5, ((1.0, 1.0, 0.7), (2.0, 0.12, 0.3), (5.4, 0.06, 0.08)), attack=0.004, sr=sr)
        vel = rng.uniform(0.12, 0.26)
        for echo in range(4):
            at = int((t + echo * 0.48) * sr)
            g = vel * 0.38 ** echo
            for i, v in enumerate(voice):
                plucks[(at + i) % n_loop] += v * g
        t += rng.uniform(1.4, 3.8)
    peak_pad = max(abs(v) for v in out)
    peak_pl = max(abs(v) for v in plucks) or 1.0
    out = [a / peak_pad + b / peak_pl * 0.45 for a, b in zip(out, plucks)]

    # Wind: low-passed noise with slow swells, filtered twice around the loop so the seam is clean.
    white = noise(loop, rng, sr)
    wind = lowpass(white * 2, 350, sr)[n_loop:]
    wind = lowpass(wind * 2, 500, sr)[n_loop:]
    peak_w = max(abs(v) for v in wind)
    for i in range(n_loop):
        swell = 0.55 + 0.45 * math.sin(TAU * 2.0 * i / n_loop) * math.sin(TAU * 3.0 * i / n_loop + 1.0)
        out[i] += wind[i] / peak_w * 0.12 * swell
    return reverb(out, wet=0.3, room=1.4, sr=sr, circular=True)


def bird(rng, pattern):
    """A short phrase of chirps: each a fast frequency sweep with a little trill."""
    sr = SR_AMB
    out = [0.0] * int(2.0 * sr)
    t = 0.05
    for f0, f1, dur, gap in pattern:
        n = int(dur * sr)
        phase = 0.0
        trill = rng.uniform(25, 45)
        start = int(t * sr)
        for i in range(n):
            u = i / n
            f = f0 + (f1 - f0) * u + 180.0 * math.sin(TAU * trill * i / sr)
            phase += TAU * f / sr
            env = math.sin(math.pi * u) ** 1.5
            if start + i < len(out):
                out[start + i] += env * math.sin(phase)
        t += dur + gap
    return trim(reverb(lowpass(out, 6000, sr), wet=0.3, room=1.0, sr=sr))


BIRDS = [
    [(2900, 4100, 0.07, 0.05), (2900, 4100, 0.07, 0.05), (3300, 2600, 0.16, 0.0)],
    [(3800, 3200, 0.05, 0.03)] * 5 + [(4200, 3000, 0.12, 0.0)],
    [(2400, 3400, 0.12, 0.12), (3400, 2600, 0.18, 0.0)],
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    sfx = {
        "click": sfx_click, "tab": sfx_tab, "modal_open": sfx_modal_open, "modal_close": sfx_modal_close,
        "deny": sfx_deny, "plow": sfx_plow, "plant": sfx_plant, "harvest": sfx_harvest, "clear": sfx_clear,
        "tock": sfx_tock, "coin": sfx_coin, "build": sfx_build, "level_up": sfx_level_up, "expand": sfx_expand,
    }
    for seed, (name, fn) in enumerate(sorted(sfx.items())):
        write_wav(name, fn(random.Random(seed + 1)), SR)
    for k, pattern in enumerate(BIRDS):
        write_wav("bird_%d" % (k + 1), bird(random.Random(100 + k), pattern), SR_AMB, peak=0.7)
    loop = ambient(random.Random(7))
    for stale in ("ambient.ogg", "ambient.wav"):
        if os.path.exists(os.path.join(OUT_DIR, stale)):
            os.remove(os.path.join(OUT_DIR, stale))
    if not write_ogg("ambient", loop, SR_AMB):
        write_wav("ambient", loop, SR_AMB, peak=0.8, loop=True)


if __name__ == "__main__":
    main()
