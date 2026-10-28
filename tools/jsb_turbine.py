"""JSBSim <turbine_engine> (+ <thruster file="direct"> placement + FADEC limit tables) -> config.json "engines" entry.

Engine entry written to config.json (SI units; all tables are jsb_expr TABLE dicts, see jsb_expr.py):
  {"type": "turbine", "model": "CFM56-5B4",
   "thrust_n": sea-level static thrust (JSBSim <milthrust>),
   "max_rpm": 100.0 (N1 shown as percent), "idle_n1", "max_n1", "idle_n2", "max_n2": fractions of 100 % N1 / N2,
   "spool_up_s", "spool_down_s": first-order time constants that reproduce JSBSim's N1 spool time (fit, see spool_tau),
   "tsfc_kg_per_n_s": JSBSim <tsfc> (lb/lbf/h) in SI,
   "pos_m": thruster location, "orient_deg": {"roll","pitch","yaw"} nozzle toe/pitch, "feed_tanks": [tank indices],
   "thrust_table":       {mach x density-altitude(ft)} -> MilThrust factor (x thrust_n x FADEC rated factor),
   "idle_thrust_table":  {mach x density-altitude(ft)} -> idle thrust as a fraction of thrust_n,
   "reverser_loss_table": {reverser position 0..1} -> thrust factor (0.65 fully deployed),
   "rated_thrust_factor": name of the JSBSim property the FADEC system computes (1.0 when not de-rated),
   "n1_spool_up_rate_table" / "n1_spool_down_rate_table": {n1 percent} -> percent N1 per second (JSBSim N1SpoolUp/Down,
                         column = autoconfig-running 0 / 1: we keep the normal column 0),
   "jsbsim": {raw JSBSim values: ignitionn1, ignitionn2, n1/n2 startrate, spinup/spindown, bleed, bypassratio...}}
Thrust, as JSBSim computes it (FGTurbine, from its source as remembered; checked against tools/a320_reference.json):
  idle = thrust_n * idle_thrust_table(mach, alt);  mil = (thrust_n - idle) * thrust_table(...) * rated_thrust_factor * reverser_loss
  thrust = idle + mil * N2norm^2,  N2norm = (N2 - idle_n2) / (max_n2 - idle_n2)  (0 at idle, 1 at max).
Fuel flow = thrust * tsfc (corrected by sqrt(T / 518.67 R)).
"""
import jsb_expr as x

FADEC_LIMITS = ("rated-thrust-n1", "toga-table", "flex-table", "mct-table", "climb-table", "idle-table", "mrev-table")
LBF_S_TO_SI = 0.45359237 / (4.4482216152605 * 3600.0)  # lb/(lbf h) -> kg/(N s)


def _interp(rows, vals, v):
    if v <= rows[0]:
        return vals[0]
    for i in range(1, len(rows)):
        if v <= rows[i]:
            f = (v - rows[i - 1]) / (rows[i] - rows[i - 1])
            return vals[i - 1] + f * (vals[i] - vals[i - 1])
    return vals[-1]


def spool_tau(tab, idle, top):
    """First-order tau (s) whose 90 % rise time equals JSBSim's idle -> 90 % time with the rate table (percent N1 per s)."""
    rows, rates = tab["rows"], [d[0] for d in tab["data"]]
    goal, n, t, dn = idle + 0.9 * (top - idle), idle, 0.0, 0.01
    while n < goal:
        t += dn / max(_interp(rows, rates, n), 1e-6)
        n += dn
    return t / 2.302585


def _col0(t):
    """2-column rate table (column breakpoints 0 / 1) -> 1-D table keeping column 0."""
    return {"row": t["row"], "col": None, "cols": None, "rows": t["rows"], "data": [[d[0]] for d in t["data"]]}


def turbine(eng, thr, unconverted, name):
    """eng = <turbine_engine> root, thr = the <thruster> element of the aircraft <engine>."""
    f = {t.get("name"): t for t in eng.findall("function")}
    t = lambda tag, d=None: x.txt(eng, tag, d)
    idle_n1, max_n1 = t("idlen1") / 100.0, t("maxn1") / 100.0
    mil_prod = f["MilThrust"].find("product")
    mil_tab = [x.table(e) for e in mil_prod.findall("table")]
    out = {
        "type": "turbine", "model": eng.get("name"),
        "thrust_n": t("milthrust") * x.FORCE["LBS"], "max_rpm": 100.0,
        "idle_n1": idle_n1, "max_n1": max_n1, "idle_n2": t("idlen2") / 100.0, "max_n2": t("maxn2") / 100.0,
        "tsfc_kg_per_n_s": t("tsfc") * LBF_S_TO_SI,
        "pos_m": x.unit_loc(thr.find("location")),
    }
    o = thr.find("orient")
    if o is not None:
        out["orient_deg"] = {k: x.txt(o, k) for k in ("roll", "pitch", "yaw")}
    if "N1SpoolUp" in f:
        up, dn = _col0(x.table(f["N1SpoolUp"].find("table"))), _col0(x.table(f["N1SpoolDown"].find("table")))
        out["n1_spool_up_rate_table"], out["n1_spool_down_rate_table"] = up, dn
        out["spool_up_s"] = round(spool_tau(up, idle_n1 * 100, max_n1 * 100), 3)
        out["spool_down_s"] = round(spool_tau(dn, idle_n1 * 100, max_n1 * 100), 3)
    out["thrust_table"] = mil_tab[0]
    out["idle_thrust_table"] = x.table(f["IdleThrust"].find("table"))
    if len(mil_tab) > 1:
        out["reverser_loss_table"] = mil_tab[1]
    props = [p.text.strip() for p in mil_prod.findall("property")]
    out["rated_thrust_factor"] = props[0] if props else None
    out["jsbsim"] = {k: t(k) for k in ("ignitionn1", "ignitionn2", "n1spinup", "n2spinup", "n1spindown", "n2spindown",
                                       "n1startrate", "n2startrate", "bleed", "bypassratio", "augmented", "injected")
                     if t(k) is not None}
    known = {"description", "milthrust", "tsfc", "bleed", "ignitionn1", "ignitionn2", "n1spinup", "n2spinup", "n1spindown",
             "n2spindown", "n1startrate", "n2startrate", "idlen1", "idlen2", "maxn1", "maxn2", "augmented",
             "injected", "function", "bypassratio", "disable-windmill"}
    for e in eng:
        if e.tag not in known and e.tag is not x.ET.Comment:
            unconverted.append({"where": name, "name": e.tag, "why": "engine element not translated"})
    return out


def apu(eng, thr, feed):
    """The APS3200 is modelled by upstream as a third JSBSim engine; we keep it out of "engines" (it makes no thrust we fly with)."""
    return {"model": eng.get("name"), "thrust_n": x.txt(eng, "milthrust") * x.FORCE["LBS"],
            "tsfc_kg_per_n_s": x.txt(eng, "tsfc") * LBF_S_TO_SI, "feed_tanks": [feed],
            "note": "upstream JSBSim engine #3 (APS3200); an APU system (systems/apu.gd) uses it, not the flight model"}


def fadec_limits(sysroot, unconverted):
    """N1 limit tables of the FADEC system file: {name: function} (rows altitude ft, columns TAT C or flex temp)."""
    out = {}
    for fn in sysroot.iter("fcs_function"):
        n = (fn.get("name") or "")
        if n.startswith("/systems/fadec/limit/") and n.rsplit("/", 1)[1] in FADEC_LIMITS:
            r = x.try_function(_wrap(fn), unconverted, "fadec")
            if r:
                out[n.rsplit("/", 1)[1]] = r
    return out


def _wrap(fn):
    """fcs_function(<function><body/></function>) -> a node function() understands (name + single body)."""
    body = fn.find("function")
    w = x.ET.Element("function", {"name": fn.get("name")})
    for e in body:
        w.append(e)
    return w
