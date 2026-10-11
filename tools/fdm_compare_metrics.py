"""Metrics and plots for tools/18_compare_fdm.py (ours_<m>.csv vs jsb_<m>.csv)."""
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

OURS, JSB = "#2a78d6", "#eb6834"  # categorical slots 1, 2
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e4e3df"
PLOTS = {  # manoeuvre -> channels to plot
    "hands_off": ["phi", "psi", "beta", "alt_ft"], "takeoff": ["kcas", "theta", "agl_ft", "y_ft"],
    "climb": ["vs_fpm", "kcas", "theta", "rpm"], "aileron_step": ["p", "phi", "r", "beta"],
    "elevator_doublet": ["q", "theta", "kcas", "alt_ft"], "rudder_doublet": ["r", "beta", "p", "phi"],
    "stall_clean": ["kcas", "alpha", "theta", "alt_ft"], "stall_flaps": ["kcas", "alpha", "theta", "alt_ft"],
    "glide": ["vs_fpm", "kcas", "theta", "alpha"], "landing": ["agl_ft", "kcas", "vs_fpm", "x_ft"],
    "crosswind_takeoff": ["kcas", "psi", "y_ft", "phi"]}


def save(cols, rows, path: Path):
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        w.writerows(rows)


def load(path: Path) -> dict:
    with open(path) as fh:
        r = csv.reader(fh)
        head = next(r)
        data = np.array([[float(x) for x in row] for row in r])
    return {h: data[:, i] for i, h in enumerate(head)}


def val(d, col, t):
    return float(np.interp(t, d["t"], d[col]))


def mean(d, col, t0, t1):
    m = (d["t"] >= t0) & (d["t"] <= t1)
    return float(np.mean(d[col][m]))


def wrap180(a):
    return (a + 180.0) % 360.0 - 180.0


def period_damping(d, col, t0):
    """Period (s) and damping ratio from the peaks of col about its mean after t0."""
    m = d["t"] >= t0
    t, y = d["t"][m], d[col][m]
    y = y - np.mean(y[len(y) // 2:]) if col in ("kcas", "alt_ft") else y
    pk = [i for i in range(1, len(y) - 1) if y[i] >= y[i - 1] and y[i] > y[i + 1] and y[i] > 0]
    pk = [i for i in pk if abs(y[i]) > 0.02 * np.max(np.abs(y))]
    if len(pk) < 2:
        return float("nan"), float("nan")
    per = float(t[pk[1]] - t[pk[0]])
    dec = np.log(y[pk[0]] / y[pk[1]]) if y[pk[1]] > 0 else float("nan")
    zeta = float(dec / np.sqrt(4 * np.pi ** 2 + dec ** 2))
    return per, zeta


def liftoff(d):
    idx = np.where(d["wow"] < 0.5)[0]
    return idx[0] if len(idx) else len(d["t"]) - 1


def metrics(name: str, d: dict) -> dict:
    t_end = float(d["t"][-1])
    if name == "hands_off":
        return {"trim pitch deg": d["theta"][0], "trim throttle": d["throttle"][0], "trim pitch-trim": d["trim"][0],
                "cruise RPM": d["rpm"][0], "cruise hp": d["hp"][0], "bank @10 s deg": val(d, "phi", 10),
                "bank @30 s deg": val(d, "phi", 30), "bank @60 s deg": val(d, "phi", 60),
                "heading change 60 s deg": wrap180(val(d, "psi", 60) - d["psi"][0]),
                "alt change 60 s ft": val(d, "alt_ft", 60) - d["alt_ft"][0]}
    if name in ("takeoff", "crosswind_takeoff"):
        i = liftoff(d)
        out = {"liftoff dist ft": d["x_ft"][i], "liftoff KCAS": d["kcas"][i], "dist to 50 ft": d["x_ft"][-1],
               "time to 50 ft s": t_end}
        if name == "crosswind_takeoff":
            out["max lateral dev ft"] = float(np.max(np.abs(d["y_ft"][: i + 1])))
            out["max heading err deg"] = float(np.max(np.abs(wrap180(d["psi"][: i + 1]))))
        return out
    if name == "climb":
        return {"ROC fpm": mean(d, "vs_fpm", 20, 60), "pitch deg": mean(d, "theta", 20, 60),
                "RPM": mean(d, "rpm", 20, 60), "hp": mean(d, "hp", 20, 60), "alpha deg": mean(d, "alpha", 20, 60)}
    if name == "aileron_step":
        return {"peak roll rate deg/s": float(np.max(d["p"])), "bank @4 s deg": val(d, "phi", 4.0),
                "time to 30 deg bank s": float(np.interp(30.0, d["phi"], d["t"])) - 1.0 if np.max(d["phi"]) > 30 else float("nan"),
                "yaw rate @2 s deg/s": val(d, "r", 2.0)}
    if name == "elevator_doublet":
        per, z = period_damping(d, "kcas", 6.0)
        return {"peak pitch rate deg/s": float(np.max(d["q"])), "phugoid period s": per, "phugoid damping": z,
                "kcas swing kt": float(np.ptp(d["kcas"][d["t"] > 6]))}
    if name == "rudder_doublet":
        per, z = period_damping(d, "r", 3.0)
        return {"peak yaw rate deg/s": float(np.max(np.abs(d["r"]))), "peak sideslip deg": float(np.max(np.abs(d["beta"]))),
                "dutch roll period s": per, "dutch roll damping": z}
    if name.startswith("stall"):
        k = int(np.argmax(d["alpha"]))
        return {"min KCAS": float(np.min(d["kcas"][: k + 1])), "max alpha deg": d["alpha"][k],
                "time of max alpha s": d["t"][k], "alt lost ft": d["alt_ft"][0] - float(np.min(d["alt_ft"]))}
    if name == "glide":
        m = (d["t"] >= 30)
        dist = d["x_ft"][m][-1] - d["x_ft"][m][0]
        dh = d["alt_ft"][m][0] - d["alt_ft"][m][-1]
        return {"sink fpm": -mean(d, "vs_fpm", 30, 90), "glide ratio": dist / dh if dh > 0 else float("nan"),
                "pitch deg": mean(d, "theta", 30, 90), "alpha deg": mean(d, "alpha", 30, 90)}
    if name == "landing":
        i = int(np.argmax(d["wow"] > 0.5))
        return {"air dist 50 ft->TD ft": d["x_ft"][i], "touchdown KCAS": d["kcas"][i],
                "touchdown VS fpm": d["vs_fpm"][max(i - 1, 0)], "ground roll ft": d["x_ft"][-1] - d["x_ft"][i],
                "total ft": d["x_ft"][-1]}
    return {}


def plot(out: Path, name: str, o: dict, j: dict):
    cols = PLOTS[name]
    fig, axs = plt.subplots(len(cols), 1, figsize=(8, 2.0 * len(cols)), sharex=True)
    for ax, col in zip(axs, cols):
        for d, c, lab in ((o, OURS, "ours"), (j, JSB, "JSBSim c172p")):
            y = d[col]
            if col == "psi":
                y = wrap180(y)
            ax.plot(d["t"], y, color=c, lw=1.6, label=lab)
        ax.set_ylabel(col, color=INK2)
        ax.grid(color=GRID, lw=0.6)
        for s in ("top", "right"):
            ax.spines[s].set_visible(False)
        ax.tick_params(colors=INK2, labelsize=8)
    axs[0].legend(loc="best", frameon=False, fontsize=8)
    axs[0].set_title(name.replace("_", " "), color=INK, loc="left")
    axs[-1].set_xlabel("t (s)", color=INK2)
    fig.tight_layout()
    fig.savefig(out / f"{name}.png", dpi=90)
    plt.close(fig)


def report(out: Path, manoeuvres):
    lines = ["| manoeuvre | metric | ours | JSBSim | diff % |", "|---|---|---:|---:|---:|"]
    for name in manoeuvres:
        po, pj = out / f"ours_{name}.csv", out / f"jsb_{name}.csv"
        if not (po.exists() and pj.exists()):
            continue
        o, j = load(po), load(pj)
        plot(out, name, o, j)
        mo, mj = metrics(name, o), metrics(name, j)
        for k in mo:
            a, b = float(mo[k]), float(mj.get(k, float("nan")))
            pct = (a - b) / abs(b) * 100.0 if abs(b) > 1e-6 and np.isfinite(b) else float("nan")
            lines.append(f"| {name} | {k} | {a:.2f} | {b:.2f} | {pct:+.0f} |")
    text = "\n".join(lines)
    (out / "metrics.md").write_text(text + "\n")
    print(text)
