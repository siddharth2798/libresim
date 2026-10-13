"""Apron ground roughness report: how bumpy is the level-0 terrain (30 m samples) where aircraft
park and taxi? Used before/after tools/apron_flatten.py (step 17) and as a QA tool. Reads the
tiles on disk (any region); needs 04 (apron polygons, buildings), 13 (stands) and 15 (terminals).

Per airport:
  stand     every stand / gate disc of STAND_R metres (>= 3 samples): peak-to-peak height. Reported as
            median / p90 / max over the stands and the share of stands that are not flat (> 1.5 m).
  apron     each OSM aeroway=apron polygon: std of the heights after removing the best-fit plane
            (area-weighted mean) and the largest peak-to-peak.
  ring      10..60 m ring around terminal / hangar-sized buildings in the aerodrome: where DSM walls
            and roofs leak into the ground next to a building. r = height minus its 5x5 median;
            reported as p98 |r| and max |r|, and the share of samples 0.8 m above a neighbour.
  terminal  where a landmark terminal model exists: the terrain around / inside each big terminal
            against the model origin height (16 raises every vertex by terrain - origin).
Usage: apron_roughness.py [ICAO ...] [--json out.json]
"""
import json
import sys

import numpy as np
import shapely
from scipy.ndimage import median_filter

import apron_flatten as AF
import common as c
from airport_fixups_io import N, Tiles

STAND_R = 45.0
RING = (10.0, 60.0)
BIG_BUILDING_M2 = 600.0
DEFAULT = ["VABB", "VANM", "VAPO", "VOCI", "VOCL", "VOGO", "VOGA", "VOML", "VOKN", "VAJJ"]


class Ground:
    """Level-0 heights over a box, read straight from the tiles (any region)."""

    def __init__(self, lo, hi, tiles=None):
        t = tiles or Tiles()
        tx0, ty0 = (int(np.floor(v / c.TILE_SIZE)) for v in lo)
        tx1, ty1 = (int(np.floor(v / c.TILE_SIZE)) for v in hi)
        self.x0, self.y0 = tx0 * c.TILE_SIZE, ty0 * c.TILE_SIZE
        nx, ny = tx1 - tx0 + 1, ty1 - ty0 + 1
        self.h = np.zeros((ny * N + 1, nx * N + 1))
        for j in range(ny):
            for i in range(nx):
                a = t.read_h(0, tx0 + i, ty0 + j)
                if a is not None:
                    self.h[j * N:(j + 1) * N + 1, i * N:(i + 1) * N + 1] = a
        self.X, self.Y = np.meshgrid(self.x0 + np.arange(self.h.shape[1]) * c.DEM_RES,
                                     self.y0 + np.arange(self.h.shape[0]) * c.DEM_RES)

    def zone(self, geom):
        return shapely.contains_xy(geom, self.X, self.Y)


def plane_std(g, mask):
    x, y, z = g.X[mask], g.Y[mask], g.h[mask]
    A = np.c_[x - x.mean(), y - y.mean(), np.ones(len(z))]
    res = z - A @ np.linalg.lstsq(A, z, rcond=None)[0]
    return float(res.std())


def stand_stats(g, pts):
    ptp = []
    for x, y in pts:
        m = (g.X - x) ** 2 + (g.Y - y) ** 2 < STAND_R ** 2
        if m.sum() >= 3:
            ptp.append(float(np.ptp(g.h[m])))
    p = np.array(ptp)
    return {"n": len(p), "median": float(np.median(p)), "p90": float(np.percentile(p, 90)),
            "max": float(p.max()), "share_bumpy": float((p > 1.5).mean())} if len(p) else {"n": 0}


def apron_stats(g, polys):
    rows = [(shapely.area(p), plane_std(g, g.zone(p)), float(np.ptp(g.h[g.zone(p)])))
            for p in polys if g.zone(p).sum() >= 6]
    if not rows:
        return {"n": 0}
    a = np.array(rows)
    return {"n": len(a), "std": float((a[:, 0] * a[:, 1]).sum() / a[:, 0].sum()), "max_ptp": float(a[:, 2].max())}


def ring_stats(g, bld_polys):
    if not bld_polys:
        return {"n": 0}
    u = shapely.union_all(bld_polys)
    mask = g.zone(u.buffer(RING[1]).difference(u.buffer(RING[0])))
    r = (g.h - median_filter(g.h, size=5, mode="nearest"))[mask]
    d = np.r_[np.abs(np.diff(g.h, axis=1))[mask[:, :-1] & mask[:, 1:]], np.abs(np.diff(g.h, axis=0))[mask[:-1] & mask[1:]]]
    if len(r) < 6:
        return {"n": len(r)}
    return {"n": int(len(r)), "p98": float(np.percentile(np.abs(r), 98)), "max": float(np.abs(r).max()),
            "steep": float((d > 0.8).mean())}


def terminal_base(g, icao):
    """Model origin height and, per big terminal, the median ground just outside / inside it."""
    p = c.OUT / "terminals" / f"{icao}_model.json"
    if not p.exists():
        return None
    m = json.loads(p.read_text())
    d = json.loads((c.OUT / "terminals" / f"{icao}.json").read_text())
    out = {"model_h": m["origin"][2], "terminals": []}
    for t in d["terminals"]:
        if t["area_m2"] <= 5000:
            continue
        foot = shapely.Polygon(t["outers"][0]).buffer(0)
        ring, inside = g.zone(foot.buffer(80.0).difference(foot.buffer(20.0))), g.zone(foot)
        out["terminals"].append({"name": t["tags"].get("name", "?"),
                                 "ring_median": float(np.median(g.h[ring])) if ring.any() else None,
                                 "inside_median": float(np.median(g.h[inside])) if inside.any() else None})
    return out


def measure(icao, tiles=None):
    aero = json.loads((c.OUT / "osm" / "aerodromes.json").read_text())
    ops = AF.Ops()
    ad = shapely.Polygon(next(a["pts"] for a in aero if a["icao"] == icao)).buffer(0)
    near = ad.buffer(AF.NEAR_AD)
    lo, hi = np.array(ad.bounds[:2]) - 200, np.array(ad.bounds[2:]) + 200
    g = Ground(lo, hi, tiles)
    pts = ops.pts[shapely.contains_xy(near, ops.pts[:, 0], ops.pts[:, 1])]
    aprons = [a for a in ops.aprons if near.contains(a.representative_point())]
    bld = [p for a, p in AF.read_buildings(lo, hi) + AF.read_terminals(lo, hi)
           if a >= BIG_BUILDING_M2 and ad.contains(p.centroid)]
    out = {"stand": stand_stats(g, pts), "apron": apron_stats(g, aprons), "ring": ring_stats(g, bld)}
    tb = terminal_base(g, icao)
    if tb:
        out["terminal"] = tb
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    js = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    if js:
        args = [a for a in args if a != js]
    res = {}
    print(f"{'ICAO':5} stands n/med/p90/max ptp (m), share > 1.5 m | aprons n, std, max ptp | "
          "building ring n, p98 |r|, max |r|, steep")
    for icao in args or DEFAULT:
        r = res[icao] = measure(icao)
        s, a, b = r["stand"], r["apron"], r["ring"]
        print(f"{icao:5} stands {s['n']:3d} {s.get('median', 0):4.1f} {s.get('p90', 0):4.1f} {s.get('max', 0):5.1f}  "
              f"{s.get('share_bumpy', 0):4.0%} | aprons {a['n']:2d} {a.get('std', 0):4.2f} {a.get('max_ptp', 0):5.1f} | "
              f"ring {b['n']:4d} {b.get('p98', 0):5.2f} {b.get('max', 0):5.1f} {b.get('steep', 0):4.0%}")
        t = r.get("terminal")
        for x in (t or {}).get("terminals", []):
            print(f"      {x['name'][:20]:20} ground ring {x['ring_median']:.1f} m, terrain inside {x['inside_median']:.1f} m "
                  f"(model origin {t['model_h']:.1f} m; the model follows the terrain per vertex)")
    if js:
        with open(js, "w") as f:
            json.dump(res, f, indent=1)


if __name__ == "__main__":
    main()
