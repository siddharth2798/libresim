"""Takeoff roll / rejected takeoff / static-thrust reference cases for the JSBSim A320 oracle (see 23_a320_reference.py)."""
import math


import a320_ref_pilot as rp
import jsb_a320_sim as js

FT = 0.3048
DEBUG = False


def _steer(sim, psi0=0.0):
    f = sim.f
    err = (f["attitude/psi-deg"] - psi0 + 180) % 360 - 180
    return rp.clip(-0.08 * err - 0.15 * math.degrees(f["velocities/r-rad_sec"]), -0.5, 0.5)


def takeoff(weight_kg=70000.0, flaps=1, vr_kt=142.0, v2_kt=146.0, toga=1.0, rto_at_kt=None, temp_dev_c=0.0, rotate_rate=1.0, trim=-0.15):
    """TOGA stabilised on the brakes (14 s), brakes released at t=0 (distances and times count from release), rotate at vr_kt to ~15 deg, gear up at 35 ft, hold V2+10 climb to 1500 ft AGL.
    rto_at_kt: instead reject at that speed (idle, max brakes, speedbrake) and return the stopping distance."""
    sim = js.A320Sim().load().init(alt_ft=0.0, kcas=0.0, weight_kg=weight_kg, flaps=flaps, gear_down=True, on_ground=True,
                                   ground_cg_ft=10.9, temp_dev_c=temp_dev_c)
    f = sim.f
    p = rp.Pilot(sim, toga)
    ev = {}
    sim.set_controls(throttle=toga, brake=1.0, parking_brake=1, trim=trim)   # stabilise TOGA thrust on the brakes, then release
    sim.step(120 * 14)
    sim.set_controls(brake=0.0, parking_brake=0)
    x0, t0 = f["position/distance-from-start-mag-mt"], sim.t
    lifted = rotated = gear_up = False
    pitch_cmd = 0.0
    sim.set_controls(throttle=toga, brake=0.0, parking_brake=0, flaps=flaps)

    def mark(name):
        if name not in ev:
            s = sim.snapshot()
            ev[name] = {"t_s": round(s["t"], 2), "dist_m": round(f["position/distance-from-start-mag-mt"] - x0, 0),
                        "kcas": round(s["kcas"], 1), "pitch_deg": round(s["pitch_deg"], 2), "alt_ft": round(f["position/h-agl-ft"] - 10.9, 1)}
    track = []
    for i in range(120 * 150 // 6):
        s_kcas = f["velocities/vc-kts"]
        wow = f["gear/unit[1]/WOW"] > 0.5 or f["gear/unit[2]/WOW"] > 0.5
        for v in (60, 80, 100, 120, 130, 140):
            if s_kcas >= v:
                mark(f"kcas_{v}")
        if rto_at_kt and s_kcas >= rto_at_kt:
            return _rto(sim, p, x0, t0, rto_at_kt, ev)
        if s_kcas >= vr_kt and not rotated:
            rotated = True
            mark("rotate")
        if rotated and wow:
            pitch_cmd = -rotate_rate if f["attitude/theta-deg"] < 11.0 else -0.15
        elif rotated and not lifted:
            lifted = True
            mark("liftoff")
        alt = f["position/h-agl-ft"] - 10.9
        if lifted and alt > 35:
            mark("35ft")
        if lifted and alt > 15 and not gear_up and f["velocities/h-dot-fps"] > 3:
            gear_up = True
            sim.set_controls(gear_down=False)
            mark("gear_up_cmd")
        if alt > 1500:
            mark("1500ft")
            break
        if lifted:
            p.thr = toga
            p.step(6, speed_t=v2_kt + 10, kind="kcas", speed_to="gamma", beta_hold=False, hold_roll=True)
        else:
            sim.set_controls(pitch=pitch_cmd, rudder=_steer(sim) if wow else 0.0)
            sim.step(6)
        track.append((sim.t, s_kcas, alt))
    return {"weight_kg": weight_kg, "conf": "1+F" if flaps == 1 else str(flaps), "vr_kt": vr_kt, "events": ev, "n1_final": round(sim.snapshot()["n1_1"], 1),
            "temp_dev_c": temp_dev_c}


def _rto(sim, p, x0, t0, v_kt, ev):
    f = sim.f
    t_r = sim.t
    xr = f["position/distance-from-start-mag-mt"]
    sim.set_controls(throttle=0.0, brake=1.0, speedbrake=1.0, pitch=0.0)
    for _ in range(120 * 90 // 6):
        sim.set_controls(rudder=_steer(sim))
        sim.step(6)
        if f["velocities/vc-kts"] < 1.0:
            break
    return {"rto_from_kcas": v_kt, "dist_to_v_m": round(xr - x0), "stop_dist_after_reject_m": round(f["position/distance-from-start-mag-mt"] - xr),
            "total_dist_m": round(f["position/distance-from-start-mag-mt"] - x0), "stop_time_s": round(sim.t - t_r, 1), "events": ev,
            "note": "brakes max (no autobrake modelling check), no reversers, speedbrake lever full; reaction delay 0 s"}


# --- thrust formula check ----------------------------------------------------------------------------------------------
def _interp2(tab, row, col):
    """JSBSim 2-D table lookup (linear, clamped) on a converter table {rows, cols, data}."""
    import numpy as np
    rows, cols, data = np.array(tab["rows"]), np.array(tab["cols"]), np.array(tab["data"])
    r = float(np.clip(row, rows[0], rows[-1]))
    c = float(np.clip(col, cols[0], cols[-1]))
    return float(np.interp(r, rows, [np.interp(c, cols, data[i]) for i in range(len(rows))]))


def thrust_check(engine_cfg, cases):  # case: (label, alt, mach, lever, on_ground[, bleed_off])
    """cases: [(label, alt_ft, mach, lever, on_ground)]. Runs the real engine+FADEC, compares thrust-lbs with the JSBSim
    turbine formula  T = (idle + (thrust_n*mil_tab*rated_factor*reverser - idle) ... )  built from the converted config tables:
    idle = thrust_n*IdleThrust(M, DA); mil = (thrust_n - idle) * MilThrust(M, DA) * rated_factor * reverser;
    T = (idle + mil * N2norm^2) * (1 - bleed), N2norm = (N2 - idle_n2) / (max_n2 - idle_n2)  (n2 in percent)."""
    out = []
    for label, alt, mach, lever, ground, *opt in cases:
        kw = dict(alt_ft=alt, weight_kg=64000, flaps=0, gear_down=ground, on_ground=ground, settle_s=0)
        if ground:
            kw.update(kcas=0, ground_cg_ft=10.9)
        else:
            kw.update(mach=mach)
        sim = js.A320Sim().load().init(**kw)
        f = sim.f
        if opt and opt[0]:   # engine bleed and packs off: no (1 - bleed) derate
            for sw in ("bleed-1", "bleed-2", "pack-1", "pack-2"):
                f[f"/controls/pneumatics/switches/{sw}"] = 0
        sim.set_controls(throttle=lever, brake=1.0 if ground else None, parking_brake=1 if ground else None)
        p = rp.Pilot(sim, lever)
        if ground:
            sim.step(120 * 40)
        else:
            p.step(120 * 25, gamma_t=0.0, hold_roll=True)
        m, da = f["velocities/mach"], f["atmosphere/density-altitude"]
        t_n = engine_cfg["thrust_n"]
        idle_t = t_n * _interp2(engine_cfg["idle_thrust_table"], m, da)
        fac = f["/systems/fadec/limit/rated-thrust-factor"]
        mil = (t_n - idle_t) * _interp2(engine_cfg["thrust_table"], m, da) * fac
        n2 = f["propulsion/engine[0]/n2"]
        n2n = (n2 - engine_cfg["idle_n2"] * 100) / ((engine_cfg["max_n2"] - engine_cfg["idle_n2"]) * 100)
        pred = (idle_t + mil * n2n * n2n)
        meas = f["propulsion/engine[0]/thrust-lbs"] * js.LBF
        out.append({"label": label, "bleed_off": bool(opt and opt[0]), "alt_ft": alt, "mach": round(m, 3), "density_alt_ft": round(da), "lever": lever,
                    "n1": round(f["propulsion/engine[0]/n1"], 1), "n2": round(n2, 1), "rated_thrust_factor": round(fac, 3),
                    "idle_table_n": round(idle_t), "mil_table_n": round(t_n * _interp2(engine_cfg["thrust_table"], m, da)),
                    "thrust_measured_n": round(meas), "thrust_formula_n": round(pred),
                    "ratio_measured_over_formula": round(meas / pred, 4) if pred else None,
                    "ff_kg_h": round(f["propulsion/engine[0]/fuel-flow-rate-pps"] * js.LB * 3600, 1)})
    return out
