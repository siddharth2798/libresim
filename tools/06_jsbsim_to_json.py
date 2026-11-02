"""JSBSim aircraft (+ engine and propeller files) -> game/aircraft/<id>/{aero,config}.json

Usage: 06_jsbsim_to_json.py [aircraft id]   (default c172; ids are the keys of SPECS below).
To add an aircraft: add a SPECS entry (the JSBSim aircraft / engine / propeller names and the tuning that
JSBSim does not carry), run this, then write aircraft.json in the same folder (docs/USAGE.md, "Adding an
aircraft"). An aircraft with several <engine> elements gets the "engines": [...] form (one piston engine
with its own propeller each, positions from JSBSim); a single engine gets the older {engine, propeller} form.

Aero: every JSBSim <function> becomes an expression tree, evaluated by game/fdm/aero.gd (format and the full
operator set: tools/jsb_expr.py). Aero expressions keep JSBSim units (psf, ft, rad); aero.gd converts the
resulting lbf / lbf*ft to SI. The config is SI. Structural frame (JSBSim): x aft, y right, z up.

"a320": the FlightGear A320-family FDE (data/raw/fg/a320, fetched by tools/22_a320_fetch.sh, GPL-2.0-only) goes
through tools/jsb_a320.py (turbofans: tools/jsb_turbine.py); notes on what is and is not converted:
tools/A320_DATA_NOTES.md.
"""
import json
import sys
import xml.etree.ElementTree as ET

import common as c
import jsb_a320
from jsb_expr import aero, expr, function, loc, table, txt  # noqa: F401 (the expression / table format lives in jsb_expr.py)

SRC = c.RAW / "jsbsim" / "src"
IN, FT, LB, SLUGFT2 = 0.0254, 0.3048, 0.45359237, 1.35581795
LBF_FT, LBF_FT_S = 14.5939029, 14.5939029  # lbf/ft -> N/m ; lbf*s/ft -> N*s/m
# What JSBSim does not carry, per aircraft id (= folder game/aircraft/<id>/).
SPECS = {
    "c172": {
        "jsbsim_aircraft": "c172p", "engine": "engIO360C", "prop": "prop_75in2f", "dst": "c172",
        "name": "Cessna 172S (JSBSim c172p airframe, IO-360 180 hp)",
        # JSBSim's c172p wheels are ~2x critically damped: a 300 fpm touchdown spikes to ~4 g and
        # trips the gear-overload check. Spring-steel legs + tyres are lightly damped: scale the
        # wheels to ~0.4 of critical (gear_damping); gear_ground.gd also ramps damping in over 3 cm.
        "gear_damping": 0.2,
        "unusable_fuel_kg": 1.5 * 2.72,
        # rigging = fixed ground-adjustable trim tabs (normalised, + = right roll / right pedal), set so
        # 100 KIAS level (middle of 90-110 KIAS cruise) is hands-off neutral with the default solo pilot
        # (180 lb left seat + engine torque).
        # Solved with zero roll/yaw acceleration at trim; see docs/FDM-VS-FLIGHTGEAR.md.
        "aileron_rigging": 0.033, "rudder_rigging": 0.004,
        # weak wings-level pull, aileron per rad of bank (flight_controls.gd; the real c172p holds bank by itself)
        "roll_stability": 1.0,
        # actuator rate limits: full -1..1 travel time, FlightGear c172p FCS <kinematic>
        "full_travel_s": {"pitch": 0.3, "roll": 0.15, "yaw": 0.15},
        # rpm of a trimmed airborne start / of a running engine at a ground start
        "cruise_rpm": 2300.0, "start_rpm": 800.0,
        # Tuning: JSBSim's 75in2f is only ~59 % efficient at Vy (J~0.5); JSBSim's
        # over-powered c172p engine (218 hp) hides that. A real C172S prop is ~67 %,
        # so thrust is boosted at low advance ratio, fading out before cruise.
        "cp_factor": 1.0,
        "ct_factor_vs_j": {"rows": [0.0, 0.55, 0.85], "data": [[1.17], [1.17], [1.0]]},
        "vspeeds_kias": {"vs0": 40, "vs1": 48, "vr": 55, "vx": 62, "vy": 74, "vg": 68,
                         "vfe10": 110, "vfe_full": 85, "vno": 129, "vne": 163, "va": 105},
    },
    "a320": {   # FlightGear A320-family, A320-200 with CFM56-5B4 (GPL-2.0-only; see third_party/a320-family/SOURCE.md)
        "src": "fg/a320", "fde": "FDE/A320-200-CFM.xml", "set": "A320-200-CFM-set.xml",
        "fadec": "a320-cfm56-5b4-engine-fadec.xml", "dst": "a320",
        "name": "A320-family twin-jet airliner (FlightGear A320-family JSBSim FDE, CFM56-5B4)",
        # Upstream wheels are used as published; tune per aircraft in the FDM phase if touchdown loads are wrong.
        "gear_damping": 1.0,
        "derived_from": {
            "upstream": "https://github.com/legoboyvdlp/A320-family", "commit": "fec1ecba767c8fffd145337b27012e89c01e3ade",
            "files": ["FDE/A320-200-CFM.xml", "FDE/Config/*.xml", "Engines/cfm56-5b4_*.xml", "Engines/APS3200.xml",
                      "Systems/a320-fcs.xml", "Systems/a320-spoilers.xml", "Systems/a320-cfm56-5b4-engine-fadec.xml",
                      "A320-200-CFM-set.xml (options/maxflap)"],
            "copyright": "Copyright (c) 2025 Josh Davidson, Jonathan Redpath, merspieler, Matthew Maring, Thorsten Herrmann, Semir Gebran",
            "license": "GPL-2.0-only",
            "modified": "2026-10-28 by libresim (tools/06_jsbsim_to_json.py a320): units converted to SI, XML -> JSON, see third_party/a320-family/SOURCE.md"},
    },
}


def config(root, spec):
    m, mb = root.find("metrics"), root.find("mass_balance")
    locs = {l.get("name"): loc(l) for l in m.findall("location")}
    gear = []
    for ct in root.find("ground_reactions").findall("contact"):
        gear.append({
            "name": ct.get("name"), "type": ct.get("type"), "pos_m": loc(ct.find("location")),
            "static_friction": txt(ct, "static_friction"), "dynamic_friction": txt(ct, "dynamic_friction"),
            "rolling_friction": txt(ct, "rolling_friction", 0.0),
            "spring_n_per_m": txt(ct, "spring_coeff") * LBF_FT,
            # wheels scaled by spec["gear_damping"] (see SPECS)
            "damping_n_s_per_m": txt(ct, "damping_coeff") * LBF_FT_S * (spec["gear_damping"] if ct.get("type") == "BOGEY" else 1.0),
            "max_steer_deg": txt(ct, "max_steer", 0.0), "brake_group": txt(ct, "brake_group", "NONE", str),
        })
    tanks = [{"pos_m": loc(t.find("location")), "capacity_kg": txt(t, "capacity") * LB,
              "contents_kg": txt(t, "contents") * LB} for t in root.find("propulsion").findall("tank")]
    flaps = [{"deg": txt(s, "position"), "time_s": txt(s, "time")}
             for s in root.iter("setting")]
    surf = {}
    for comp in root.find("flight_control").iter("aerosurface_scale"):
        out = comp.findtext("output").strip()
        if out.endswith("-rad"):
            r = comp.find("range")
            surf[out.split("/")[1].replace("-pos-rad", "")] = {"min_deg": txt(r, "min"), "max_deg": txt(r, "max")}
    engines = engine_blocks(root, spec)
    cfg = {
        "name": spec["name"],
        "metrics": {"wing_area_m2": txt(m, "wingarea") * FT * FT, "wingspan_m": txt(m, "wingspan") * FT,
                    "chord_m": txt(m, "chord") * FT, "htail_area_m2": txt(m, "htailarea") * FT * FT,
                    "htail_arm_m": txt(m, "htailarm") * FT,
                    "aero_ref_pt_m": locs["AERORP"], "eyepoint_m": locs["EYEPOINT"], "vrp_m": locs["VRP"]},
        "mass": {"empty_kg": txt(mb, "emptywt") * LB, "empty_cg_m": loc(mb.find("location")),
                 "inertia_kgm2": {k: txt(mb, k) * SLUGFT2 for k in ("ixx", "iyy", "izz", "ixz")},
                 "point_masses": [{"name": p.get("name"), "kg": txt(p, "weight") * LB,
                                   "pos_m": loc(p.find("location"))} for p in mb.findall("pointmass")]},
        "gear": gear,
        "tanks": tanks, "unusable_fuel_kg": spec["unusable_fuel_kg"],
        "controls": {"surfaces": surf, "flaps": flaps, "aileron_rigging": spec["aileron_rigging"],
                     "rudder_rigging": spec["rudder_rigging"], "roll_stability": spec["roll_stability"],
                     "full_travel_s": spec["full_travel_s"]},
    }
    if len(engines) == 1:
        cfg["engine"], cfg["propeller"] = engines[0]["engine"], engines[0]["propeller"]
    else:
        cfg["engines"] = [{**e["engine"], "propeller": e["propeller"]} for e in engines]
    cfg["vspeeds_kias"] = spec["vspeeds_kias"]
    return cfg


def engine_blocks(root, spec):
    """One {engine, propeller} pair per <engine> of the JSBSim aircraft (all of the spec's engine / prop files)."""
    eng = ET.parse(SRC / "engine" / (spec["engine"] + ".xml")).getroot()
    prop = ET.parse(SRC / "engine" / (spec["prop"] + ".xml")).getroot()
    out = []
    for e in root.find("propulsion").findall("engine"):
        thr = e.find("thruster")
        out.append({
            "engine": {"type": "piston", "maxhp": txt(eng, "maxhp"), "displacement_in3": txt(eng, "displacement"),
                       "idle_rpm": txt(eng, "idlerpm"), "max_rpm": txt(eng, "maxrpm"),
                       "min_map_inhg": txt(eng, "minmp"), "max_map_inhg": txt(eng, "maxmp"),
                       "spark_fail_drop": txt(eng, "sparkfaildrop"),
                       "pos_m": loc(thr.find("location")), "p_factor": txt(thr, "p_factor", 0.0),
                       "sense": txt(thr, "sense", 1.0),
                       "cruise_rpm": spec["cruise_rpm"], "start_rpm": spec["start_rpm"]},
            "propeller": {"diameter_m": txt(prop, "diameter") * IN, "ixx_kgm2": txt(prop, "ixx") * SLUGFT2,
                          "blades": txt(prop, "numblades"), "pitch_deg": txt(prop, "minpitch"),
                          "cp_factor": spec["cp_factor"],
                          "ct_factor_vs_j": {"row": None, "col": None, "cols": None, **spec["ct_factor_vs_j"]},
                          **{t.get("name"): table(t) for t in prop.findall("table")}},
        })
    return out


def main():
    aid = sys.argv[1] if len(sys.argv) > 1 else "c172"
    if aid not in SPECS:
        sys.exit(f"unknown aircraft '{aid}', known: {', '.join(SPECS)}")
    spec = SPECS[aid]
    dst = c.ROOT / "game" / "aircraft" / spec["dst"]
    if "fde" in spec:  # file-split FlightGear FDE (a320)
        a, cfg = jsb_a320.build(spec, c.RAW / spec["src"])
        dst.mkdir(parents=True, exist_ok=True)
        (dst / "aero.json").write_text(json.dumps(a, indent=1))
        (dst / "config.json").write_text(json.dumps(cfg, indent=1))
        print(aid, "aero functions:", len(a["functions"]), {k: len(v) for k, v in a["axes"].items()},
              "| engines", len(cfg["engines"]), "gear", len(cfg["gear"]), "tanks", len(cfg["tanks"]),
              "| unconverted", len(cfg["unconverted"]))
        return
    root = ET.parse(SRC / "aircraft" / spec["jsbsim_aircraft"] / (spec["jsbsim_aircraft"] + ".xml")).getroot()
    dst.mkdir(parents=True, exist_ok=True)
    a = aero(root)
    (dst / "aero.json").write_text(json.dumps(a, indent=1))
    (dst / "config.json").write_text(json.dumps(config(root, spec), indent=1))
    print(aid, "aero functions:", len(a["functions"]), {k: len(v) for k, v in a["axes"].items()})


if __name__ == "__main__":
    main()
