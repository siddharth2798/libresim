"""In-flight reference cases for the JSBSim A320 oracle: trims, stall speeds, approach, climbs, FBW step responses.
Each returns plain dicts (JSON-able) and, for the step responses, rows for CSV. See 23_a320_reference.py."""
import math

import a320_ref_pilot as rp
import jsb_a320_sim as js

G = 9.80665
S_WING = 122.6  # m2, metrics file
RHO0 = 1.225
FLAP_NAME = ("0", "1", "2", "3", "FULL")
TRIM_KEYS = ("kcas", "mach", "ktas", "alt_ft", "alpha_deg", "pitch_deg", "elev_l_deg", "ths_deg", "n1_1", "thrust_n_1",
             "weight_kg", "flap_deg", "slat_deg")


def new_sim(**init):
    return js.A320Sim().load().init(**init)


def trim_point(label, weight_kg, flaps, alt_ft, kcas=None, mach=None, gear_down=False, seconds=150.0, gamma_t=0.0):
    kw = {"kcas": kcas} if mach is None else {"mach": mach}
    sim = new_sim(alt_ft=alt_ft, weight_kg=weight_kg, flaps=flaps, gear_down=gear_down, **kw)
    out, p = rp.trim_level(sim, mach * 600.0 if mach else kcas, "mach" if mach else "kcas", seconds, gamma_t)
    res = {k: round(out[k], 3) for k in TRIM_KEYS}
    f = sim.f
    env = {k: round(f[f"/FMGC/internal/{n}"], 1) for k, n in (("fmgc_vs1g_kts", "vs1g-kts"), ("fmgc_vls_kts", "vls"), ("fmgc_vsw_kts", "vsw"))}
    res.update(env)
    res.update({"label": label, "conf": FLAP_NAME[flaps], "gear_down": gear_down, "throttle_lever": round(p.thr, 3),
                "fuel_flow_kg_h_per_engine": round(out["fuel_flow_kg_h_per_engine"], 1),
                "vs_fpm": round(out["vs_fpm"], 1), "gamma_deg": round(out["gamma_deg"], 3)})
    return res


def stall_run(weight_kg, flaps, gear_down, alt_ft, v_start_kt, rate_kt_s=1.0):
    """Normal-law angle-of-attack limit. Phase 1: 1 g deceleration (speed target ramps down, pitch loop holds level) until
    alpha-prot. Phase 2: full aft stick, idle, wings level, 40 s: alpha settles at alpha-max. CL at alpha-max from the last 5 s
    (CL = nz W / (q S)); VaMAX(1 g) = sqrt(2 W / (rho0 S CL)); an extrapolated 1-g stall speed from a linear CL(alpha) fit
    (alpha-prot-2.5 .. alpha-max) extended to alpha-stall (estimate: normal law never lets the aircraft stall)."""
    sim = new_sim(alt_ft=alt_ft, weight_kg=weight_kg, flaps=flaps, gear_down=gear_down, kcas=v_start_kt)
    f = sim.f
    p = rp.Pilot(sim, 0.5)
    p.step(120 * 90, gamma_t=0.0, speed_t=v_start_kt)   # the IC starts at alpha 0: let the g-law / trim settle
    am, ap, ast = f["/systems/fbw/alpha-max-deg"], f["/systems/fbw/alpha-prot-deg"], f["/systems/fbw/alpha-stall-deg"]
    t0, v_prot = sim.t, None
    for _ in range(120 * 150 // 12):
        p.step(12, gamma_t=0.0, speed_t=max(60.0, v_start_kt - rate_kt_s * (sim.t - t0)))
        if sim.snapshot()["alpha_deg"] >= ap - 0.1:
            v_prot = f["velocities/vc-kts"]
            break
    pts = []
    p.thr = 0.0
    for i in range(120 * 40 // 12):
        sim.set_controls(throttle=0.0, pitch=-1.0, roll=rp.clip(-0.04 * f["attitude/phi-deg"], -0.3, 0.3))
        sim.step(12)
        s = sim.snapshot()
        pts.append((s["alpha_deg"], s["nz"] * s["weight_kg"] * G / (f["aero/qbar-psf"] * 47.8803 * S_WING), s["kcas"], s["nz"], s["gamma_deg"]))
    last = pts[-40:]
    avg = [sum(x[i] for x in last) / len(last) for i in range(5)]
    cl_am = avg[1]
    fit = [(a, c) for a, c, *_ in pts if ap - 2.5 <= a <= am + 0.05]
    vs_est = None
    if len(fit) > 10:
        n = len(fit)
        ma, mc = sum(a for a, _ in fit) / n, sum(c for _, c in fit) / n
        den = sum((a - ma) ** 2 for a, _ in fit)
        if den > 1e-3:
            k = sum((a - ma) * (c - mc) for a, c in fit) / den
            vs_est = math.sqrt(2 * weight_kg * G / (RHO0 * S_WING * (mc + k * (ast - ma)))) / 0.514444
    return {"conf": FLAP_NAME[flaps], "gear_down": gear_down, "weight_kg": weight_kg, "decel_kt_per_s": rate_kt_s,
            "alpha_prot_deg": round(ap, 2), "alpha_max_deg": round(am, 2), "alpha_stall_deg": round(ast, 2),
            "kcas_at_alpha_prot_1g": v_prot and round(v_prot, 1), "alpha_end_deg": round(avg[0], 2), "nz_end": round(avg[3], 3),
            "gamma_end_deg": round(avg[4], 1), "kcas_end": round(avg[2], 1), "cl_at_alpha_max": round(cl_am, 3),
            "v_alpha_max_1g_kcas": round(math.sqrt(2 * weight_kg * G / (RHO0 * S_WING * cl_am)) / 0.514444, 1),
            "vs1g_estimate_kcas": vs_est and round(vs_est, 1),
            "note": "v_alpha_max_1g from CL at alpha-max; vs1g_estimate extrapolated to alpha-stall"}


def climb_run(weight_kg, flaps, alt_ft, kcas, throttle, gear_down=False, seconds=90.0, engine_out=False, mach=None):
    """Climb at constant speed (pitch follows speed) with the throttle lever fixed; returns the steady rate/gradient."""
    kw = {"kcas": kcas} if mach is None else {"mach": mach}
    sim = new_sim(alt_ft=alt_ft, weight_kg=weight_kg, flaps=flaps, gear_down=gear_down, gamma_deg=4.0, **kw)
    f = sim.f
    p = rp.Pilot(sim, throttle)
    eng = (0, 1)
    if engine_out:
        f["propulsion/engine[1]/set-running"] = 0
        f["/controls/engines/engine[1]/cutoff"] = 1
        eng = (0,)
        sim.set_controls(throttle=0.0, engines=(1,))
    kind, tgt = ("kcas", kcas) if mach is None else ("mach", mach * 600.0)
    p.step(int(seconds * 120 * 0.6), speed_t=tgt, kind=kind, speed_to="gamma", engines=eng, beta_hold=engine_out)
    a0, t0 = f["position/h-sl-ft"], sim.t
    p.step(int(seconds * 120 * 0.4), speed_t=tgt, kind=kind, speed_to="gamma", engines=eng, beta_hold=engine_out)
    roc = (f["position/h-sl-ft"] - a0) / (sim.t - t0) * 60
    s = sim.snapshot()
    gam = math.degrees(math.asin(max(-1, min(1, roc / 60 / (s["ktas"] * 1.68781)))))
    return {"weight_kg": weight_kg, "conf": FLAP_NAME[flaps], "alt_ft": alt_ft, "kcas": round(s["kcas"], 1), "mach": round(s["mach"], 3),
            "engine_out": engine_out, "throttle_lever": throttle, "rate_of_climb_fpm": round(roc), "gradient_pct": round(math.tan(math.radians(gam)) * 100, 2),
            "n1_1": round(s["n1_1"], 1), "n1_2": round(s["n1_2"], 1), "alpha_deg": round(s["alpha_deg"], 2),
            "pitch_deg": round(s["pitch_deg"], 2), "beta_deg": round(f["aero/beta-deg"], 2), "rudder_cmd": round(p.rudder, 3)}


def pitch_step(weight_kg, flaps, gear_down, alt_ft, kcas, stick=-0.3, hold_s=4.0, total_s=20.0):
    """Open-loop stick pulse from trimmed level flight. Returns (summary, rows)."""
    sim = new_sim(alt_ft=alt_ft, weight_kg=weight_kg, flaps=flaps, gear_down=gear_down, kcas=kcas)
    _, p = rp.trim_level(sim, kcas, "kcas", 120.0)
    rec = rp.Recorder(sim)
    p.log = rec
    p.step(120 * 2, hold_roll=True)                       # 2 s steady pre-roll
    t_start = sim.t
    p.pitch = stick
    p.step(int(hold_s * 120), hold_roll=True)
    p.pitch = 0.0
    p.step(int((total_s - hold_s) * 120), hold_roll=True)
    rows = [{**r, "t": round(r["t"] - t_start, 3), "stick": stick if 0 <= r["t"] - t_start < hold_s else 0.0} for r in rec.rows]
    seg = [r for r in rows if 0 <= r["t"] <= hold_s]
    nz_peak = max(seg, key=lambda r: abs(r["nz"] - 1))["nz"]
    t63 = next((r["t"] for r in seg if abs(r["nz"] - 1) >= 0.63 * abs(nz_peak - 1)), None)
    return {"kcas": kcas, "alt_ft": alt_ft, "conf": FLAP_NAME[flaps], "weight_kg": weight_kg, "stick": stick, "hold_s": hold_s,
            "nz_peak": round(nz_peak, 3), "t_to_63pct_nz_s": t63, "q_peak_dps": round(max(abs(r["q_dps"]) for r in seg), 2),
            "alpha_peak_deg": round(max(r["alpha_deg"] for r in seg), 2), "elev_peak_deg": round(max(abs(r["elev_l_deg"]) for r in seg), 2)}, rows


def roll_step(weight_kg, flaps, gear_down, alt_ft, kcas, stick=0.5, hold_s=4.0, total_s=14.0):
    sim = new_sim(alt_ft=alt_ft, weight_kg=weight_kg, flaps=flaps, gear_down=gear_down, kcas=kcas)
    _, p = rp.trim_level(sim, kcas, "kcas", 120.0)
    rec = rp.Recorder(sim)
    p.log = rec
    p.step(120 * 2, hold_roll=False)
    t_start = sim.t
    p.roll = stick
    p.step(int(hold_s * 120), hold_roll=False, gamma_t=0.0)
    p.roll = 0.0
    p.step(int((total_s - hold_s) * 120), hold_roll=False, gamma_t=0.0)
    rows = [{**r, "t": round(r["t"] - t_start, 3), "stick": stick if 0 <= r["t"] - t_start < hold_s else 0.0} for r in rec.rows]
    seg = [r for r in rows if 0 <= r["t"] <= hold_s]
    p_ss = sum(r["p_dps"] for r in seg if r["t"] > hold_s - 1.5) / max(1, len([r for r in seg if r["t"] > hold_s - 1.5]))
    t63 = next((r["t"] for r in seg if abs(r["p_dps"]) >= 0.63 * abs(p_ss)), None)
    return {"kcas": kcas, "alt_ft": alt_ft, "conf": FLAP_NAME[flaps], "weight_kg": weight_kg, "stick": stick, "hold_s": hold_s,
            "roll_rate_ss_dps": round(p_ss, 2), "t_to_63pct_rate_s": t63, "bank_at_release_deg": round(seg[-1]["roll_deg"], 1),
            "p_peak_dps": round(max(abs(r["p_dps"]) for r in seg), 2), "roll_after_release_deg": round(rows[-1]["roll_deg"], 1)}, rows
