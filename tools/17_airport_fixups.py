"""Post-process airport fixes on the generated terrain tiles (levels 0-2), in place.

1. Levelled airports (LEVELLED: VANM, VOKN, VOSR): Navi Mumbai (VANM, NMIA) was built on reclaimed, levelled
   land (Ulwe hill cut, creeks and rivers diverted) after the Copernicus DEM epoch. The raw
   data there is the old landscape: a 40 m hill at the west end, mudflats at -8..+2 m at the
   east end, and creeks that 11_landclass.py marks as water (OSM water polygons, and "DEM
   <= 0.3 m means sea"). The terrain shader drew water over most of the airport and the
   runway was a 1.4 % ramp. Inside the OSM aeroway=aerodrome polygon: heights = one platform
   elevation (feathered over FEATHER m outside), land class 0 (no water, no trees).
2. Taxiways at every aerodrome: Copernicus is a surface model (aircraft, hangars, trees) and
   only runways and aprons are flattened by 02, so taxiway strips (airport_builder.gd) were
   buried in metre-high bumps ("runway / taxiway does not load completely"). Heights under
   each taxiway (+ shoulder) follow a robustly smoothed centreline profile, feathered out.
3. Land class: water (255) -> 0 on all paved surfaces (runways.json strips, OSM aprons), and
   no trees (1..200 -> 0) inside any aerodrome perimeter: airfields are kept clear, and the
   6-15 m crossed-quad trees 11 placed on the grass hid taxiways at grazing angles.
Both regions (meta.json grid and meta_<region>.json packs). Heights: level 0 is edited; the
change is propagated to levels 1-2 with 02's [1 2 1] decimation filter. Land class: the same
per-pixel rules on every existing level 0-2 mask. min/max in the owning meta are updated. Levels >= 3 (12_outer, >= 61 km tiles) are left alone.
Originals are kept (airport_fixups_io), so re-running reverts and re-applies.

Run order: after 02, 09, 11, 12; then re-run 09 (runway heights), 14 (ILS), 10 (buildings).
./run.sh does this (step 17).
Usage: 17_airport_fixups.py [--refresh-osm]
"""
import json
import sys

import numpy as np
import shapely
from matplotlib.path import Path as MplPath
from scipy.ndimage import median_filter, uniform_filter1d

import common as c
from airport_fixups_io import N, LCN, Tiles, downsample

AERO_CACHE = c.OUT / "osm" / "aerodromes.json"
FEATHER = 200.0      # levelled platform blend distance (m)
TW_SHOULDER = 10.0   # flat margin beyond the taxiway half-width (m)
TW_FEATHER = 60.0    # taxiway blend distance (m)
PAVED_PAD = 15.0     # m beyond the paved half-width that must not be water
# ICAO -> platform elevation (m AMSL) for airports built by cut-and-fill after the DEM epoch
# (Copernicus = TanDEM-X 2011-2015). NMIA's platform was filled to roughly +8 m; Kannur
# (2018) and Sindhudurg/Chipi (2021) sit on levelled plateaus, but the DEM still has the
# old slopes (runway ends 90/131 m and 51/70 m). Elevations: OurAirports.
LEVELLED = {"VANM": 8.0, "VOKN": 100.6, "VOSR": 61.9}


def aerodromes():
    """OSM aeroway=aerodrome outlines in both regions (Mumbai-Pune grid, Konkan-Kerala
    corridor), from every extract (osm_regions.iter_osm), cached in osm/aerodromes.json."""
    if AERO_CACHE.exists() and "--refresh-osm" not in sys.argv:
        return json.loads(AERO_CACHE.read_text())
    import osmium
    import osm_regions as R
    fwd = c.transformer()
    out = []
    proc = lambda path: (osmium.FileProcessor(str(path)).with_locations().with_areas()
                         .with_filter(osmium.filter.TagFilter(("aeroway", "aerodrome"))))
    for o in R.iter_osm(proc, R.region_filter()):
        if not o.is_area():
            continue
        for ring in o.outer_rings():
            ll = [(n.location.lon, n.location.lat) for n in ring if n.location.valid()]
            if len(ll) >= 4:
                out.append({"icao": o.tags.get("icao", ""), "name": o.tags.get("name", ""),
                            "pts": [[round(v, 1) for v in fwd(*p)] for p in ll]})
    AERO_CACHE.write_text(json.dumps(out))
    return out


def tiles_over(lo, hi, size):
    return [(tx, ty) for ty in range(int(np.floor(lo[1] / size)), int(np.floor(hi[1] / size)) + 1)
            for tx in range(int(np.floor(lo[0] / size)), int(np.floor(hi[0] / size)) + 1)]


def near_lines(rw, lo, hi):
    """Runway centrelines and taxiway polylines (with widths) touching the box."""
    inb = lambda p: lo[0] <= p[0] <= hi[0] and lo[1] <= p[1] <= hi[1]
    rwys = [([(e["x"], e["y"]) for e in r["ends"]], r["width"]) for r in rw["runways"]]
    twys = [([tuple(p[:2]) for p in t["pts"]], min(t["width"], 23.0)) for t in rw["taxiways"]]
    keep = lambda ls: [(p, w) for p, w in ls if len(p) >= 2 and any(inb(q) for q in p)]
    return keep(rwys), keep(twys)


class Mosaic:
    """Level-0 heights around one aerodrome, origin on a level-2 corner so that 2x
    decimation stays on the level-1/2 sample lattices."""

    def __init__(self, tiles, lo, hi):
        s2 = c.TILE_SIZE * 4
        self.x0, self.y0 = np.floor(lo / s2) * s2
        self.lo, self.hi = lo, hi
        # whole level-2 tiles, so every level-1/2 tile over the airport fits in the mosaic
        nx, ny = (int(v) * 4 for v in np.ceil((hi - (self.x0, self.y0)) / s2))
        self.h = np.zeros((ny * N + 1, nx * N + 1))
        for j in range(ny):
            for i in range(nx):
                a = tiles.read_h(0, int(self.x0 / c.TILE_SIZE) + i, int(self.y0 / c.TILE_SIZE) + j)
                if a is not None:
                    self.h[j * N:(j + 1) * N + 1, i * N:(i + 1) * N + 1] = a
        xs = self.x0 + np.arange(self.h.shape[1]) * c.DEM_RES
        ys = self.y0 + np.arange(self.h.shape[0]) * c.DEM_RES
        self.X, self.Y = np.meshgrid(xs, ys)
        self.tgt = self.h.copy()
        self.w = np.zeros(self.h.shape)

    def sample(self, x, y):
        i = np.clip(np.round((x - self.x0) / c.DEM_RES).astype(int), 0, self.h.shape[1] - 1)
        j = np.clip(np.round((y - self.y0) / c.DEM_RES).astype(int), 0, self.h.shape[0] - 1)
        return self.h[j, i]

    def blend(self, geom, dist_flat, feather, target_fn):
        """Pull samples within dist_flat (+feather) of geom towards target_fn(points)."""
        b = np.array(geom.bounds) + [-dist_flat - feather, -dist_flat - feather, dist_flat + feather, dist_flat + feather]
        win = (self.X >= b[0]) & (self.X <= b[2]) & (self.Y >= b[1]) & (self.Y <= b[3])
        if not win.any():
            return
        pts = shapely.points(self.X[win], self.Y[win])
        d = shapely.distance(geom, pts)
        t = np.clip(1 - (d - dist_flat) / feather, 0, 1)
        t = t * t * (3 - 2 * t)
        sub_w, sub_t = self.w[win], self.tgt[win]
        better = t > sub_w
        sub_t[better] = target_fn(pts[better])
        sub_w[better] = t[better]
        self.w[win], self.tgt[win] = sub_w, sub_t

    def commit(self, tiles, mask_keep):
        self.w[mask_keep] = 0.0
        deltas = [(self.tgt - self.h) * self.w]
        for _ in range(2):
            deltas.append(downsample(deltas[-1]))
        n = 0
        for level, d in enumerate(deltas):
            size, res = c.TILE_SIZE * 2 ** level, c.DEM_RES * 2 ** level
            for tx, ty in tiles_over(self.lo, self.hi, size):
                i0, j0 = round((tx * size - self.x0) / res), round((ty * size - self.y0) / res)
                if i0 < 0 or j0 < 0 or j0 + N + 1 > d.shape[0] or i0 + N + 1 > d.shape[1]:
                    continue
                dd = d[j0:j0 + N + 1, i0:i0 + N + 1]
                a = tiles.read_h(level, tx, ty)
                if a is None or np.abs(dd).max() < 0.05:
                    continue
                tiles.write_h(level, tx, ty, a + dd)
                n += 1
        return n


def taxiway_profile(m, line):
    """Centreline heights every 15 m, median (~135 m) then mean (~75 m) filtered."""
    s = np.arange(0.0, line.length + 15.0, 15.0)
    p = shapely.line_interpolate_point(line, np.minimum(s, line.length))
    h = m.sample(shapely.get_x(p), shapely.get_y(p))
    if len(h) >= 3:
        h = uniform_filter1d(median_filter(h, size=min(9, len(h)), mode="nearest"), size=min(5, len(h)), mode="nearest")
    return lambda pts: np.interp(shapely.line_locate_point(line, pts), s, h)


def fix_heights(tiles, ad, rw):
    poly = np.asarray(ad["pts"], float)
    lo, hi = poly.min(0) - FEATHER - 500, poly.max(0) + FEATHER + 500
    rwys, twys = near_lines(rw, lo, hi)
    m = Mosaic(tiles, lo, hi)
    elev = LEVELLED.get(ad["icao"])
    if elev is not None:
        m.blend(shapely.Polygon(poly), 0.0, FEATHER, lambda pts: np.full(len(pts), elev))
    else:
        for pts, w in twys:
            line = shapely.LineString(pts)
            if line.length > 1.0:
                m.blend(line, w / 2 + TW_SHOULDER, TW_FEATHER, taxiway_profile(m, line))
    keep = np.zeros(m.h.shape, bool)
    if elev is None:  # 02 made runways exact (least-squares line): never touch them
        for pts, w in rwys:
            keep |= shapely.distance(shapely.LineString(pts), shapely.points(m.X, m.Y)) < w / 2 + 20.0
    return m.commit(tiles, keep), len(twys)


def paved_polys(rw, lo, hi):
    """Paved surfaces in the box: runway/taxiway strips as quads, OSM aprons as polygons."""
    rwys, twys = near_lines(rw, lo, hi)
    out = []
    for pts, w in rwys + twys:
        for a, b in zip(pts, pts[1:]):
            a, b = np.asarray(a, float), np.asarray(b, float)
            u = (b - a) / (np.hypot(*(b - a)) or 1)
            n = np.array([-u[1], u[0]]) * (w / 2 + PAVED_PAD)
            u = u * PAVED_PAD
            out.append(np.array([a - u + n, b + u + n, b + u - n, a - u - n]))
    aw = json.loads((c.OUT / "osm" / "aeroways.json").read_text())
    out += [np.asarray(a["pts"], float) for a in aw["areas"] if a["kind"] == "apron"
            and lo[0] <= a["pts"][0][0] <= hi[0] and lo[1] <= a["pts"][0][1] <= hi[1]]
    return out


def fix_landclass(tiles, ad, rw):
    """Every existing land-class tile at levels 0-2 (the corridor has none at level 0; its
    finest is level 1) gets the same per-pixel rules; coarser levels are not re-derived from
    finer ones, so tiles with partly missing children stay correct."""
    poly = np.asarray(ad["pts"], float)
    lo, hi = poly.min(0) - 500, poly.max(0) + 500
    paved = paved_polys(rw, lo, hi)
    levelled = ad["icao"] in LEVELLED
    ha = [0.0, 0.0, 0.0]
    for level in (0, 1, 2):
        size = c.TILE_SIZE * 2 ** level
        px = size / LCN
        for tx, ty in tiles_over(lo, hi, size):
            a = tiles.read_lc(level, tx, ty)
            if a is None:
                continue
            X, Y = np.meshgrid(tx * size + (np.arange(LCN) + 0.5) * px,
                               ty * size + size - (np.arange(LCN) + 0.5) * px)  # row 0 = north
            xy = np.c_[X.ravel(), Y.ravel()]
            inside = lambda p: MplPath(p).contains_points(xy).reshape(X.shape)
            m = inside(poly) & ((a != 0) if levelled else ((a > 0) & (a < 255)))
            for p in paved:
                m |= inside(p) & (a == 255)
            if m.any():
                a[m] = 0
                ha[level] += float(m.sum()) * px * px / 1e4
                tiles.write_lc(level, tx, ty, a)
    return max(ha)


def main():
    tiles = Tiles()
    print(tiles.prepare())
    rw = json.loads((c.OUT / "runways.json").read_text())
    for ad in aerodromes():
        name = ad["icao"] or ad["name"]
        n, ntw = fix_heights(tiles, ad, rw)
        what = f"levelled to {LEVELLED[ad['icao']]} m" if ad["icao"] in LEVELLED else f"{ntw} taxiways smoothed"
        print(f"{name}: {what}, {n} height tiles patched (levels 0-2)")
        ha = fix_landclass(tiles, ad, rw)
        if ha > 0:
            print(f"{name}: land class fixed on {ha:.1f} ha")
    tiles.save()
    print(f"{len(tiles.files)} tiles written; now re-run 09_runways.py, 14_ils.py and 10_buildings.py")


if __name__ == "__main__":
    main()
