"""ILS for the sim's runways -> data/processed/ils.json.

REAL where the AIP India lists an ILS (step 29 -> ils_aip.json, plus tools/ils_overrides.json): the real
ident, frequency, category and glide angle, one record per real runway end only (an airport with a real
ILS gets no invented ILS on its other ends), "simulated": false. Every other runway of 2000 m or more
at a VA/VO airport (and the airports whose AIP page lists no ILS at all) keeps a SIMULATED ILS for
gameplay: generated idents ("IBB27"), 20 cycling channels 108.10 ... 111.90 (a channel a real ILS uses
within 150 nm is skipped), "simulated": true. Geometry follows the runway for both kinds (localizer
antenna 300 m beyond the far end, glideslope antenna 300 m past the threshold and 120 m to the side).
The real antenna coordinates only check the course (ils_real.match), they do not move the antennas.
Optional fields (older readers ignore them): "category" (1-3), "source". Run after 09_runways.py, 29_ils_aip.py.
"""
import json
import math

import common as c
import ils_real

MIN_LENGTH = 2000.0
FREQS = [108.1 + 0.2 * k for k in range(20)]  # ILS channels: odd tenths 108.10 ... 111.90
SIM_WHERE_AIP_HAS_NONE = True  # airports whose AIP page lists no ILS (VOSH, VOSR) still get a simulated one


def record(r, i, ident, freq, gs_deg, simulated, category=None, source=None):
    thr, far = r["ends"][i], r["ends"][1 - i]
    dx, dy = far["x"] - thr["x"], far["y"] - thr["y"]
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    gs_x = thr["x"] + ux * 300.0 + uy * 120.0
    gs_y = thr["y"] + uy * 300.0 - ux * 120.0
    out = {
        "airport": r["airport"], "runway": thr["ident"], "ident": ident, "freq_mhz": round(freq, 2),
        "course_true": round(math.degrees(math.atan2(ux, uy)) % 360.0, 2),
        "loc": {"x": round(far["x"] + ux * 300.0, 1), "y": round(far["y"] + uy * 300.0, 1), "h": far["h"]},
        "gs": {"x": round(gs_x, 1), "y": round(gs_y, 1), "h": thr["h"]},
        "threshold": {"x": thr["x"], "y": thr["y"], "h": thr["h"]},
        "gs_deg": gs_deg, "simulated": simulated,
    }
    if category:
        out["category"] = category
    if source:
        out["source"] = source
    return out


def pick_channel(k, blocked, taken):
    """The k-th channel of the cycle, or the next one a real ILS nearby does not use."""
    for n in range(len(FREQS)):
        f = round(FREQS[(k + n) % len(FREQS)], 2)
        if f not in blocked and f not in taken:
            return f
    return round(FREQS[k % len(FREQS)], 2)


def build(rw, airports, corr, recs, pages, fwd):
    """-> (ils list, log lines). rw: runways.json records; airports: ICAO -> (x, y); corr: corridor ICAOs."""
    real, log = ils_real.match(rw, recs, fwd)
    out, k = [], 0
    real_ap = {a for a, _ in real}
    taken = {}  # airport -> frequencies of its own simulated ILS, so they stay distinct
    # Mumbai-Pune first so its (simulated) channels stay stable; then the corridor
    for r in sorted(rw, key=lambda r: (r["airport"] in corr, r["airport"], -r["length"])):
        ap = r["airport"]
        for i in (0, 1):
            end = r["ends"][i]["ident"]
            rec = real.get((ap, end))
            if rec is not None:
                out.append(record(r, i, rec["ident"], rec["freq_mhz"], rec.get("gs_deg") or 3.0, False,
                                  rec.get("category"), rec.get("source")))
        if r["length"] < MIN_LENGTH or not ap[:2] in ("VA", "VO"):
            continue
        sim_ok = ap not in real_ap and (ap not in pages or SIM_WHERE_AIP_HAS_NONE)
        for i in (0, 1):
            if sim_ok:
                f = pick_channel(k, ils_real.blocked_freqs(real, airports, ap), taken.setdefault(ap, set()))
                taken[ap].add(f)
                out.append(record(r, i, "I" + ap[2:] + r["ends"][i]["ident"][:2], f, 3.0, True))
            k += 1
    return out, log


def main():
    rw = json.loads((c.OUT / "runways.json").read_text())["runways"]
    ap = json.loads((c.OUT / "airports.json").read_text())
    corr = {a["icao"] or a["ident"] for a in ap if a.get("region") == "konkan_kerala"}
    airports = {a["icao"] or a["ident"]: (a["x"], a["y"]) for a in ap}
    aip_file = c.OUT / "ils_aip.json"
    aip = json.loads(aip_file.read_text()) if aip_file.exists() else None
    recs, pages = ils_real.records(aip, ils_real.load_overrides(c.ROOT / "tools" / "ils_overrides.json"))
    out, log = build(rw, airports, corr, recs, pages, c.transformer())
    (c.OUT / "ils.json").write_text(json.dumps(out, indent=1))
    for line in log:
        print("ils: " + line)
    for s in out:
        tag = "simulated" if s["simulated"] else "REAL" + (f' CAT {s["category"]}' if s.get("category") else "")
        print(f'{s["airport"]} RWY {s["runway"]}: {s["ident"]} {s["freq_mhz"]:.2f} course {s["course_true"]:.0f}T ({tag})')
    n_real = sum(1 for s in out if not s["simulated"])
    print(f"ils: {n_real} real, {len(out) - n_real} simulated runway ends, {len({s['airport'] for s in out if not s['simulated']})} airports with a real ILS")


if __name__ == "__main__":
    main()
