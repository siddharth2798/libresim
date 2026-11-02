"""Reference numbers from the real A320 JSBSim model (FlightGear A320-family FDE + FBW / FADEC systems) run headless.

Tuning oracle for libresim's hand-written A320 control laws and FDM test cards (not used at run time).
Usage: 23_a320_reference.py [--only name,name] [--rebuild]      -> tools/a320_reference.json, tools/ref/a320_*.csv
Needs: tools/22_a320_fetch.sh done, jsbsim in tools/.venv. First run builds data/raw/fg/a320_root (~3 min, stub cache).
Runner: jsb_a320_sim.A320Sim (+ jsb_a320_root.py); cases: a320_ref_flight.py, a320_ref_takeoff.py. Notes: A320_DATA_NOTES.md.
"""
import argparse
import datetime
import json
import sys
import traceback
from pathlib import Path

import a320_ref_flight as fl
import a320_ref_pilot as rp
import a320_ref_takeoff as to
import common as c
import jsb_a320_root as root

OUT = Path(__file__).resolve().parent / "a320_reference.json"
REF = Path(__file__).resolve().parent / "ref"
ERRORS = []

PUBLIC = {  # public A320 data points (order of magnitude checks, not certified figures)
    "mtow_kg": [73500, 78000], "mlw_kg": 64500, "vref_full_64t_kt": 135, "takeoff_roll_m": [1800, 2200],
    "vr_v2_70t_kt": [140, 150], "cruise_ff_kg_h_per_engine_m078_fl350": [1200, 1300], "rated_thrust_kn": 120,
    "clean_vs1g_64t_kt_approx": [150, 160], "full_vs1g_64t_kt_approx": [105, 112]}


def run(name, fn, *a, **kw):
    """Run one case; on 'property X does not exist' add the stub and retry (up to 6 times); errors are recorded, not hidden."""
    for _ in range(6):
        try:
            return fn(*a, **kw)
        except Exception as e:  # noqa: BLE001 - JSBSim raises LogExceptionError
            prop = root.missing_property(str(e))
            if prop and root.add_stub(prop):
                print(f"  [{name}] added stub {prop}, retrying")
                continue
            ERRORS.append({"case": name, "error": str(e)[:400], "trace": traceback.format_exc()[-600:]})
            print(f"  [{name}] FAILED: {str(e)[:200]}")
            return None
    return None


def comparison(d):
    """JSBSim run vs public data points, from whatever parts of the result exist."""
    rows = []

    def add(item, jsb, public, note=""):
        rows.append({"item": item, "jsbsim": jsb, "public": public, "note": note})
    th = {x["label"]: x for x in d.get("thrust_formula_check", [])}
    if "static TOGA SL bleeds+packs off" in th:
        add("static TOGA thrust per engine, SL ISA (kN)", [round(th["static TOGA SL"]["thrust_measured_n"] / 1000, 1), round(th["static TOGA SL bleeds+packs off"]["thrust_measured_n"] / 1000, 1)],
            "~120 (rated thrust per the brief; CFM56-5B4 published 117.9 kN)", "first value bleed on, second bleed off")
    tr = {x["label"]: x for x in d.get("trim_level", [])}
    if "cruise M0.78 FL350 64 t" in tr:
        add("cruise fuel flow per engine M0.78 FL350 64 t (kg/h)", tr["cruise M0.78 FL350 64 t"]["fuel_flow_kg_h_per_engine"], "1200-1300")
        add("FMGC table Vs1g clean / CONF FULL at 64 t (kt)", [tr["cruise M0.78 FL350 64 t"]["fmgc_vs1g_kts"], tr["CONF FULL 135 KCAS 3000 ft gear down 64 t"]["fmgc_vs1g_kts"]],
            "~150-160 / ~105-112", "upstream FMGC weight tables, not the aerodynamics")
        add("Vref = 1.23 x FMGC Vs1g CONF FULL at 64 t (kt)", round(1.23 * tr["CONF FULL 135 KCAS 3000 ft gear down 64 t"]["fmgc_vs1g_kts"], 1), "~135")
    al = {x["conf"]: x for x in d.get("alpha_limit", [])}
    if "0" in al and "FULL" in al:
        add("aerodynamic 1-g speed at alpha-max clean / FULL, 64 t (kt)", [al["0"]["v_alpha_max_1g_kcas"], al["FULL"]["v_alpha_max_1g_kcas"]], "stall ~155 / ~109",
            "clean: the FDE aerodynamics reach alpha-max at ~12 % higher speed than the FMGC table Vs1g; FULL: ~10 % higher (1.23 x 119.7 = 147 kt vs public Vref ~135)")
    for x in d.get("takeoff", []):
        ev = x["events"]
        add(f"takeoff {x['weight_kg'] / 1000:.0f} t ISA{x['temp_dev_c']:+.0f}: liftoff distance (m) / liftoff speed (kt) / 35 ft distance (m)",
            [ev["liftoff"]["dist_m"], ev["liftoff"]["kcas"], ev["35ft"]["dist_m"]], "takeoff run 1800-2200 m near MTOW; VR / V2 140-150 kt at 70 t",
            f"brake release at stabilised TOGA, flaps 1+F, rotate {x['vr_kt']} kt; JSBSim roll is ~30 % shorter than the public figure")
    if d.get("rejected_takeoff"):
        add("rejected takeoff from 140 kt, brakes only (m after the reject)", d["rejected_takeoff"]["stop_dist_after_reject_m"], "no public figure used", "70 t, max braking, speedbrake, no reversers, no reaction delay")
    cl = d.get("climb", [])
    if len(cl) == 4:
        add("initial climb 70 t TOGA CONF 1 gear up, 1500 ft (fpm / %)", [cl[2]["rate_of_climb_fpm"], cl[2]["gradient_pct"]], "typical 2500-3500 fpm (not a certified figure)")
        add("one-engine-out climb, same case (fpm / %)", [cl[3]["rate_of_climb_fpm"], cl[3]["gradient_pct"]], ">= 2.4 % (second segment minimum)")
    rows.append({"item": "MTOW 73.5-78 t, MLW 64.5 t", "jsbsim": "not in the FDE (empty 43.28 t + 11.7 t payload points + tanks)", "public": "73500-78000 / 64500", "note": "limits belong in aircraft.json"})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--rebuild", action="store_true")
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    want = lambda n: not only or n in only  # noqa: E731
    root.ensure(args.rebuild)
    REF.mkdir(exist_ok=True)
    eng = json.load(open(c.ROOT / "game/aircraft/a320/config.json"))["engines"][0]
    res = {"meta": {
        "generated": datetime.date.today().isoformat(), "oracle": "JSBSim 1.3.3 headless, FlightGear A320-family FDE "
        "(pin fec1ecba767c8fffd145337b27012e89c01e3ade), A320-200 CFM56-5B4, 120 Hz", "licence": "GPL-2.0-only data (third_party/a320-family)",
        "units": "SI unless a key says kt / ft / fpm / deg; weights in kg; thrust in N per engine; fuel flow kg/h per engine",
        "caveats": [
            "FlightGear-side Nasal is not run. The g-law PI (/systems/fbw/pitch/load-factor-pi) is the upstream property rule Systems/a320-fbw-rules.xml "
            "re-implemented in velocity form at 120 Hz (jsb_a320_sim._load_factor_pi): FG's exact update rate and algorithm are not reproduced, so pitch step timing "
            "carries that uncertainty. Rate loop, actuators, gain schedules and protections are the real JSBSim ones. Autopilot / FMGC modes are not run.",
            "Cockpit switches set to normal in-flight state; autoconfig-running=0 (the cheat flag zeroes rated-thrust-factor); engine bleed/packs ON (thrust x 0.97).",
            "Pilot loops (a320_ref_pilot.py) are simple P/PI: trim numbers are averages over 10 s of settled flight; the aircraft starts at alpha 0 and settles for 60-150 s.",
            "Takeoff: 14 s of stabilised TOGA on the brakes, then release; rotation 1.0 stick to 11 deg then 0.15; trim -0.15 (THS ~ -2 deg); no wind, flat runway, ISA."],
        "public_data": PUBLIC}}
    if want("thrust"):
        print("thrust check")
        res["thrust_formula_check"] = run("thrust", to.thrust_check, eng, [
            ("static idle SL", 0, 0, 0.0, True), ("static TOGA SL", 0, 0, 1.0, True), ("M0.2 SL TOGA", 0, 0.2, 1.0, False),
            ("M0.56 FL100 TOGA", 10000, 0.45, 1.0, False), ("M0.78 FL350 CL", 35000, 0.78, 0.625, False), ("M0.78 FL350 idle", 35000, 0.78, 0.0, False),
            ("static TOGA SL bleeds+packs off", 0, 0, 1.0, True, True), ("M0.78 FL350 CL bleeds+packs off", 35000, 0.78, 0.625, False, True)])
    if want("trim"):
        print("trims")
        pts = [("clean 250 KCAS FL100 64 t", 64000, 0, 10000, dict(kcas=250)), ("clean 250 KCAS FL100 75 t", 75000, 0, 10000, dict(kcas=250)),
               ("cruise M0.78 FL350 64 t", 64000, 0, 35000, dict(mach=0.78)), ("cruise M0.78 FL350 75 t", 75000, 0, 35000, dict(mach=0.78)),
               ("CONF 1 190 KCAS 3000 ft 64 t", 64000, 1, 3000, dict(kcas=190)), ("CONF 2 170 KCAS 3000 ft 64 t", 64000, 2, 3000, dict(kcas=170)),
               ("CONF 3 150 KCAS 3000 ft gear down 64 t", 64000, 3, 3000, dict(kcas=150, gear_down=True)),
               ("CONF FULL 135 KCAS 3000 ft gear down 64 t", 64000, 4, 3000, dict(kcas=135, gear_down=True))]
        res["trim_level"] = [r for r in (run("trim", fl.trim_point, n, w, f, a, **k) for n, w, f, a, k in pts) if r]
        res["approach_3deg"] = run("approach", fl.trim_point, "CONF FULL 3 deg glide 135 KCAS gear down 64 t", 64000, 4, 2000,
                                   kcas=135, gear_down=True, gamma_t=-3.0)
    if want("stall"):
        print("stall / alpha-max")
        res["alpha_limit"] = [r for r in (run("stall", fl.stall_run, 64000, f, g, a, v) for f, g, a, v in
                                          ((0, False, 10000, 200), (1, False, 8000, 185), (2, False, 6000, 160), (3, True, 5000, 150), (4, True, 5000, 150))) if r]
    if want("takeoff"):
        print("takeoff")
        res["takeoff"] = [r for r in (run("takeoff", to.takeoff, **kw) for kw in (
            dict(weight_kg=70000), dict(weight_kg=78000, vr_kt=148.0, v2_kt=152.0), dict(weight_kg=70000, temp_dev_c=15.0))) if r]
        res["rejected_takeoff"] = run("rto", to.takeoff, weight_kg=70000, rto_at_kt=140.0)
    if want("climb"):
        print("climb")
        res["climb"] = [r for r in (run("climb", fl.climb_run, *a, **k) for a, k in (
            ((70000, 0, 10000, 250, 0.625), {}), ((70000, 0, 25000, 0, 0.625), dict(mach=0.78)),
            ((70000, 1, 1500, 156, 1.0), dict(seconds=60)), ((70000, 1, 1500, 156, 1.0), dict(seconds=60, engine_out=True)))) if r]
    if want("steps"):
        print("fbw steps")
        steps = []
        for name, fn, a, k in (("pitch_clean_250_fl100", fl.pitch_step, (64000, 0, False, 10000, 250), dict(stick=-0.3)),
                               ("pitch_full_140_3000", fl.pitch_step, (64000, 4, True, 3000, 140), dict(stick=-0.25)),
                               ("roll_clean_250_fl100_half", fl.roll_step, (64000, 0, False, 10000, 250), dict(stick=0.5)),
                               ("roll_clean_250_fl100_full", fl.roll_step, (64000, 0, False, 10000, 250), dict(stick=1.0)),
                               ("roll_full_140_3000_half", fl.roll_step, (64000, 4, True, 3000, 140), dict(stick=0.5))):
            r = run(name, fn, *a, **k)
            if r:
                summary, rows = r
                rp.write_csv(REF / f"a320_{name}.csv", rows)
                steps.append({"name": name, "csv": f"tools/ref/a320_{name}.csv", **summary})
        res["fbw_steps"] = steps
    res["errors"] = ERRORS
    old = json.loads(OUT.read_text()) if OUT.exists() and only else {}
    old.update(res)
    old["comparison_with_public_data"] = comparison(old)
    OUT.write_text(json.dumps(old, indent=1))
    print("wrote", OUT, "errors:", len(ERRORS))
    return 1 if ERRORS else 0


if __name__ == "__main__":
    sys.exit(main())
