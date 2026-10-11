"""Merged OSM runways + taxiways -> data/processed/runways.json (for rendering and start positions).

runways:  [{airport, ends: [{ident, x, y, h, heading_true}, {...}], width, length}]
taxiways: [{width, pts: [[x, y, h], ...]}]   (heights sampled from the flattened DEM)
Run after 02_dem_tiles.py (both regions: re-run once the corridor level-0 heights exist).
"""
import json
import math

import numpy as np

import common as c
import flatten

TAXI_W = 15.0
MISSING = set()  # level-0 height tiles not generated yet (heights 0 there)


def load_heights():
    meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
    n = meta["tile_n"]
    cache = {}

    def h(x, y):
        tx, ty = math.floor(x / c.TILE_SIZE), math.floor(y / c.TILE_SIZE)
        if (tx, ty) not in cache:
            p = c.OUT / "terrain" / "h" / "0" / f"{tx}_{ty}.r16"
            cache[(tx, ty)] = (np.fromfile(p, "<u2").reshape(n + 1, n + 1) * meta["h_scale"] + meta["h_offset"]
                               if p.exists() else np.zeros((n + 1, n + 1)))
            if not p.exists():
                MISSING.add((tx, ty))

        a = cache[(tx, ty)]
        fx, fy = (x - tx * c.TILE_SIZE) / c.DEM_RES, (y - ty * c.TILE_SIZE) / c.DEM_RES
        i, j = min(int(fx), n - 1), min(int(fy), n - 1)
        u, v = fx - i, fy - j
        return float((a[j, i] * (1 - u) + a[j, i + 1] * u) * (1 - v) + (a[j + 1, i] * (1 - u) + a[j + 1, i + 1] * u) * v)
    return h


def ident(hdg):
    n = round(hdg / 10) % 36
    return f"{n or 36:02d}"


def drop_shadow_runways(merged, max_offset=300.0, max_angle_deg=5.0):
    """OSM sometimes tags a parallel taxiway or an old strip as aeroway=runway (e.g. VOGO: an
    unnamed 1289 m "08/26" 145 m south of the real runway). Drop a runway that has no published
    designator (no "nn/nn" ref) and lies parallel to, within max_offset m of, and alongside a
    longer runway. Returns (kept [(p0, p1, w, refs)], dropped [(p0, p1, w)])."""
    keep, drop = [], []
    for i, (p0, p1, w, refs) in enumerate(merged):
        L = np.hypot(*(p1 - p0))
        u = (p1 - p0) / L
        shadow = False
        for j, (q0, q1, _, _) in enumerate(merged):
            M = np.hypot(*(q1 - q0))
            if j == i or refs or M <= L:
                continue
            v = (q1 - q0) / M
            if abs(float(u @ v)) < math.cos(math.radians(max_angle_deg)):
                continue
            mid = (p0 + p1) / 2 - q0
            along = float(mid @ v)
            if abs(float(mid[0] * v[1] - mid[1] * v[0])) < max_offset and -L / 2 < along < M + L / 2:
                shadow = True
                break
        (drop if shadow else keep).append((p0, p1, w) if shadow else (p0, p1, w, refs))
    for p0, p1, w in drop:
        print(f"dropped runway-tagged parallel strip {np.hypot(*(p1 - p0)):.0f} m at ({p0[0]:.0f}, {p0[1]:.0f})")
    return keep, drop


def main():
    h = load_heights()
    osm = json.loads((c.OUT / "osm" / "aeroways.json").read_text())
    airports = json.loads((c.OUT / "airports.json").read_text())
    rwy_lines = [l for l in osm["lines"] if l["kind"] == "runway"]
    runways = []
    merged = []
    for p0, p1, w in flatten.merge_runways(rwy_lines):
        mid = (p0 + p1) / 2
        refs = [l["ref"] for l in rwy_lines if "/" in l["ref"] and
                min(math.hypot(x - mid[0], y - mid[1]) for x, y in l["pts"]) < np.hypot(*(p1 - p0)) / 2 + 50]
        merged.append((p0, p1, w, refs))
    merged, shadows = drop_shadow_runways(merged)
    for p0, p1, w, refs in merged:
        mid = (p0 + p1) / 2
        ap = min(airports, key=lambda a: math.hypot(a["x"] - mid[0], a["y"] - mid[1]))
        ends = []
        for a, b in ((p0, p1), (p1, p0)):
            hdg = math.degrees(math.atan2(b[0] - a[0], b[1] - a[1])) % 360  # grid north == true north here
            name = ident(hdg)
            # prefer a published designator (OSM ref) within 25 deg of this end's heading
            cands = [r for ref in refs for r in ref.split("/")]
            diff = lambda r: abs((int("".join(ch for ch in r if ch.isdigit()) or 0) * 10 - hdg + 180) % 360 - 180)
            if cands and diff(min(cands, key=diff)) < 25:
                name = min(cands, key=diff)
            ends.append({"ident": name, "x": round(float(a[0]), 1), "y": round(float(a[1]), 1),
                         "h": round(h(*a), 2), "heading_true": round(hdg, 2)})
        runways.append({"airport": ap["icao"] or ap["ident"], "width": w,
                        "length": round(float(np.hypot(*(p1 - p0))), 1), "ends": ends})
    taxiways = []
    for p0, p1, w in shadows:  # mis-tagged parallel taxiways: keep them paved, as taxiways
        taxiways.append({"width": min(w, 23.0), "pts": [[round(float(x), 1), round(float(y), 1), round(h(x, y), 2)]
                                                         for x, y in (p0, p1)]})
    for l in osm["lines"]:
        if l["kind"] == "taxiway":
            taxiways.append({"width": flatten._width(l["width"], TAXI_W),
                             "pts": [[x, y, round(h(x, y), 2)] for x, y in l["pts"]]})
    (c.OUT / "runways.json").write_text(json.dumps({"runways": runways, "taxiways": taxiways}))
    for r in runways:
        print(r["airport"], "/".join(e["ident"] for e in r["ends"]), f'{r["length"]:.0f} m x {r["width"]:.0f} m')
    print("taxiways:", len(taxiways))
    if MISSING:
        print(f"WARNING: {len(MISSING)} level-0 height tiles missing, heights there are 0; re-run after 02: "
              + " ".join(f"{a}_{b}" for a, b in sorted(MISSING)))


if __name__ == "__main__":
    main()
