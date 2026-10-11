"""Fly the same scripted manoeuvres in JSBSim c172p and in our FDM, then compare.
Usage: 18_compare_fdm.py [--out /tmp/fdm_compare] [--no-godot] [--engine io360|io320] [--rig 0.035,0.005]
Runs game/tests/fdm_compare.gd (ours_<m>.csv), flies the same pilot laws in JSBSim (jsb_<m>.csv), then
writes metrics.md + PNG plots (fdm_compare_metrics.py). --engine io360 (default) swaps JSBSim's 160 hp
IO-320 for engIO360C; --rig = JSBSim roll/yaw trim (pilot convention), default ours (c172_config.json).
"""
import argparse
import json
import math
import subprocess
from pathlib import Path

import jsbsim

import common as c
import fdm_compare_metrics as fm

SRC = c.RAW / "jsbsim" / "src"
GODOT = Path.home() / ".local" / "bin" / "godot"
KT = 0.514444
FT = 0.3048
DT = 1.0 / 120.0
COLS = "t,alt_ft,agl_ft,kcas,ktas,phi,theta,psi,alpha,beta,p,q,r,vs_fpm,rpm,x_ft,y_ft,wow,pitch,roll,yaw,throttle,trim,hp".split(",")
MANOEUVRES = ["hands_off", "takeoff", "climb", "aileron_step", "elevator_doublet", "rudder_doublet",
              "stall_clean", "stall_flaps", "glide", "landing", "crosswind_takeoff"]
clip = lambda x, lo=-1.0, hi=1.0: max(lo, min(hi, x))


def jsbsim_root(out: Path, engine: str) -> Path:
    """A JSBSim root whose c172p uses the requested engine (stock = io320)."""
    root = out / "jsbsim_root"
    (root / "aircraft" / "c172p").mkdir(parents=True, exist_ok=True)
    for d in ("engine", "systems"):
        link = root / d
        if not link.exists() and not link.is_symlink():
            link.symlink_to(SRC / d)
    xml = (SRC / "aircraft" / "c172p" / "c172p.xml").read_text()
    if engine == "io360":
        xml = xml.replace('file="eng_io320"', 'file="engIO360C"')
    (root / "aircraft" / "c172p" / "c172p.xml").write_text(xml)
    return root


class Jsb:
    """JSBSim adapter exposing the same state/controls as FDM in fdm_compare.gd."""

    def __init__(self, root: Path, rig):
        self.f = jsbsim.FGFDMExec(str(root))
        self.f.set_debug_level(0)
        self.f.load_model("c172p")
        self.rig = rig
        self.u = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
        self.trim = 0.0
        self.t = 0.0
        self.x = 0.0
        self.y = 0.0
        self.ip = 0.0
        self.isp = 0.0
        self.rows = []

    __getitem__ = lambda self, k: self.f[k]
    __setitem__ = lambda self, k, v: self.f.__setitem__(k, v)

    # state, SI / rad, same meaning as ours
    phi = property(lambda s: s["attitude/phi-rad"])
    theta = property(lambda s: s["attitude/theta-rad"])
    psi = property(lambda s: s["attitude/psi-rad"])
    p = property(lambda s: s["velocities/p-rad_sec"])
    q = property(lambda s: s["velocities/q-rad_sec"])
    r = property(lambda s: s["velocities/r-rad_sec"])
    cas = property(lambda s: s["velocities/vc-kts"] * KT)
    vt = property(lambda s: s["velocities/vt-fps"] * FT)
    agl = property(lambda s: s["position/h-agl-ft"] * FT)
    vs = property(lambda s: -s["velocities/v-down-fps"] * FT)
    wow = property(lambda s: any(s[f"gear/unit[{i}]/WOW"] for i in range(3)))

    def controls(self, throttle=None, flaps_deg=None, brakes=None):
        if throttle is not None:
            self["fcs/throttle-cmd-norm"] = throttle
        if flaps_deg is not None:
            self["fcs/flap-cmd-norm"] = flaps_deg / 30.0
        if brakes is not None:
            self["fcs/left-brake-cmd-norm"] = brakes
            self["fcs/right-brake-cmd-norm"] = brakes

    def _apply(self):
        self["fcs/elevator-cmd-norm"] = -self.u["pitch"]
        self["fcs/pitch-trim-cmd-norm"] = -self.trim
        self["fcs/aileron-cmd-norm"] = self.u["roll"]
        self["fcs/roll-trim-cmd-norm"] = self.rig[0]
        self["fcs/rudder-cmd-norm"] = -self.u["yaw"]
        self["fcs/yaw-trim-cmd-norm"] = -self.rig[1]
        self["fcs/steer-cmd-norm"] = self.u["yaw"]

    def tick(self):
        self._apply()
        self.f.run()
        self.x += self["velocities/v-north-fps"] * DT
        self.y += self["velocities/v-east-fps"] * DT
        self.t += DT

    def log(self):
        g = self
        self.rows.append([g.t, g["position/h-sl-ft"], g["position/h-agl-ft"], g["velocities/vc-kts"],
                          g["velocities/vtrue-kts"], g["attitude/phi-deg"], g["attitude/theta-deg"],
                          math.degrees(g.psi) % 360.0, g["aero/alpha-deg"], g["aero/beta-deg"],
                          math.degrees(g.p), math.degrees(g.q), math.degrees(g.r), g.vs / FT * 60.0,
                          g["propulsion/engine/engine-rpm"], g.x, g.y, int(g.wow), g.u["pitch"], g.u["roll"],
                          g.u["yaw"], g["fcs/throttle-cmd-norm"], g.trim, g["propulsion/engine/power-hp"]])


class Pilot:
    """Mirror of the pilot laws in game/tests/fdm_compare.gd."""

    def __init__(self, s: Jsb):
        self.s = s

    def wings_level(self):
        s = self.s
        s.u["roll"] = clip(-2.0 * s.phi - 0.5 * s.p)

    def pitch_hold(self, theta_t):
        s = self.s
        err = theta_t - s.theta
        s.ip = clip(s.ip + err * DT, -2.0, 2.0)
        s.u["pitch"] = clip(3.0 * err + 1.5 * s.ip - 0.6 * s.q)

    def speed_hold(self, kcas):
        s = self.s
        e = s.cas - kcas * KT
        s.isp = clip(s.isp + e * DT, -100.0, 100.0)
        self.pitch_hold(clip(0.03 * e + 0.006 * s.isp, -0.3, 0.35))

    def heading_hold(self, psi_t):
        s = self.s
        e = (psi_t - s.psi + math.pi) % (2 * math.pi) - math.pi
        s.u["yaw"] = clip(3.0 * e - 0.5 * s.r)


def run(s: Jsb, seconds, law):
    for _ in range(int(round(seconds / DT))):
        s.log()
        if law():
            return
        s.tick()


def setup_air(root, rig, alt_ft, kcas, flaps=0):
    s = Jsb(root, rig)
    s["ic/h-sl-ft"] = alt_ft
    s["ic/vc-kts"] = kcas
    s["ic/gamma-deg"] = 0.0
    s["ic/psi-true-deg"] = 0.0
    s.controls(throttle=0.6, flaps_deg=[0, 10, 20, 30][flaps])
    s["fcs/mixture-cmd-norm"] = 1.0
    s._apply()
    s.f.run_ic()
    s["propulsion/set-running"] = -1
    try:
        s.f.do_trim(0)
    except Exception as e:  # noqa: BLE001 (JSBSim raises a generic trim failure)
        print(f"  JSBSim trim at {kcas} KCAS flaps {flaps}: {e}")
    s.trim = -clip(s["fcs/elevator-cmd-norm"] + s["fcs/pitch-trim-cmd-norm"])
    s.u = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
    s._apply()
    return s


def setup_ground(root, rig):
    s = Jsb(root, rig)
    s["ic/h-agl-ft"] = 4.0
    s["ic/vc-kts"] = 0.0
    s["ic/psi-true-deg"] = 0.0
    s["fcs/mixture-cmd-norm"] = 1.0
    s.controls(throttle=0.0, flaps_deg=0, brakes=1.0)
    s.f.run_ic()
    s["propulsion/set-running"] = -1
    for _ in range(int(3.0 / DT)):  # drop onto the gear and settle, brakes on
        s.tick()
    s.controls(brakes=0.0)
    s.t = s.x = s.y = 0.0
    return s


def fly_all(root, rig, h0):
    out = {}
    s = setup_air(root, rig, 1500, 100)
    run(s, 60, lambda: False)
    out["hands_off"] = s

    s = setup_air(root, rig, 1000, 74)
    p = Pilot(s)
    s.controls(throttle=1.0)
    run(s, 60, lambda: (p.speed_hold(74), p.wings_level(), False)[-1])
    out["climb"] = s

    s = setup_air(root, rig, 1500, 100)
    run(s, 6, lambda: (s.u.__setitem__("roll", 0.5 if 1.0 <= s.t < 4.0 else 0.0), False)[-1])
    out["aileron_step"] = s

    s = setup_air(root, rig, 1500, 100)
    p = Pilot(s)
    run(s, 120, lambda: (s.u.__setitem__("pitch", 0.2 if 1.0 <= s.t < 2.0 else (-0.2 if 2.0 <= s.t < 3.0 else 0.0)),
                         p.wings_level(), False)[-1])
    out["elevator_doublet"] = s

    s = setup_air(root, rig, 1500, 100)
    run(s, 15, lambda: (s.u.__setitem__("yaw", 0.5 if 1.0 <= s.t < 2.0 else (-0.5 if 2.0 <= s.t < 3.0 else 0.0)), False)[-1])
    out["rudder_doublet"] = s

    for name, flaps, kcas in (("stall_clean", 0, 70.0), ("stall_flaps", 3, 60.0)):
        s = setup_air(root, rig, 3000, kcas, flaps)
        p = Pilot(s)
        s.controls(throttle=0.0)
        run(s, 40, lambda s=s, p=p: (s.u.__setitem__("pitch", clip(0.04 * s.t, 0.0, 1.0)), p.wings_level(), False)[-1])
        out[name] = s

    s = setup_air(root, rig, 3000, 68)
    p = Pilot(s)
    s.controls(throttle=0.0)
    run(s, 90, lambda: (p.speed_hold(68), p.wings_level(), p.heading_hold(0.0), False)[-1])
    out["glide"] = s

    for name, xwind in (("takeoff", False), ("crosswind_takeoff", True)):
        s = setup_ground(root, rig)
        if xwind:
            s["atmosphere/wind-east-fps"] = -10.0 * KT / FT
        g0 = s.agl
        out[name] = s
        run(s, 60, lambda s=s, g0=g0, xwind=xwind: takeoff_law(s, Pilot(s), g0, xwind))

    out["landing"] = landing(root, rig, h0)
    return out


def takeoff_law(s, p, g0, xwind):
    s.controls(throttle=1.0)
    p.heading_hold(0.0)
    if s.cas < 55.0 * KT and s.agl - g0 < 1.0:
        s.u["pitch"] = 0.0
        s.u["roll"] = clip(0.6 * (1.0 - s.cas / (60.0 * KT)), 0.0, 1.0) if xwind else 0.0
    else:
        p.pitch_hold(math.radians(8.0))
        p.wings_level()
    return s.agl - g0 > 50.0 * FT


def landing(root, rig, h0):
    s = setup_air(root, rig, 50.0 + h0 / FT, 61, 3)
    p = Pilot(s)
    s.controls(throttle=0.0)
    td = [-1.0]

    def law():
        p.heading_hold(0.0)
        if td[0] < 0.0 and s.wow:
            td[0] = s.t
        if td[0] < 0.0:
            p.wings_level()
            h = s.agl - h0
            if h > 20.0 * FT:
                p.speed_hold(61)
            else:
                vs_t = -0.3 - 0.25 * max(h, 0.0)
                p.pitch_hold(clip(s.theta + 0.08 * (vs_t - s.vs), -0.1, 0.25))
        else:
            s.u["roll"] = 0.0
            s.u["pitch"] = 1.0 if s.t - td[0] < 1.0 else 0.3
            s.controls(brakes=1.0 if s.t - td[0] > 1.0 else 0.0)
        return td[0] > 0.0 and s.vt < 1.0 and s.t - td[0] > 2.0

    run(s, 90, law)
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/tmp/fdm_compare")
    ap.add_argument("--no-godot", action="store_true")
    ap.add_argument("--engine", default="io360", choices=["io360", "io320"])
    ap.add_argument("--rig", default=None, help="aileron,rudder rigging for JSBSim (default: ours)")
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    if not a.no_godot:
        subprocess.run([str(GODOT), "--headless", "--path", str(c.ROOT / "game"), "-s",
                        "res://tests/fdm_compare.gd", "--", f"--out={out}"], check=True)
    cfg = json.loads((c.ROOT / "game" / "aircraft" / "c172" / "c172_config.json").read_text())["controls"]
    rig = [float(x) for x in a.rig.split(",")] if a.rig else [cfg.get("aileron_rigging", 0.0), cfg.get("rudder_rigging", 0.0)]
    root = jsbsim_root(out, a.engine)
    h0 = setup_ground(root, rig).agl
    print(f"JSBSim c172p ({a.engine}), rigging aileron {rig[0]:+.3f} rudder {rig[1]:+.3f}, CG on gear {h0 / FT:.2f} ft")
    runs = fly_all(root, rig, h0)
    for name, s in runs.items():
        fm.save(COLS, s.rows, out / f"jsb_{name}.csv")
    fm.report(out, MANOEUVRES)


if __name__ == "__main__":
    main()
