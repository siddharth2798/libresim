"""Level the ground where aircraft park and taxi (helper of 17_airport_fixups.py).

Copernicus GLO-30 is a surface model: terminals, hangars, parked aircraft, vehicles and tree
rows are in the heights. 02_dem_tiles.py only flattens runway strips and the OSM aeroway=apron
polygons (to their median DSM height), but at most airports the polygons cover a fraction of
the stand area (VABB: 30 of 114 stands lie inside one) and none of the ground next to the
terminal, so the apron was a field of 5-25 m mounds (terminal walls and roofs, aircraft).

Zone Z (inside the aerodrome outline or within NEAR_AD of it):
  - OSM apron polygons,
  - STAND_R around every stand / gate (airport_ops.json from 13), LANE_PAD beyond the lead-in
    lines, taxilanes and the taxiways close to the stands (its taxi graph),
  - BRIDGE_PAD around jet bridges,
  - BUILD_PAD around buildings of >= BUILD_MIN_M2 (04's footprint tiles, 15's terminal outlines):
    terminals, hangars, towers, so the ground under and beside them is ground, not roof.
Ground model: the DSM with its clutter replaced by a smooth membrane (harmonic inpainting) from
the ground around it. Clutter = samples within CORE_* of a building footprint, samples standing
too far above a 3- or 5-sample morphological opening (aircraft, vehicles, trees, sheds, annexes the
footprints miss) where the surrounding ground is flat (on_flat_ground: a hilltop corner is terrain),
and the wider ring around footprints only where it stands above the first fill (a wall leaking into
its neighbour, not the apron beside it). Big opening windows are not used: they would take a graded
apron terrace for a building. A last smoothing moves a sample by at most SMOOTH_MAX. Inside Z the
terrain becomes that ground, smoothstep-blended to the DSM over FEATHER m; where nothing is clutter
the DSM stays (02's flat apron polygons stay as they are). Runway strips are never touched (17
keeps them). The result is carried to levels 1-2 by Mosaic.commit like every other fix.
Measure it with tools/apron_roughness.py.
"""
import json
import struct

import numpy as np
import shapely
from scipy.ndimage import binary_dilation, gaussian_filter, grey_opening, maximum_filter, minimum_filter
from scipy.sparse import coo_matrix, identity
from scipy.sparse.linalg import spsolve

import common as c

STAND_R = 50.0
LANE_PAD = 20.0
BRIDGE_PAD = 20.0
BUILD_PAD = 30.0
BUILD_MIN_M2 = 150.0     # smaller buildings stay (sheds, kiosks)
BUILD_BIG_M2 = 5000.0    # blocks this big are levelled even when only near the aerodrome outline
NEAR_AD = 150.0          # m around the aerodrome outline that still counts as "the airport"
NEAR_STAND = 60.0        # taxiways this close to the core zone are levelled with it
MASK_BIG, MASK_SMALL = 45.0, 30.0   # wide ring around buildings >= / < MASK_BIG_M2 m2
CORE_BIG, CORE_SMALL = 15.0, 10.0   # always clutter within this of a footprint
MASK_BIG_M2 = 600.0
RING, RING_RANGE = 3, 3.0           # flat-ground test of a flagged object: unflagged samples within RING span <= m
WIDE_TOL = 0.8                      # m the wide ring must stand above the fill to count as clutter
PMF = ((3, 0.8), (5, 1.0))          # (window in samples, max height above the opening in m)
SMOOTH_MAX = 1.0                    # m: residual-noise smoothing never moves a sample more than this
FEATHER = 30.0
SIGMA = 1.0                         # samples (30 m)


def read_buildings(lo, hi):
    """[(area_m2, shapely Polygon)] of OSM buildings (04's tile .bin files) centred in the box."""
    out = []
    for ty in range(int(np.floor(lo[1] / c.TILE_SIZE)), int(np.floor(hi[1] / c.TILE_SIZE)) + 1):
        for tx in range(int(np.floor(lo[0] / c.TILE_SIZE)), int(np.floor(hi[0] / c.TILE_SIZE)) + 1):
            p = c.OUT / "osm" / "buildings" / f"{tx}_{ty}.bin"
            if not p.exists():
                continue
            b, o = p.read_bytes(), 0
            while o < len(b):
                n, _h = struct.unpack_from("<Hf", b, o)
                pts = np.frombuffer(b, "<f4", 2 * n, o + 6).reshape(n, 2).astype(float)
                o += 6 + 8 * n
                m = pts.mean(0)
                if n >= 3 and lo[0] <= m[0] <= hi[0] and lo[1] <= m[1] <= hi[1]:
                    poly = shapely.Polygon(pts).buffer(0)
                    if not poly.is_empty and poly.area >= 40.0:
                        out.append((poly.area, poly))
    return out


def read_terminals(lo, hi):
    """Terminal / part / car-park footprints of 15_terminals.py (some terminals carry no OSM
    building tag, so they are not in 04's tiles), same format as read_buildings."""
    out = []
    for f in sorted((c.OUT / "terminals").glob("[A-Z][A-Z0-9][A-Z0-9][A-Z0-9].json")):
        d = json.loads(f.read_text())
        for g in ("terminals", "parts", "car_parks"):
            for t in d.get(g, []):
                for ring in t["outers"]:
                    poly = shapely.Polygon(ring).buffer(0)
                    cx, cy = poly.centroid.x, poly.centroid.y
                    if not poly.is_empty and lo[0] <= cx <= hi[0] and lo[1] <= cy <= hi[1]:
                        out.append((poly.area, poly))
    return out


class Ops:
    """Airport features from airport_ops.json and the OSM apron polygons (loaded once)."""

    def __init__(self):
        ops = json.loads((c.OUT / "airport_ops.json").read_text())
        aw = json.loads((c.OUT / "osm" / "aeroways.json").read_text())
        self.pts = np.array([(s["x"], s["y"]) for o in ops.values() for s in o["stands"] + o["gates"]]).reshape(-1, 2)
        self.bridges = [shapely.LineString(j["pts"]) for o in ops.values() for j in o["jetbridges"] if len(j["pts"]) >= 2]
        self.edges = []  # (LineString, half width, kind) of every non-runway taxi graph edge
        for o in ops.values():
            nodes = o["taxi"]["nodes"]
            for a, b, _ref, w, kind in o["taxi"]["edges"]:
                if kind != "runway" and a in nodes and b in nodes:
                    try:
                        hw = max(float(w), 12.0) / 2
                    except (ValueError, TypeError):
                        hw = 10.0
                    self.edges.append((shapely.LineString([nodes[a], nodes[b]]), hw, kind))
        self.aprons = [shapely.Polygon(a["pts"]).buffer(0) for a in aw["areas"] if a["kind"] == "apron" and len(a["pts"]) >= 4]

    def zone(self, ad, bld):
        """(zone geometry, levelled building polygons) for one aerodrome polygon."""
        near = ad.buffer(NEAR_AD)
        shapely.prepare(near)
        core = [a for a in self.aprons if near.contains(a.representative_point())]
        core += [shapely.Point(p).buffer(STAND_R) for p in self.pts[shapely.contains_xy(near, self.pts[:, 0], self.pts[:, 1])]]
        core += [b.buffer(BRIDGE_PAD) for b in self.bridges if near.contains(b.centroid)]
        lev = [p for a, p in bld if a >= BUILD_MIN_M2 and (ad.buffer(30.0).contains(p.centroid)
                                                           or (a >= BUILD_BIG_M2 and near.contains(p.centroid)))]
        core += [p.buffer(BUILD_PAD) for p in lev]
        if not core:
            return None, lev
        cz = shapely.unary_union(core)
        shapely.prepare(cz)
        lanes = [ls.buffer(hw + LANE_PAD) for ls, hw, kind in self.edges
                 if near.contains(ls.centroid) and (kind != "taxiway" or cz.distance(ls) < NEAR_STAND)]
        return shapely.unary_union([cz] + lanes), lev


def clutter(m, bld, around):
    """(core, wide) boolean masks of mosaic samples that are not ground. core: within CORE_* of a
    building footprint, or standing more than a limit above a morphological opening of 3 or 5
    samples (aircraft, vehicles, trees, sheds), dilated by one sample for the leaking edges. wide:
    the samples up to MASK_* from a footprint, which are clutter only where they stand above the
    ground inpainted under the core (a wall leaking into its neighbour, not an apron beside it).
    Big opening windows are not used: they would take a graded apron terrace for a building."""
    near = around.buffer(300.0)
    shapely.prepare(near)
    mine = [(a, p) for a, p in bld if near.intersects(p)]
    none = np.zeros(m.h.shape, bool)

    def around_footprints(big, small):
        if not mine:
            return none
        return shapely.contains_xy(shapely.unary_union([p.buffer(big if a >= MASK_BIG_M2 else small) for a, p in mine]), m.X, m.Y)

    foot = around_footprints(CORE_BIG, CORE_SMALL)
    z, objs = m.h, none.copy()
    for w, lim in PMF:
        o = grey_opening(z, size=(w, w), mode="nearest")
        objs |= (z - o) > lim
        z = o
    core = foot | on_flat_ground(m.h, binary_dilation(objs, np.ones((3, 3), bool)), foot)
    return core, around_footprints(MASK_BIG, MASK_SMALL) & ~core


def on_flat_ground(h, flags, skip):
    """The flagged samples that sit on flat ground. A convex corner or a narrow terrace of steep
    terrain (a hilltop apron) is also higher than its opening, but the unflagged ground around it
    is not flat: where those samples within RING samples span more than RING_RANGE m the flag is
    dropped (terrain, not an object)."""
    ground = ~flags & ~skip
    hi = maximum_filter(np.where(ground, h, -np.inf), size=2 * RING + 1, mode="nearest")
    lo = minimum_filter(np.where(ground, h, np.inf), size=2 * RING + 1, mode="nearest")
    return flags & ~(hi - lo > RING_RANGE)


def inpaint(h, bad):
    """Harmonic (membrane) fill of the masked samples from the unmasked ones around them: smooth,
    bridges a terminal's width, and never leaves the range of the surrounding ground."""
    idx = np.full(h.shape, -1)
    idx[bad] = np.arange(int(bad.sum()))
    n = int(bad.sum())
    rows, cols, vals, rhs = [np.arange(n)], [np.arange(n)], [np.full(n, 4.0)], np.full(n, 1e-6)
    out = h.copy()
    hp, ip = np.pad(h, 1, mode="edge"), np.pad(idx, 1, mode="edge")
    for dj, di in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb_h = hp[1 + dj:1 + dj + h.shape[0], 1 + di:1 + di + h.shape[1]][bad]
        nb_i = ip[1 + dj:1 + dj + h.shape[0], 1 + di:1 + di + h.shape[1]][bad]
        inside = nb_i >= 0
        rows.append(np.arange(n)[inside])
        cols.append(nb_i[inside])
        vals.append(np.full(int(inside.sum()), -1.0))
        rhs = rhs + np.where(inside, 0.0, nb_h)
    a = coo_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, n)).tocsc()
    a = a + 1e-6 * identity(n, format="csc")
    out[bad] = spsolve(a, rhs + 1e-6 * h[bad])
    return out


def ground_field(m, bld, around):
    """Ground height on the mosaic grid: the DSM with the clutter inpainted (the wide ring only
    where it stands WIDE_TOL above the first fill), then smoothed by at most SMOOTH_MAX m (sigma
    SIGMA samples) so residual DSM noise flattens without eroding real relief."""
    core, wide = clutter(m, bld, around)
    if core.all() or not core.any():
        return m.h.copy()
    g = inpaint(m.h, core)
    ring = wide & (m.h - g > WIDE_TOL)
    if ring.any():
        g = inpaint(m.h, core | ring)
    return g + np.clip(gaussian_filter(g, SIGMA, mode="nearest") - g, -SMOOTH_MAX, SMOOTH_MAX)


def level(m, ad_pts, ops):
    """Pull the apron zone of one aerodrome (outline ad_pts) in Mosaic m towards the ground model.
    Returns the number of mosaic samples fully levelled (weight 1), 0 when nothing to do."""
    ad = shapely.Polygon(ad_pts).buffer(0)
    bld = read_buildings(m.lo, m.hi) + read_terminals(m.lo, m.hi)
    zone, _lev = ops.zone(ad, bld)
    if zone is None:
        return 0
    g = ground_field(m, bld, zone)

    def target(pts):
        i = np.clip(np.round((shapely.get_x(pts) - m.x0) / c.DEM_RES).astype(int), 0, m.h.shape[1] - 1)
        j = np.clip(np.round((shapely.get_y(pts) - m.y0) / c.DEM_RES).astype(int), 0, m.h.shape[0] - 1)
        return g[j, i]

    m.blend(zone, 0.0, FEATHER, target)
    return int((m.w >= 0.999).sum())
