"""FlightGear A320-family JSBSim files (data/raw/fg/a320, GPL-2.0-only) -> aero.json + config.json dicts.

The upstream FDE is split into component files referenced by file="..."; this resolves them, converts what the
libresim flight model needs and lists the rest in "unconverted" (written into config.json) so nothing is silently lost.
config.json layout (SI, JSBSim structural frame x aft, y right, z up, metres; same keys as the c172 config where they
exist): name, derived_from, license, metrics, mass, gear[], tanks[], unusable_fuel_kg, engines[] (see jsb_turbine.py),
apu, controls {surfaces, flaps, gear_transit, spoilers}, fadec_limits, unconverted[].
Extra gear keys: "retractable" (bool), "cornering_coeff" (1-D table slip angle deg -> coefficient or null).
Extra tank keys: "name", "density_kg_per_l", "unusable_l", "priority", "feed_for" is on the engine ("feed_tanks").
"""
import re
from pathlib import Path

import jsb_expr as x
import jsb_turbine as jt

UPSTREAM = "https://github.com/legoboyvdlp/A320-family"
UNIT_CHILD_SKIP = {"location", "static_friction", "dynamic_friction", "rolling_friction", "spring_coeff",
                   "damping_coeff", "max_steer", "brake_group", "retractable", "table"}
BUILTIN = ("aero/", "metrics/", "velocities/", "position/", "attitude/", "inertia/", "propulsion/", "gear/", "atmosphere/")


def resolve(el, base, sub):
    """An element with file="x" -> the root of that XML file (relative to base, base/sub, with or without .xml)."""
    f = el.get("file")
    if not f:
        return el
    for d in (base, base / sub):
        for name in (f, f + ".xml"):
            if (d / name).is_file():
                return x.parse(d / name)
    raise FileNotFoundError(f"{f} (under {base})")


def metrics(m):
    locs = {l.get("name"): x.unit_loc(l) for l in m.findall("location")}
    out = {"wing_area_m2": x.val(m, "wingarea", x.AREA), "wingspan_m": x.val(m, "wingspan", x.LENGTH),
           "chord_m": x.val(m, "chord", x.LENGTH)}
    for k, t in (("htail_area_m2", "htailarea"), ("htail_arm_m", "htailarm")):
        if m.find(t) is not None:
            out[k] = x.val(m, t, x.AREA if "area" in t else x.LENGTH)
    out.update({"aero_ref_pt_m": locs["AERORP"], "eyepoint_m": locs["EYEPOINT"], "vrp_m": locs["VRP"]})
    return out


def mass(mb):
    return {"empty_kg": x.val(mb, "emptywt", x.MASS), "empty_cg_m": x.unit_loc(mb.find("location")),
            "inertia_kgm2": {k: x.val(mb, k, x.SLUGFT2) for k in ("ixx", "iyy", "izz", "ixz")},
            "point_masses": [{"name": p.get("name"), "kg": x.val(p, "weight", x.MASS),
                              "pos_m": x.unit_loc(p.find("location"))} for p in mb.findall("pointmass")]}


def gear(gr, spec, unconverted):
    out = []
    for ct in gr.findall("contact"):
        t = ct.find("table")
        bogey = ct.get("type") == "BOGEY"
        out.append({
            "name": ct.get("name"), "type": ct.get("type"), "pos_m": x.unit_loc(ct.find("location")),
            "static_friction": x.txt(ct, "static_friction"), "dynamic_friction": x.txt(ct, "dynamic_friction"),
            "rolling_friction": x.txt(ct, "rolling_friction", 0.0),
            "spring_n_per_m": x.val(ct, "spring_coeff", x.SPRING),
            "damping_n_s_per_m": x.val(ct, "damping_coeff", x.DAMP) * (spec.get("gear_damping", 1.0) if bogey else 1.0),
            "max_steer_deg": x.txt(ct, "max_steer", 0.0), "brake_group": x.txt(ct, "brake_group", "NONE", str),
            "retractable": bool(x.txt(ct, "retractable", 0, int)),
            "cornering_coeff": x.table(t) if t is not None else None,
        })
        for e in ct:
            if e.tag not in UNIT_CHILD_SKIP and e.tag is not x.ET.Comment:
                unconverted.append({"where": "gear " + ct.get("name"), "name": e.tag, "why": "contact element not translated"})
    return out


def tanks(prop):
    out = []
    for t in prop.findall("tank"):
        cm = next((c.text.strip() for c in t if c.tag is x.ET.Comment), None)
        dens = t.find("density")
        d_kg_l = float(dens.text) * x.MASS["LBS"] / x.VOLUME_L["GAL"] if dens is not None else 0.8
        unus = t.find("unusable-volume")
        out.append({"name": cm, "pos_m": x.unit_loc(t.find("location")), "capacity_kg": x.val(t, "capacity", x.MASS),
                    "contents_kg": x.val(t, "contents", x.MASS), "density_kg_per_l": d_kg_l,
                    "unusable_l": float(unus.text) * x.VOLUME_L[unus.get("unit")] if unus is not None else 0.0,
                    "priority": x.txt(t, "priority", 1, int)})
    return out


def _named(root, tag, name):
    return next((e for e in root.iter(tag) if e.get("name") == name), None)


def _switch_rate(root, name):
    """Largest plain number among the test values of a rate switch (the in-flight hydraulic rate; 100 = autoconfig cheat)."""
    sw = _named(root, "switch", name)
    if sw is None:
        return None
    vals = [float(t.get("value")) for t in sw.findall("test") if re.fullmatch(r"-?[0-9.]+", t.get("value", ""))]
    vals = [v for v in vals if v < 100]
    return max(vals) if vals else None


def surfaces(fcs):
    """Control-surface actuators: {surface: {max_deg, clip_deg, rate_deg_s, lag_rad_s, output}} from the FCS system file."""
    out = {}
    for ac in fcs.iter("actuator"):
        n = ac.get("name") or ""
        if not n.endswith("/final-actuator"):
            continue
        base = n[: -len("/final-actuator")]
        g = _named(fcs, "pure_gain", base + "/cmd-deg")
        clip = g.find("clipto") if g is not None else None
        out[base.rsplit("/", 1)[1]] = {
            "output": ac.findtext("output").strip(), "lag_rad_s": x.txt(ac, "lag"),
            "rate_deg_s": _switch_rate(fcs, base + "/rate"),
            "max_deg": x.txt(g, "gain") if g is not None else None,
            "clip_deg": [x.txt(clip, "min"), x.txt(clip, "max")] if clip is not None else None}
    return out


def flaps(fcs, setfile):
    """Flap / slat detents from the SFCC switches (/controls/flight/flaps-cmd, slats-cmd) + rates + options/maxflap."""
    fc, sc = _named(fcs, "switch", "/controls/flight/flaps-cmd"), _named(fcs, "switch", "/controls/flight/slats-cmd")
    flap_by_pos = {}
    for t in fc.findall("test"):
        flap_by_pos[int(re.search(r"flaps-pos eq (\d+)", x.cond_text(t)).group(1))] = float(t.get("value"))
    slat_tests = [(x.cond_text(t).split(), float(t.get("value"))) for t in sc.findall("test")]
    slat_by_input = {int(w[2]): v for w, v in slat_tests if w[1] == "eq"}
    slat_ge2 = next(v for w, v in slat_tests if w[1] == "ge" and w[2] == "2")
    maxflap = float(re.search(r"<maxflap[^>]*>([0-9.]+)<", Path(setfile).read_text(encoding="utf-8")).group(1))
    # lever detents 0, 1, 2, 3, FULL = SFCC flaps-input 0..4; "1" and "1+F" differ only in flap angle (flaps-pos 1 vs 2)
    det = [("0", 0.0, 0.0), ("1", slat_by_input[1], 0.0), ("1+F", slat_by_input[1], flap_by_pos[2]),
           ("2", slat_ge2, flap_by_pos[3]), ("3", slat_ge2, flap_by_pos[4]),
           ("FULL", slat_by_input[4], min(flap_by_pos[5], maxflap))]
    fl, sl = _named(fcs, "aerosurface_scale", "rubbish/flap-pos-norm"), _named(fcs, "aerosurface_scale", "rubbish/slat-pos-norm")
    return {"detents": [{"lever": n, "slat_deg": s, "flap_deg": f} for n, s, f in det],
            "flap_max_deg": x.txt(fl.find("domain"), "max"), "slat_max_deg": x.txt(sl.find("domain"), "max"),
            "flap_rate_deg_s": _switch_rate(fcs, "fcs/flap-pos-rate"), "slat_rate_deg_s": _switch_rate(fcs, "fcs/slat-pos-rate"),
            "full_flap_deg_for_this_engine_set": maxflap, "note": "JSBSim fcs/flap-pos-deg and fcs/slat-pos-deg; aero tables use them (+ slat-pos-norm)"}


def gear_transit(fcs):
    r = {}
    for u, n in ((0, "nose"), (1, "left_main"), (2, "right_main")):
        for sense, key in (("incr", "down_s"), ("decr", "up_s")):
            sw = _named(fcs, "switch", f"/systems/gear/unit[{u}]/rate-{sense}")
            hyd = [float(t.get("value")) for t in sw.findall("test") if "green-psi ge" in x.cond_text(t)]
            r.setdefault(n, {})[key] = round(1.0 / hyd[0], 2) if hyd and hyd[0] > 0 else None
    return r


def spoilers(sp):
    def tab(name):
        fn = _named(sp, "fcs_function", name)
        return x.table(fn.find("function").find("table"))
    g = _named(sp, "pure_gain", "/systems/fcs/spoiler-l2/cmd-deg")
    return {"lever_input_table": tab("spoilers/lever-input"), "main_cmd_table": tab("spoilers/main-cmd"),
            "max_deg": x.txt(g, "gain"), "panels_per_wing": 5, "rate_deg_s": _switch_rate(sp, "/systems/fcs/spoiler-l2/rate"),
            "lag_rad_s": x.txt(_named(sp, "actuator", "/systems/fcs/spoiler-l2/final-actuator"), "lag"),
            "outputs": {"left": "fcs/spoiler-left-deg", "right": "fcs/spoiler-right-deg", "symmetrical": "fcs/spoiler-symmetrical-deg"},
            "note": "ground spoilers (all 5 panels) / speedbrake (panels 2-4) / roll spoilers: upstream logic is in a320-spoilers.xml (not converted)"}


def collect_inputs(a):
    """Every property the aerodynamics read (expression properties and table lookup variables), minus its own functions."""
    names = set()

    def walk(e):
        if isinstance(e, dict):
            if "p" in e:
                names.add(e["p"])
            if "table" in e:
                names.update(v for v in (e["table"]["row"], e["table"]["col"], e["table"].get("layer")) if v)
            for v in e.values():
                walk(v)
        elif isinstance(e, list):
            for v in e:
                walk(v)
    walk([a["functions"], a["axes"]])
    own = {fn["name"] for fn in a["functions"]} | set(a.get("properties", {}))
    return sorted(names - own)


def build(spec, src: Path):
    base = src
    root = x.parse(base / spec["fde"])
    parts = {t: resolve(root.find(t), base, "") for t in ("aerodynamics", "external_reactions", "ground_reactions", "metrics")}
    unc = []
    a = x.aero(parts["aerodynamics"])
    used = collect_inputs(a)
    a["aero_inputs"] = {"jsbsim_builtin": [p for p in used if p.startswith(BUILTIN)],
                        "from_systems": [p for p in used if not p.startswith(BUILTIN)]}
    a["derived_from"] = spec["derived_from"]
    sysdir = base / "Systems"
    fcs, spo = x.parse(sysdir / "a320-fcs.xml"), x.parse(sysdir / "a320-spoilers.xml")
    fad = x.parse(sysdir / spec["fadec"])
    prop = root.find("propulsion")
    eng, thr_list, apu_cfg = [], [], None
    for e in prop.findall("engine"):
        er = resolve(e, base, "Engines")
        feed = x.txt(e, "feed", None, int)
        if er.get("name", "").startswith("APS"):
            apu_cfg = jt.apu(er, e.find("thruster"), feed)
            continue
        t = jt.turbine(er, e.find("thruster"), unc, er.get("name"))
        t["feed_tanks"] = [feed]
        eng.append(t)
    tk = tanks(prop)
    for s in root.findall("system"):
        unc.append({"where": "fde system", "name": s.get("file"), "why": "JSBSim system (control laws / systems): written in GDScript with JSBSim as oracle"})
    unc.append({"where": "external_reactions", "name": "tractor", "why": "pushback tug force: libresim has its own pushback"})
    cfg = {
        "name": spec["name"], "derived_from": spec["derived_from"], "license": "GPL-2.0-only (see third_party/a320-family/)",
        "metrics": metrics(parts["metrics"]), "mass": mass(root.find("mass_balance")),
        "gear": gear(parts["ground_reactions"], spec, unc), "tanks": tk,
        "unusable_fuel_kg": round(sum(t["unusable_l"] * t["density_kg_per_l"] for t in tk), 3),
        "engines": eng, "apu": apu_cfg,
        "controls": {"surfaces": surfaces(fcs), "flaps": flaps(fcs, base / spec["set"]),
                     "gear_transit": gear_transit(fcs), "spoilers": spoilers(spo)},
        "fadec_limits": jt.fadec_limits(fad, unc),
    }
    cfg["unconverted"] = unc
    return a, cfg
