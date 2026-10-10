"""Landmark terminal models: OSM footprints (15_terminals.py) + per-airport recipes
(terminal_styles.py) -> data/processed/terminals/<ICAO>.glb and <ICAO>_model.json
({icao, origin [east, north, ground h], extent [w, h], signs [...]}) for world/terminals.gd.
Also writes terminals/landmarks.json (footprints in world metres) so that
10_buildings.py leaves those buildings out of the generic extruded city.

Run after 15_terminals.py, then re-run 10_buildings.py.
    python 16_terminal_models.py [VABB VAPO VOCI]
"""
import csv
import importlib
import json
import sys

import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union

import common as c
from glb_writer import Glb
import terminal_styles as ts

DIR = c.OUT / "terminals"


def ground_height(icao, e, n):
    try:  # the DEM where we have it (Mumbai-Pune region) ...
        hts = importlib.import_module("10_buildings").Heights(int(e // c.TILE_SIZE), int(n // c.TILE_SIZE))
        if np.any(hts.a):
            return float(hts.at(np.array([e]), np.array([n]))[0])
    except Exception:  # noqa: BLE001
        pass
    with open(c.RAW / "ourairports" / "airports.csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):  # ... else the published aerodrome elevation
            if r["ident"] == icao:
                return float(r["elevation_ft"] or 0) * 0.3048
    return 0.0


def build(icao):
    d = json.loads((DIR / f"{icao}.json").read_text())
    big = [t for t in d["terminals"] if t["area_m2"] > 5000.0]
    o = np.mean([t["centroid"] for t in big], 0)

    def poly(f):
        shells = [Polygon(np.asarray(r) - o) for r in f["outers"]]
        holes = [Polygon(np.asarray(r) - o) for r in f.get("inners", [])]
        p = unary_union([s.buffer(0) for s in shells])
        for h in holes:
            p = p.difference(h.buffer(0))
        return p.simplify(0.5)

    shift = lambda f: {**f, "line": (np.asarray(f["line"]) - o).tolist()}  # noqa: E731
    ctx = {"poly": poly,
           "by_osm": {f["osm"]: poly(f) for f in d["terminals"]},
           "parts": d.get("parts", []), "car_parks": d.get("car_parks", []),
           "jet_bridges": [shift(j) for j in d.get("jet_bridges", [])],
           "elevated_roads": [shift(r) for r in d.get("elevated_roads", [])]}
    g = Glb()
    landmarks, signs = ts.RECIPES[icao](g, ctx)
    g.save(DIR / f"{icao}.glb")
    h0 = ground_height(icao, *o)
    b = unary_union(landmarks).bounds
    meta = {"icao": icao, "origin": [round(float(o[0]), 2), round(float(o[1]), 2), round(h0, 2)],
            "extent": [b[2] - b[0], b[3] - b[1]], "signs": signs,
            "focus": [[round(lm.centroid.x, 1), round(lm.centroid.y, 1), round(max(lm.bounds[2] - lm.bounds[0],
                       lm.bounds[3] - lm.bounds[1]), 1)] for lm in landmarks]}
    (DIR / f"{icao}_model.json").write_text(json.dumps(meta, indent=1))
    rings = [(np.asarray(p.exterior.coords) + o).round(1).tolist() for lm in landmarks for p in ts.tg.polys(lm)]
    tris = sum(len(i) for p in g.prims.values() for i in p[2]) // 3
    print(f"{icao}: {len(landmarks)} landmark footprints, {tris} triangles, ground {h0:.1f} m, "
          f"{(DIR / f'{icao}.glb').stat().st_size / 1e6:.1f} MB")
    return icao, rings


def main():
    icaos = sys.argv[1:] or list(ts.RECIPES)
    lm_path = DIR / "landmarks.json"
    lm = json.loads(lm_path.read_text()) if lm_path.exists() else {}
    for icao in icaos:
        k, rings = build(icao)
        lm[k] = rings
    lm_path.write_text(json.dumps(lm))


if __name__ == "__main__":
    main()
