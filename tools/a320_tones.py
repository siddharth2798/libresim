#!/usr/bin/env python3
"""Original A320 stall horn and lite GPWS tones. Libresim's own work.

Writes 16-bit mono WAVs into game/aircraft/a320/sounds/ using the stdlib only
(wave + math). No upstream audio, and not a copy of a Honeywell or Airbus GPWS
voice or the Airbus autopilot cavalry charge: a beating two-tone loop, one soft
blip, and two double beeps at different pitches.

  python3 tools/a320_tones.py
"""
import array
import hashlib
import math
import os
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "aircraft", "a320", "sounds")
RATE = 44100
PEAK = 10 ** (-3.0 / 20.0)  # -3 dBFS, same peak as the recording cuts
MAX_BYTES = 100 * 1024


def _stall(t):
    # 0.40 s holds an integer number of cycles of each tone, so the loop joins.
    return (math.sin(2.0 * math.pi * 480.0 * t)
            + math.sin(2.0 * math.pi * 487.5 * t)
            + 0.22 * math.sin(2.0 * math.pi * 960.0 * t))


def _env(t, t0, dur, attack, release):
    u = t - t0
    if u < 0.0 or u > dur:
        return 0.0
    return min(1.0, u / attack) * min(1.0, (dur - u) / release)


def _alt(t):
    dur = 0.20
    if t >= dur:
        return 0.0
    attack = min(1.0, t / 0.012)
    release = min(1.0, (dur - t) / 0.018)
    return attack * release * math.exp(-3.6 * t / dur) * math.sin(2.0 * math.pi * 932.0 * t)


def _odd(t, freq):
    return sum(math.sin(2.0 * math.pi * freq * k * t) / k for k in (1, 3, 5, 7))


def _sink(t):
    gate = _env(t, 0.02, 0.09, 0.004, 0.012) + _env(t, 0.16, 0.09, 0.004, 0.012)
    return gate * _odd(t, 196.0)


def _ap(t):
    gate = _env(t, 0.012, 0.046, 0.004, 0.008) + _env(t, 0.088, 0.046, 0.004, 0.008)
    return gate * math.sin(2.0 * math.pi * 1480.0 * t)


def _render(seconds, fn):
    n = int(round(RATE * seconds))
    return [fn(i / RATE) for i in range(n)]


def _write(name, samples):
    peak = max(abs(x) for x in samples)
    if peak < 1e-6:
        raise SystemExit("%s is silent" % name)
    scale = PEAK / peak * 32767.0
    pcm = array.array("h", (max(-32767, min(32767, int(round(x * scale)))) for x in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    return path


def _seam(samples):
    step = sum(abs(samples[i + 1] - samples[i]) for i in range(len(samples) - 1)) / (len(samples) - 1)
    return abs(samples[0] - samples[-1]) / max(step, 1e-9)


def main():
    tones = {
        "stall_horn_loop.wav": _render(0.40, _stall),
        "gpws_alt.wav": _render(0.20, _alt),
        "gpws_sink.wav": _render(0.28, _sink),
        "gpws_ap.wav": _render(0.16, _ap),
    }
    if _seam(tones["stall_horn_loop.wav"]) > 3.0:
        raise SystemExit("stall loop does not join")
    digests = set()
    for name, samples in tones.items():
        path = _write(name, samples)
        size = os.path.getsize(path)
        if size > MAX_BYTES:
            raise SystemExit("%s is %d bytes" % (name, size))
        digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if digest in digests:
            raise SystemExit("%s duplicates another tone" % name)
        digests.add(digest)
        print("%s  %d bytes  %.3f s" % (name, size, len(samples) / RATE))


if __name__ == "__main__":
    main()
