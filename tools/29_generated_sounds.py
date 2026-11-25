#!/usr/bin/env python3
"""Generated aircraft sounds (libresim's own work, no upstream audio). See docs/AUDIO-PLAN.md.

Writes 16-bit mono 44.1 kHz WAVs, peak -3 dBFS, seeded (the same bytes every run):
  A320  game/aircraft/a320/sounds/
    ptu_bark_loop.wav        power transfer unit: bursts of a harsh low growl ("barking dog")
    apu_loop.wav             APU turbine whine + combustion rumble + intake rush (pitch follows apu/n_pct in game)
    master_warning_loop.wav  continuous repetitive chime (red warning), an original bell, not the Airbus sample
    master_caution.wav       single chime (amber caution)
    avionics_fan_loop.wav    cockpit avionics ventilation blower
  C172  game/aircraft/c172/sounds/
    tc_gyro_loop.wav         electric turn-coordinator gyro whine
  World game/world/sounds/
    diesel_loop.wav          ramp diesel (pushback tug, baggage tractor, GPU, bus) at idle: firing thumps and rattle
    car_loop.wav             petrol car engine at idle (follow-me car)
    jetway_motor_loop.wav    jetway drive motor whine and gearbox with its moving-warning beeper
    thunder.wav              thunder: crack and rolling rumble

Loops join seamlessly: tones hold a whole number of cycles in the loop, noise beds are cross-faded end into start.

  tools/.venv/bin/python tools/29_generated_sounds.py          # write all
  tools/.venv/bin/python tools/29_generated_sounds.py --check  # print length / peak / seam of each, write nothing
"""
import os
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A320 = os.path.join(ROOT, "game", "aircraft", "a320", "sounds")
C172 = os.path.join(ROOT, "game", "aircraft", "c172", "sounds")
WORLD = os.path.join(ROOT, "game", "world", "sounds")
RATE = 44100
PEAK = 10 ** (-3.0 / 20.0)


def _t(sec):
    return np.arange(int(round(sec * RATE))) / RATE


def _tone(f, t):
    return np.sin(2 * np.pi * f * t)


def _whole(f, sec):
    """f rounded so the loop of `sec` seconds holds a whole number of cycles."""
    return max(1, round(f * sec)) / sec


def _band(x, lo, hi):
    """Band-pass by FFT mask (soft edges); periodic, so a loop stays a loop."""
    spec = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / RATE)
    m = 1 / (1 + (lo / np.maximum(fr, 1e-3)) ** 4) / (1 + (fr / hi) ** 4)
    return np.fft.irfft(spec * m, len(x))


def _pink(n, rng):
    spec = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / RATE)
    spec /= np.sqrt(np.maximum(fr, 20.0))
    return np.fft.irfft(spec, n)


def _norm(x):
    x = x - x.mean()
    return x * (PEAK / max(np.abs(x).max(), 1e-9))


def _fades(x, attack=0.005, release=0.02):
    a, r = int(attack * RATE), int(release * RATE)
    x = x.copy()
    x[:a] *= np.linspace(0, 1, a)
    x[-r:] *= np.linspace(1, 0, r)
    return x


def _bell(f, t, decay):
    """An original two-partial chime with a soft strike."""
    env = np.exp(-t / decay) * np.minimum(1.0, t / 0.003)
    return env * (_tone(f, t) + 0.45 * _tone(f * 2.76, t) * np.exp(-t / (decay * 0.4)) + 0.2 * _tone(f * 5.4, t) * np.exp(-t / (decay * 0.2)))


def ptu_bark(rng):
    sec = 2.52
    t = _t(sec)
    out = np.zeros_like(t)
    starts = [0.0, 0.40, 0.86, 1.24, 1.68, 2.08]
    for i, s0 in enumerate(starts):
        dur = 0.17 + 0.03 * rng.random()
        u = t - s0
        on = (u >= 0) & (u < dur)
        uu = u[on]
        f0 = 92.0 + 6 * rng.random()
        ph = 2 * np.pi * np.cumsum(f0 * (1.0 - 0.18 * uu / dur)) / RATE  # pitch sags through the bark
        saw = 2 * ((ph / (2 * np.pi)) % 1.0) - 1
        growl = np.tanh(3.0 * (saw + 0.5 * np.sin(2 * ph)))
        env = np.minimum(1, uu / 0.012) * np.exp(-uu / (dur * 0.7)) * (1 - uu / dur) ** 0.5
        out[on] += growl * env * (0.85 + 0.15 * rng.random())
    rumble = _band(rng.standard_normal(len(t)), 40, 400) * 0.25  # the pump body between barks
    return _norm(_band(out, 50, 3500) + rumble)


def apu_loop(rng):
    sec = 4.0
    t = _t(sec)
    f1 = _whole(2150.0, sec)
    flutter = 1 + 0.06 * _tone(_whole(7.0, sec), t)
    whine = (_tone(f1, t) + 0.45 * _tone(2 * f1, t) + 0.25 * _tone(_whole(3300.0, sec), t)) * flutter
    rush = _band(_pink(len(t), rng), 500, 5000)
    rumble = _band(rng.standard_normal(len(t)), 30, 260)
    x = 0.22 * whine / np.abs(whine).max() + 0.5 * rush / np.abs(rush).max() + 0.6 * rumble / np.abs(rumble).max()
    return _norm(x)


def master_warning():
    sec = 1.0  # four strikes a second, decayed before the next: the loop joins
    t = _t(sec)
    out = np.zeros_like(t)
    for s0 in (0.0, 0.25, 0.5, 0.75):
        u = t - s0
        on = (u >= 0) & (u < 0.25)
        out[on] += _bell(1020.0, u[on], 0.05) * np.minimum(1, (0.25 - u[on]) / 0.01)
    return _norm(out)


def master_caution():
    t = _t(1.1)
    return _fades(_norm(_bell(760.0, t, 0.28)), 0.001, 0.05)


def avionics_fan(rng):
    sec = 6.0
    t = _t(sec)
    air = _band(_pink(len(t), rng), 250, 4500)
    bpf = _whole(186.0, sec)  # blade passing
    hum = _tone(bpf, t) + 0.4 * _tone(2 * bpf, t) + 0.15 * _tone(_whole(400.0, sec), t)
    x = air / np.abs(air).max() + 0.12 * hum / np.abs(hum).max()
    return _norm(x)


def tc_gyro(rng):
    sec = 2.0
    t = _t(sec)
    f = _whole(1580.0, sec)
    wob = 1 + 0.08 * _tone(_whole(3.0, sec), t)
    whine = (_tone(f, t) + 0.3 * _tone(2 * f, t) + 0.12 * _tone(_whole(790.0, sec), t)) * wob
    bearing = _band(rng.standard_normal(len(t)), 2000, 9000)
    return _norm(whine / np.abs(whine).max() + 0.25 * bearing / np.abs(bearing).max())


def _pulses(t, sec, f, decay, rng, jitter=0.0):
    """A train of decaying thumps at a whole-number rate f in the loop (engine firing)."""
    out = np.zeros_like(t)
    n = int(round(f * sec))
    for i in range(n):
        s0 = i / n * sec
        u = (t - s0) % sec  # wraps, so the last thump rings into the start
        out += np.exp(-u / decay) * (1 + jitter * (rng.random() - 0.5)) * np.minimum(1, u / 0.0015)
    return out


def diesel(rng):
    sec = 3.0
    t = _t(sec)
    fire = _pulses(t, sec, 27.0, 0.008, rng, 0.5)
    body = _band(fire * rng.standard_normal(len(t)) * 0.5 + fire, 30, 700)
    rattle = _band(rng.standard_normal(len(t)), 1200, 4500) * _band(fire, 1, 200)
    intake = _band(_pink(len(t), rng), 80, 1500)
    x = body / np.abs(body).max() + 0.35 * rattle / np.abs(rattle).max() + 0.25 * intake / np.abs(intake).max()
    return _norm(x)


def car(rng):
    sec = 2.0
    t = _t(sec)
    fire = _pulses(t, sec, 33.0, 0.012, rng, 0.15)
    body = _band(fire, 25, 500)
    exhaust = _band(_pink(len(t), rng), 60, 1800) * (0.6 + 0.4 * _band(fire, 1, 120) / np.abs(fire).max())
    return _norm(body / np.abs(body).max() + 0.4 * exhaust / np.abs(exhaust).max())


def jetway_motor(rng):
    sec = 2.0
    t = _t(sec)
    f = _whole(420.0, sec)
    whine = _tone(f, t) + 0.5 * _tone(2 * f, t) + 0.2 * _tone(_whole(1260.0, sec), t)
    gears = _band(rng.standard_normal(len(t)), 700, 3200) * (1 + 0.5 * _tone(_whole(12.0, sec), t))
    beep = _tone(_whole(2900.0, sec), t) * (((t % 1.0) < 0.3) * 1.0)
    beep = _band(beep, 2000, 4000)  # soft edges on the beeps
    x = 0.45 * whine / np.abs(whine).max() + 0.35 * gears / np.abs(gears).max() + 0.5 * beep / np.abs(beep).max()
    return _norm(x)


def thunder(rng):
    sec = 7.0
    t = _t(sec)
    crack = _band(rng.standard_normal(len(t)), 300, 6000) * np.exp(-t / 0.08) * np.minimum(1, t / 0.004)
    brown = np.cumsum(rng.standard_normal(len(t)))
    brown = _band(brown - np.linspace(brown[0], brown[-1], len(t)), 25, 260)
    swell = np.ones_like(t)
    for _ in range(5):
        c, w = 0.4 + 4.5 * rng.random(), 0.3 + 0.8 * rng.random()
        swell += 1.2 * rng.random() * np.exp(-((t - c) / w) ** 2)
    rumble = brown / np.abs(brown).max() * swell * np.exp(-t / 2.4) * np.minimum(1, t / 0.15)
    return _fades(_norm(0.5 * crack / np.abs(crack).max() + rumble), 0.002, 0.8)


FILES = [
    (A320, "ptu_bark_loop.wav", lambda r: ptu_bark(r)),
    (A320, "apu_loop.wav", lambda r: apu_loop(r)),
    (A320, "master_warning_loop.wav", lambda r: master_warning()),
    (A320, "master_caution.wav", lambda r: master_caution()),
    (A320, "avionics_fan_loop.wav", lambda r: avionics_fan(r)),
    (C172, "tc_gyro_loop.wav", lambda r: tc_gyro(r)),
    (WORLD, "diesel_loop.wav", lambda r: diesel(r)),
    (WORLD, "car_loop.wav", lambda r: car(r)),
    (WORLD, "jetway_motor_loop.wav", lambda r: jetway_motor(r)),
    (WORLD, "thunder.wav", lambda r: thunder(r)),
]


def _write(path, x):
    pcm = np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main():
    check = "--check" in sys.argv
    for i, (d, name, fn) in enumerate(FILES):
        x = fn(np.random.default_rng(29000 + i))
        seam = abs(float(x[-1] - x[0]))
        print("%-26s %5.2f s  peak %.3f  seam %.4f" % (name, len(x) / RATE, np.abs(x).max(), seam))
        if not check:
            os.makedirs(d, exist_ok=True)
            _write(os.path.join(d, name), x)


if __name__ == "__main__":
    main()
