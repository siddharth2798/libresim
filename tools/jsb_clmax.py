"""Deliberate deviation from the JSBSim data: CLmax of the A320 (docs/A320-STATUS.md "stall (CLmax)").

The upstream lift tables stall 10-20 % early (1 g speed at alpha-max 173.7 kt clean / 119.7 kt CONF FULL at 64 t
against the FMGC table Vs1g 155.4 / 109.2 kt, i.e. CLmax 2.2 against 2.65 in CONF FULL). Below alpha_on_deg (the
approach alphas) the lift curve is untouched. Above it the roll-off to the peak is stretched in alpha and in height, per
flap / slat detent, by one extra LIFT term
"aero/coefficient/CLmaxfix" = qbar * Sw * kCLge * boost(alpha, flap, slat) * mach fade, with (C = CLalpha table + CLflap +
CLslat at M 0.2, C0 = C(alpha_on), C_pk its peak at alpha_pk):
  C'(alpha) = C0 + k (C(alpha_on + (alpha - alpha_on) / lam) - C0),     boost = C' - C
  lam = (alpha_pk + shift_deg - alpha_on) / (alpha_pk - alpha_on),   k = (clmax_k C_pk - C0) / (C_pk - C0)
i.e. the old curve above alpha_on is stretched to a peak `shift_deg` higher in alpha and `clmax_k` times higher in
CL (alpha-max of the FBW follows the peak). The lift slope between alpha_on and the peak rises from about 0.05-0.07 to
0.10-0.11 per degree (the linear part, 0.083, is not exceeded much).
The boost is tabulated on the 3-D grid (alpha-deg, flap-pos-deg, slat-pos-deg) at the six detents; other
(slat, flap) pairs take the nearest detent. It fades out between Mach 0.40 and 0.55 (the tables' own transonic
buffet limit stays). Constants per detent: SPECS["a320"]["clmax"] in 06_jsbsim_to_json.py.
The FBW alpha limits for the new curve (fdm/fbw_params.gd alpha_deg rows) are printed by `report()`.
"""
import numpy as np

COLS_FLAP = [0.0, 10.0, 15.0, 20.0, 35.0]
LAYERS_SLAT = [0.0, 18.0, 22.0, 27.0]
ALPHA_ROWS = [-10.0, 7.5] + [8.0 + 0.5 * i for i in range(45)] + [35.0, 45.0]
MACH_FADE = {"rows": [0.0, 0.40, 0.55, 1.0], "data": [[1.0], [1.0], [0.0], [0.0]]}


def _lift_parts(a):
    lift = {f["name"]: f["f"] for f in a["axes"]["LIFT"]}
    t = lift["aero/coefficient/CLalpha"]["args"][-1]["table"]
    return t, lift["aero/coefficient/CLflap"]["args"][-1]["table"], lift["aero/coefficient/CLslat"]["args"][-1]["table"]


class Curve:
    """C(alpha_deg, slat_deg, flap_deg) at Mach 0.2 from the converted tables."""

    def __init__(self, a):
        t, tf, ts = _lift_parts(a)
        assert t["layers"] == [0.0, 1.0] and t["cols"][0] == 0.2, "CLalpha table layout changed"
        self.rows = np.array(t["rows"])
        self.layers = [np.array(layer)[:, 0] for layer in t["data"]]
        self.flap = (tf["rows"], [r[0] for r in tf["data"]])
        self.slat = (ts["rows"], [r[0] for r in ts["data"]])
        self.slat_max = LAYERS_SLAT[-1]

    def __call__(self, alpha, slat, flap):
        lo, hi = (np.interp(alpha, self.rows, v) for v in self.layers)
        base = lo + (hi - lo) * slat / self.slat_max
        return base + np.interp(flap, *self.flap) + np.interp(slat, *self.slat)


def boost_curve(curve, slat, flap, p, alphas):
    """boost(alpha) for one detent; p = {alpha_on_deg, shift_deg, clmax_k}. Returns (boost, old peak alpha, old CLmax, lam)."""
    fine = np.arange(0.0, 30.0, 0.01)
    c = curve(fine, slat, flap)
    a_pk, c_pk = float(fine[int(np.argmax(c))]), float(c.max())
    on = p["alpha_on_deg"]
    lam = (a_pk + p["shift_deg"] - on) / (a_pk - on)
    c0 = float(curve(on, slat, flap))
    k = (p["clmax_k"] * c_pk - c0) / (c_pk - c0)
    new = c0 + k * (curve(on + (alphas - on) / lam, slat, flap) - c0)
    return np.where(alphas > on, new - curve(alphas, slat, flap), 0.0), a_pk, c_pk, lam


def _nearest(detents, slat, flap):
    return min(detents, key=lambda d: abs(d["slat"] - slat) / 27.0 + abs(d["flap"] - flap) / 35.0)


def apply(a, spec):
    """Append the CLmaxfix term to a["axes"]["LIFT"] (spec: SPECS["a320"]["clmax"]). Returns the report rows."""
    cfg, curve = spec["clmax"], Curve(a)
    alphas = np.array(ALPHA_ROWS)
    per, rows = {}, []
    for name, d in cfg["detents"].items():
        p = {"alpha_on_deg": cfg["alpha_on_deg"], **d}
        per[name], a_pk, c_pk, lam = boost_curve(curve, d["slat"], d["flap"], p, alphas)
        rows.append({"conf": name, "peak_alpha_old": round(a_pk, 2), "clmax_old": round(c_pk, 3), "shift_deg": d["shift_deg"],
                     "clmax_k": d["clmax_k"], "lam": round(lam, 3)})
    names = list(cfg["detents"])
    detents = [{"name": n, **cfg["detents"][n]} for n in names]
    data = []
    for s in LAYERS_SLAT:
        layer = []
        for ai in range(len(alphas)):
            layer.append([round(float(per[_nearest(detents, s, f)["name"]][ai]), 5) for f in COLS_FLAP])
        data.append(layer)
    # table layout as jsb_expr.table (3-D): data[layer][row][col]
    tab = {"row": "aero/alpha-deg", "col": "fcs/flap-pos-deg", "layer": "fcs/slat-pos-deg", "cols": COLS_FLAP,
           "layers": LAYERS_SLAT, "rows": [float(x) for x in alphas], "data": data}
    fade = {"row": "velocities/mach", "col": None, "cols": None, **MACH_FADE}
    term = {"name": "aero/coefficient/CLmaxfix",
            "desc": "libresim: CLmax of the A320 raised to the FMGC Vs1g table (tools/jsb_clmax.py); not in the upstream FDE",
            "f": {"op": "product", "args": [{"p": "aero/qbar-psf"}, {"p": "metrics/Sw-sqft"}, {"p": "aero/function/kCLge"},
                                            {"table": tab}, {"table": fade}]}}
    lift = a["axes"]["LIFT"]
    lift.insert(next(i for i, f in enumerate(lift) if f["name"] == "aero/coefficient/CLslat") + 1, term)
    return rows
