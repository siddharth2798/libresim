"""Simulated ILS for the long runways -> data/processed/ils.json.

OurAirports has no ILS records, so these localizer/glideslope installations are
GENERATED for gameplay: geometry follows the real runways (localizer antenna 300 m
beyond the far end, glideslope antenna 300 m past the threshold, 120 m to the side,
3.0 deg path), but the FREQUENCIES and IDENTS ARE NOT REAL AIP DATA (marked
"simulated": true). Replace them with real values if you have an official source.
Run after 09_runways.py.
"""
import json
import math

import common as c

MIN_LENGTH = 2000.0
FREQS = [108.1 + 0.2 * k for k in range(20)]  # ILS channels: odd tenths 108.10 ... 111.90


def main():
    rw = json.loads((c.OUT / "runways.json").read_text())["runways"]
    out = []
    k = 0
    corr = {a["icao"] or a["ident"] for a in json.loads((c.OUT / "airports.json").read_text())
            if a.get("region") == "konkan_kerala"}
    # Mumbai-Pune first so its (simulated) channels stay stable; then the corridor
    for r in sorted(rw, key=lambda r: (r["airport"] in corr, r["airport"], -r["length"])):
        if r["length"] < MIN_LENGTH or not r["airport"][:2] in ("VA", "VO"):
            continue
        for i in (0, 1):
            thr, far = r["ends"][i], r["ends"][1 - i]
            dx, dy = far["x"] - thr["x"], far["y"] - thr["y"]
            L = math.hypot(dx, dy)
            ux, uy = dx / L, dy / L
            gs_x = thr["x"] + ux * 300.0 + uy * 120.0
            gs_y = thr["y"] + uy * 300.0 - ux * 120.0
            out.append({
                "airport": r["airport"], "runway": thr["ident"],
                "ident": "I" + r["airport"][2:] + thr["ident"][:2],
                "freq_mhz": round(FREQS[k % len(FREQS)], 2),
                "course_true": round(math.degrees(math.atan2(ux, uy)) % 360.0, 2),
                "loc": {"x": round(far["x"] + ux * 300.0, 1), "y": round(far["y"] + uy * 300.0, 1), "h": far["h"]},
                "gs": {"x": round(gs_x, 1), "y": round(gs_y, 1), "h": thr["h"]},
                "threshold": {"x": thr["x"], "y": thr["y"], "h": thr["h"]},
                "gs_deg": 3.0, "simulated": True,
            })
            k += 1
    (c.OUT / "ils.json").write_text(json.dumps(out, indent=1))
    for s in out:
        print(f'{s["airport"]} RWY {s["runway"]}: {s["ident"]} {s["freq_mhz"]:.2f} course {s["course_true"]:.0f}T (simulated)')


if __name__ == "__main__":
    main()
