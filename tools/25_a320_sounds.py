#!/usr/bin/env python3
"""A320 pack sounds: fetch the verified CC0 / CC-BY recordings, cut them into loops / one-shots, audit.

  25_a320_sounds.py            audit (default): every shipped file is in manifest.json and SOURCES.md, sha256
                               matches, loops are seamless, size budget holds. Needs numpy only.
  25_a320_sounds.py --fetch    download the source recordings into data/raw/a320_sounds/<id>/ (own folder
                               each, never executed, sha256 pinned below; needs certifi from the venv).
  25_a320_sounds.py --build    cut the sources into game/aircraft/a320/sounds/*.wav + manifest.json
                               (needs numpy, scipy, soundfile: tools/.venv/bin/pip install soundfile).

Licence rules (user decision): only recordings whose own file page says CC0 or CC-BY, listed file by file
in game/aircraft/a320/sounds/SOURCES.md, CREDITS.md and docs/LICENSING.md. Nothing from the A320-family
upstream Sounds/ folder. Nothing is synthesised: every output is a trimmed / filtered / resampled /
normalised cut of a real recording (the edits are in EDITS below and in SOURCES.md).
Run with tools/.venv/bin/python (system python lacks certificates).
"""
import hashlib
import json
import os
import re
import sys
import wave
from math import gcd

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw", "a320_sounds")
OUT = os.path.join(ROOT, "game", "aircraft", "a320", "sounds")
MANIFEST = os.path.join(OUT, "manifest.json")
SOURCES_MD = os.path.join(OUT, "SOURCES.md")
RATE = 44100
MAX_BYTES = 30 * 1024 * 1024
C = "https://upload.wikimedia.org/wikipedia/commons/"

# id -> where the original comes from. Licence read on the file's own page on 2026-10-28.
SRC = {
    "draken": dict(
        key="WWS_SaabJ35DDrakenstartengineandtaxiing",
        file="draken_start.ogg", url=C + "4/49/WWS_SaabJ35DDrakenstartengineandtaxiing.ogg",
        sha256="4162d7c726e51f507b953bcfd032e70d91e0aaee2f0ac593d9192d9442c084e4"),
    "lax": dict(
        key="lax-airport-landing-sound",
        file="lax_landing.ogg", url="https://opengameart.org/sites/default/files/LAX%20Aiport%20Landing%20Sound%20Two.ogg",
        sha256="4ff92b863b2d45912e486ea86bc1fc2d24fc8cf1b6b079c9bcd8ac6c6ee9c985"),
    "ac_hum2": dict(
        key="Air_conditioner_hum_2",
        file="ac_hum2.wav", url=C + "d/dc/Air_conditioner_hum_2_%28Gravity_Sound%29.wav",
        sha256="bb9e9358e2b7041cab8f35d93e712727ddccc3490d075ef907b0923bbb0a1861"),
    "pump": dict(
        key="WWS_Pump",
        file="wws_pump.ogg", url=C + "2/2f/WWS_Pump.ogg",
        sha256="bb9a5cf5c61f007af37345ba3c8b9c83acf2fa9d1eee8c53d2276ba46899653d"),
    "hoist": dict(
        key="WWS_Hoist",
        file="wws_hoist.ogg", url=C + "2/24/WWS_Hoist.ogg",
        sha256="57b2f05c4218b669fa30ab56883eafec86e6989a4c9bdc37f8b6784b0dcd5742"),
    "chime": dict(
        key="Airplane_Chime_Sound_Effect",
        file="chime.ogg", url=C + "c/ce/Airplane_Chime_Sound_Effect.ogg",
        sha256="cce5b73c814b7f8c501d0370ce27995c28fe2e6c2bed06547208cba00f285c2b"),
}

# out file -> recipe. loop: crossfade seconds (a seamless loop is made of the cut); fade: (in, out) seconds.
# hp / lp: Butterworth cut-off Hz (4th order). peak: normalise to this dBFS peak.
EDITS = {
    "eng_idle_loop.wav": dict(src="draken", t=(70.0, 82.0), loop=1.5, peak=-3),
    "eng_power_loop.wav": dict(src="draken", t=(104.0, 118.0), loop=2.0, peak=-3),
    "eng_whine_loop.wav": dict(src="draken", t=(104.0, 118.0), loop=2.0, hp=1800.0, peak=-3),
    "eng_start.wav": dict(src="draken", t=(3.0, 20.0), fade=(0.4, 1.5), peak=-3),
    "eng_shutdown.wav": dict(src="draken", t=(118.0, 134.0), fade=(0.05, 1.5), peak=-3),
    "eng_reverse.wav": dict(src="lax", t=(34.0, 47.0), fade=(2.0, 3.0), peak=-3),
    "packs_loop.wav": dict(src="ac_hum2", t=(0.0, 18.0), loop=2.0, peak=-3),
    "hyd_pump_loop.wav": dict(src="pump", t=(4.0, 13.0), loop=1.5, peak=-3),
    "gear_motion_loop.wav": dict(src="hoist", t=(18.0, 30.0), loop=1.5, peak=-3),
    "chime.wav": dict(src="chime", t=(0.0, 2.9), fade=(0.0, 0.05), peak=-3),
}
LOOPS = [k for k, v in EDITS.items() if "loop" in v]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def src_path(i):
    return os.path.join(RAW, i, SRC[i]["file"])


def fetch():
    import ssl
    import urllib.request
    import certifi
    ctx = ssl.create_default_context(cafile=certifi.where())
    for i, s in SRC.items():
        os.makedirs(os.path.join(RAW, i), exist_ok=True)
        p = src_path(i)
        if not os.path.exists(p):
            req = urllib.request.Request(s["url"], headers={"User-Agent": "libresim-sound-fetch/1.0 (libresim project; siddharth@fossunited.org)"})
            with urllib.request.urlopen(req, timeout=120, context=ctx) as r, open(p, "wb") as f:
                f.write(r.read())
        ok = sha256(p) == s["sha256"]
        print(("ok   " if ok else "HASH MISMATCH ") + i, os.path.getsize(p))
        if not ok:
            sys.exit(1)


def read_mono(i):
    import soundfile as sf
    x, sr = sf.read(src_path(i), always_2d=True)
    return x.mean(axis=1), sr


def cut(x, sr, t0, t1):
    return x[int(t0 * sr):int(t1 * sr)].copy()


def resample(x, sr):
    from scipy.signal import resample_poly
    if sr == RATE:
        return x
    g = gcd(RATE, sr)
    return resample_poly(x, RATE // g, sr // g)


def filt(x, kind, hz):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(4, hz, btype=kind, fs=RATE, output="sos"), x)


def make_loop(x, xf_s):
    """Cross-fade the tail onto the head (equal power): the cut becomes N - xf samples and its last
    sample continues straight into its first."""
    xf = int(xf_s * RATE)
    n = len(x) - xf
    t = np.linspace(0.0, 1.0, xf, endpoint=False)
    out = x[:n].copy()
    out[:xf] = x[:xf] * np.sin(t * np.pi / 2) + x[n:] * np.cos(t * np.pi / 2)
    return out


def write_wav(path, x):
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        n, ch, sr, sw = w.getnframes(), w.getnchannels(), w.getframerate(), w.getsampwidth()
        raw = w.readframes(n)
    assert sw == 2, "16-bit expected"
    x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    return x.reshape(-1, ch).mean(axis=1), sr, ch


def build():
    os.makedirs(OUT, exist_ok=True)
    man = {}
    cache = {}
    for name, e in EDITS.items():
        if e["src"] not in cache:
            cache[e["src"]] = read_mono(e["src"])
        x, sr = cache[e["src"]]
        x = resample(cut(x, sr, *e["t"]), sr)
        x = x - x.mean()  # no DC
        if "hp" in e:
            x = filt(x, "highpass", e["hp"])
        if "lp" in e:
            x = filt(x, "lowpass", e["lp"])
        if "loop" in e:
            x = make_loop(x, e["loop"])
        if "fade" in e:
            a, b = int(e["fade"][0] * RATE), int(e["fade"][1] * RATE)
            if a:
                x[:a] *= np.linspace(0.0, 1.0, a)
            if b:
                x[-b:] *= np.linspace(1.0, 0.0, b)
        x = x * (10 ** (e["peak"] / 20) / max(np.abs(x).max(), 1e-9))
        write_wav(os.path.join(OUT, name), x)
        man[name] = dict(src=e["src"], edit={k: v for k, v in e.items() if k != "src"},
                         sha256=sha256(os.path.join(OUT, name)), frames=len(x), rate=RATE,
                         loop="loop" in e)
        print("built", name, round(len(x) / RATE, 2), "s")
    with open(MANIFEST, "w") as f:
        json.dump(dict(sources={i: dict(url=s["url"], sha256=s["sha256"]) for i, s in SRC.items()}, files=man), f, indent=1)


def seam(x):
    """Jump at the loop point relative to the typical sample step (1.0 = as smooth as the signal itself)."""
    step = np.abs(np.diff(x[:2000])).mean() + np.abs(np.diff(x[-2000:])).mean()
    return abs(x[0] - x[-1]) / max(step / 2, 1e-6)


def audit():
    errs = []
    if not os.path.exists(MANIFEST):
        print("no manifest.json (run --build)")
        sys.exit(1)
    man = json.load(open(MANIFEST))["files"]
    md = open(SOURCES_MD).read() if os.path.exists(SOURCES_MD) else ""
    on_disk = sorted(f for f in os.listdir(OUT) if f.endswith((".wav", ".ogg")))
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in on_disk)
    for f in on_disk:
        if f not in man:
            errs.append(f"{f}: on disk but not in manifest.json")
    for f, m in man.items():
        p = os.path.join(OUT, f)
        if not os.path.exists(p):
            errs.append(f"{f}: in manifest but missing")
            continue
        if sha256(p) != m["sha256"]:
            errs.append(f"{f}: sha256 differs from manifest")
        x, sr, ch = read_wav(p)
        if sr != m["rate"] or len(x) != m["frames"]:
            errs.append(f"{f}: rate/frames differ")
        if not re.search(re.escape(f), md):
            errs.append(f"{f}: not listed in SOURCES.md")
        peak = np.abs(x).max()
        if peak < 0.05 or peak > 0.999:
            errs.append(f"{f}: peak {peak:.3f} out of range")
        if m["loop"]:
            s = seam(x)
            if s > 8.0 or len(x) / sr < 3.0:
                errs.append(f"{f}: loop seam jump {s:.1f}x the sample step / too short")
            print(f"loop {f:24s} {len(x) / sr:5.1f}s seam={s:4.1f}x")
    for i, s in SRC.items():
        if s["key"] not in md:
            errs.append(f"source {i}: page ({s['key']}) not credited in SOURCES.md")
    for i, s in man_sources().items():
        if SRC[i]["sha256"] != s["sha256"]:
            errs.append(f"source {i}: manifest source hash differs from the script's")
    print(f"{len(on_disk)} files, {total / 1e6:.1f} MB (budget {MAX_BYTES / 1e6:.0f} MB)")
    if total > MAX_BYTES:
        errs.append("over size budget")
    for e in errs:
        print("FAIL", e)
    sys.exit(1 if errs else 0)


def man_sources():
    return json.load(open(MANIFEST))["sources"]


if __name__ == "__main__":
    a = sys.argv[1] if len(sys.argv) > 1 else ""
    if a == "--fetch":
        fetch()
    elif a == "--build":
        build()
    else:
        audit()
