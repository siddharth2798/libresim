"""Simple 'pilot' controllers on top of jsb_a320_sim.A320Sim for the reference runs (stick / throttle / rudder loops).

FG sign conventions: pitch stick -1 = pull (nose up); roll stick +1 = roll right; rudder +1 = nose right.
Normal law makes the stick a load-factor-rate demand, so a P loop on flight-path angle is enough for the pitch axis.
"""
import math

import jsb_a320_sim as js


def clip(v, lo, hi):
    return max(lo, min(hi, v))


class Pilot:
    def __init__(self, sim, throttle=0.6):
        self.sim = sim
        self.thr = self.thr0 = throttle
        self.int_v = 0.0
        self.int_g = 0.0
        self.log = None   # Recorder or None
        self.int_beta = 0.0
        self.pitch = 0.0
        self.roll = 0.0
        self.rudder = 0.0

    def speed_var(self, kind):
        f = self.sim.f
        return {"kcas": f["velocities/vc-kts"], "mach": f["velocities/mach"] * 600.0, "ktas": f["velocities/vt-fps"] / 1.68781}[kind]

    def step(self, n, gamma_t=None, speed_t=None, kind="kcas", hold_roll=True, beta_hold=False, engines=(0, 1),
             speed_to="throttle", **extra):
        """Advance n steps in blocks of 12 (10 Hz control), updating the loops each block.
        gamma_t: flight-path target deg (pitch loop). speed_t: target; speed_to 'throttle' (PI on lever) or 'gamma'
        (the pitch loop then follows speed: gamma_t is ignored)."""
        f = self.sim.f
        blocks = max(1, n // 12)
        dt = 12 * js.DT
        for _ in range(blocks):
            v = self.speed_var(kind) if speed_t is not None else 0.0
            if speed_t is not None and speed_to == "throttle":
                e = speed_t - v
                self.int_v = clip(self.int_v + e * dt, -80, 80)
                self.thr = clip(self.thr0 + 0.02 * e + 0.003 * self.int_v, 0.0, 1.0)
            gam = f["flight-path/gamma-deg"]
            gt = gamma_t
            if speed_t is not None and speed_to == "gamma":
                self.int_g = clip(self.int_g + (v - speed_t) * dt, -120, 120)
                gt = clip(0.25 * (v - speed_t) + 0.06 * self.int_g, -6.0, 18.0)
            if gt is not None:
                err = gam - gt   # sidestick has a +-2 % dead zone: add a small offset so small errors still act
                self.pitch = 0.0 if abs(err) < 0.04 else clip(0.06 * err + math.copysign(0.022, err), -1.0, 1.0)
            if hold_roll:
                self.roll = clip(-0.04 * f["attitude/phi-deg"] - 0.1 * math.degrees(f["velocities/p-rad_sec"]) * 0.2, -0.5, 0.5)
            if beta_hold:
                beta = f["aero/beta-deg"]
                self.int_beta = clip(self.int_beta + beta * dt, -8, 8)
                self.rudder = clip(0.3 * beta + 0.12 * self.int_beta, -1, 1)
            self.sim.set_controls(throttle=self.thr, pitch=self.pitch, roll=self.roll, rudder=self.rudder,
                                  engines=engines, **extra)
            self.sim.step(12)
            if self.log is not None:
                self.log.sample()


def trim_level(sim, speed, kind="kcas", seconds=180.0, gamma_t=0.0):
    """Fly a steady path (level by default) at `speed` until settled; returns averages over the last 10 s."""
    p = Pilot(sim, throttle=0.6)
    p.step(int(seconds * 120), gamma_t=gamma_t, speed_t=speed, kind=kind)
    acc = {}
    cnt = 0
    for _ in range(10):
        p.step(120, gamma_t=gamma_t, speed_t=speed, kind=kind)
        s = sim.snapshot()
        for k, v in s.items():
            if isinstance(v, float):
                acc[k] = acc.get(k, 0.0) + v
        cnt += 1
    out = {k: v / cnt for k, v in acc.items()}
    out["throttle_lever"] = p.thr
    out["fuel_flow_kg_h_per_engine"] = (out["ff_kgh_1"] + out["ff_kgh_2"]) / 2
    return out, p


class Recorder:
    """Samples selected snapshot keys every `every` calls of sample() (Pilot calls it every 0.1 s)."""
    KEYS = ("t", "kcas", "mach", "alt_ft", "alpha_deg", "pitch_deg", "roll_deg", "gamma_deg", "nz", "q_dps", "p_dps",
            "r_dps", "n1_1", "elev_l_deg", "ths_deg", "flap_deg", "slat_deg")

    def __init__(self, sim, keys=None, every=1):
        self.sim, self.keys, self.every, self.n, self.rows = sim, keys or self.KEYS, every, 0, []

    def sample(self):
        self.n += 1
        if self.n % self.every == 0:
            s = self.sim.snapshot()
            self.rows.append({k: s[k] for k in self.keys})


def write_csv(path, rows):
    with open(path, "w") as fh:
        fh.write(",".join(rows[0].keys()) + "\n")
        for r in rows:
            fh.write(",".join(f"{v:.5g}" if isinstance(v, float) else str(v) for v in r.values()) + "\n")
