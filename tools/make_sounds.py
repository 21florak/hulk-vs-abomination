#!/usr/bin/env python3
"""Synthesizes the game's original sound effects (no samples, no copyrighted audio).

Writes .ogg files (Roblox accepts .ogg and .mp3 uploads) into sounds/:
  roar, smash, stomp, heartbeat (loop), ambience (loop), alarm (loop), scream (stinger), thunder

Usage: python3 tools/make_sounds.py        (needs numpy and ffmpeg)
"""
import pathlib
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "sounds"
rng = np.random.default_rng(2008)


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def band(signal, low, high):
    """Brick-wall band-pass via FFT (fine for sound design)."""
    spectrum = np.fft.rfft(signal)
    freqs = np.fft.rfftfreq(len(signal), 1 / RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0
    return np.fft.irfft(spectrum, len(signal))


def osc(freq_curve, shape="saw"):
    """Oscillator following a per-sample frequency curve."""
    phase = np.cumsum(freq_curve) / RATE
    if shape == "sine":
        return np.sin(2 * np.pi * phase)
    if shape == "square":
        return np.sign(np.sin(2 * np.pi * phase))
    return 2 * (phase % 1) - 1  # saw


def envelope(n, attack, release, total):
    env = np.ones(n)
    a, r = int(attack * RATE), int(release * RATE)
    if a:
        env[:a] = np.linspace(0, 1, a)
    if r:
        env[-r:] *= np.linspace(1, 0, r) ** 1.5
    return env[: int(total * RATE)]


def normalize(x, peak=0.92):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def loop_crossfade(x, seconds=1.5):
    """Make a seamless loop by fading the tail into the head."""
    n = int(seconds * RATE)
    fade = np.linspace(0, 1, n)
    head, tail = x[:n], x[-n:]
    x = x[:-n].copy()
    x[:n] = head * fade + tail * (1 - fade)
    return x


# ---------------------------------------------------------------------------
def roar():
    d = 3.6
    tt = t(d)
    n = len(tt)
    # pitch rises into the roar, holds, then sags
    pitch = np.interp(tt, [0, 0.5, 2.4, d], [55, 92, 80, 45])
    jitter = 1 + 0.06 * band(rng.standard_normal(n), 5, 30) / 0.05
    growl = osc(pitch * jitter) + 0.7 * osc(pitch * 1.503 * jitter) + 0.5 * osc(pitch * 0.5)
    # throaty rattle: fast amplitude flutter
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * np.interp(tt, [0, d], [28, 18]) * tt) ** 2
    breath = band(rng.standard_normal(n), 250, 2600) * 0.9
    voice = growl * flutter + breath * np.interp(tt, [0, 0.4, d], [0.3, 1, 0.6])
    voice = band(voice, 35, 5000)
    voice = np.tanh(voice * 2.5)  # distortion = menace
    sub = np.sin(2 * np.pi * 38 * tt) * 0.6
    return normalize((voice + sub) * envelope(n, 0.35, 1.4, d))


def smash():
    d = 2.0
    tt = t(d)
    n = len(tt)
    thump_pitch = 70 * np.exp(-tt * 6) + 32
    thump = osc(thump_pitch, "sine") * np.exp(-tt * 4.5) * 1.4
    crack = band(rng.standard_normal(n), 900, 9000) * np.exp(-tt * 28) * 1.2
    crunch = band(rng.standard_normal(n), 200, 2500) * np.exp(-tt * 7) * 0.8
    debris = np.zeros(n)
    for _ in range(70):  # concrete chunks and rattling bits
        start = int(rng.uniform(0.08, 1.6) * RATE)
        length = int(rng.uniform(0.01, 0.06) * RATE)
        grain = band(rng.standard_normal(length + 64), 1500, 7000)[:length] * np.hanning(length)
        debris[start:start + length] += grain * rng.uniform(0.1, 0.5) * np.exp(-start / RATE * 1.4)
    return normalize(np.tanh((thump + crack + crunch + debris) * 1.6))


def stomp():
    d = 1.2
    tt = t(d)
    n = len(tt)
    pitch = 55 * np.exp(-tt * 9) + 28
    boom = osc(pitch, "sine") * np.exp(-tt * 5) * 1.5
    rumble = band(rng.standard_normal(n), 20, 220) * np.exp(-tt * 4) * 1.2
    grit = band(rng.standard_normal(n), 400, 2000) * np.exp(-tt * 30) * 0.4
    return normalize(np.tanh((boom + rumble + grit) * 1.3))


def heartbeat():
    d = 0.95
    tt = t(d)
    out = np.zeros(len(tt))
    for start, strength in ((0.0, 1.0), (0.26, 0.75)):  # lub-dub
        s = int(start * RATE)
        seg = t(0.22)
        beat = osc(48 * np.exp(-seg * 8) + 38, "sine") * np.exp(-seg * 16) * strength
        out[s:s + len(seg)] += beat
    out = band(out, 20, 300)
    return normalize(np.tanh(out * 2))


def ambience():
    d = 32
    tt = t(d)
    n = len(tt)
    drone = (np.sin(2 * np.pi * 41 * tt) + 0.8 * np.sin(2 * np.pi * 41.7 * tt) + 0.4 * np.sin(2 * np.pi * 82.3 * tt)) * 0.35
    drone *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.05 * tt)
    air = band(rng.standard_normal(n), 120, 900) * (0.25 + 0.15 * np.sin(2 * np.pi * 0.08 * tt + 1))
    groans = np.zeros(n)
    for _ in range(6):  # distant metal stress
        start = rng.uniform(1, d - 6)
        length = rng.uniform(2.0, 4.5)
        seg = t(length)
        f = rng.uniform(140, 320) * (1 - 0.25 * seg / length)
        groan = (osc(f, "saw") + osc(f * 1.41, "saw") * 0.6) * np.hanning(len(seg)) * 0.25
        groan = band(groan, 100, 1800)
        s = int(start * RATE)
        groans[s:s + len(seg)] += groan
    return normalize(loop_crossfade(drone + air + groans), 0.8)


def alarm():
    d = 2.4
    tt = t(d)
    freq = np.where((tt % 0.6) < 0.3, 620, 470)  # two-tone klaxon
    tone = osc(freq, "square") * 0.6 + osc(freq * 2, "saw") * 0.2
    tone = band(tone, 200, 4000)
    gate = np.clip(np.sin(np.pi * (tt % 0.3) / 0.3) * 4, 0, 1)
    return normalize(np.tanh(tone * gate * 1.5), 0.8)


def scream():
    """Jump-scare stinger: a dissonant cluster that shrieks and bends down, plus a hit."""
    d = 2.6
    tt = t(d)
    n = len(tt)
    bend = np.interp(tt, [0, 0.15, d], [1.0, 1.04, 0.82])
    cluster = sum(osc(f * bend * (1 + 0.004 * np.sin(2 * np.pi * 7 * tt + i)), "saw") for i, f in enumerate([880, 932, 988, 1245, 1319]))
    cluster = band(cluster, 400, 9000) * 0.5
    hit = band(rng.standard_normal(n), 60, 6000) * np.exp(-tt * 9) * 1.5
    sub = osc(60 * np.exp(-tt * 3) + 30, "sine") * np.exp(-tt * 3)
    return normalize(np.tanh((cluster + hit + sub) * 2) * envelope(n, 0.01, 1.2, d))


def thunder():
    d = 5.0
    tt = t(d)
    n = len(tt)
    crack = band(rng.standard_normal(n), 300, 6000) * np.exp(-tt * 10)
    rumble = band(rng.standard_normal(n), 20, 180) * (np.exp(-tt * 0.9) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.3 * tt) ** 2))
    return normalize(np.tanh((crack * 0.7 + rumble * 2.2) * 1.4) * envelope(n, 0.02, 1.5, d), 0.85)


SOUNDS = {
    "roar": roar,
    "smash": smash,
    "stomp": stomp,
    "heartbeat": heartbeat,
    "ambience": ambience,
    "alarm": alarm,
    "scream": scream,
    "thunder": thunder,
}


def write_ogg(name, samples):
    OUT.mkdir(exist_ok=True)
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = pathlib.Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        out = OUT / f"{name}.ogg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "6", str(out)], check=True)
    return out


if __name__ == "__main__":
    for name, make in SOUNDS.items():
        path = write_ogg(name, make())
        print(f"{path.name}: {path.stat().st_size // 1024} KB")
