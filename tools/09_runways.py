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


def main():
    h = load_heights()
    osm = json.loads((c.OUT / "osm" / "aeroways.json").read_text())
    airports = json.loads((c.OUT / "airports.json").read_text())
    rwy_lines = [l for l in osm["lines"] if l["kind"] == "runway"]
    runways = []
    for p0, p1, w in flatten.merge_runways(rwy_lines):
        mid = (p0 + p1) / 2
        refs = [l["ref"] for l in rwy_lines if "/" in l["ref"] and
                min(math.hypot(x - mid[0], y - mid[1]) for x, y in l["pts"]) < np.hypot(*(p1 - p0)) / 2 + 50]
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
