"""Copernicus DEM -> world-frame heightmap tiles with runway/apron flattening.

Output data/processed/terrain/:
  meta.json                 grid constants + per-tile min/max height
  h/<L>/<tx>_<ty>.r16       (TILE_N+1)^2 uint16 LE, h = v*H_SCALE + H_OFFSET
Sample (i, j) of tile (L, tx, ty) sits at world x = tx*S + i*S/TILE_N,
y = ty*S + j*S/TILE_N with S = TILE_SIZE * 2^L (row j = 0 is the SOUTH edge).
Run 04_osm_extract.py and 05_airports_navaids.py first (used for flattening).

Regions (--region mumbai_pune | konkan_kerala | all, default all; --workers N):
  mumbai_pune    one in-memory grid, levels 0..LEVELS-1, writes meta.json (12_outer.py then
                 replaces levels >= 3 with the outer ring).
  konkan_kerala  corridor tiles from common.region_tiles() at levels 0-2, built per level-2
                 block (+ margin) in parallel; runways from runways.json / airports.json;
                 writes meta_konkan_kerala.json with [min, max, flags] (03/11 set the bits; a re-run
                 keeps bits of img/lc tiles already on disk).
"""
import json
import math
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from osgeo import gdal

import common as c
import flatten
import regions as R

gdal.UseExceptions()


# The grid covers whole level-2 tiles so levels 1-2 never clamp past the data edge;
# level-0 tiles are still only written inside X/Y_MIN..MAX.
L2 = c.TILE_SIZE * 4
GX0, GY0 = math.floor(c.X_MIN / L2) * L2, math.floor(c.Y_MIN / L2) * L2
GX1, GY1 = math.ceil(c.X_MAX / L2) * L2, math.ceil(c.Y_MAX / L2) * L2


def warp_dem():
    # GLO-90 first, GLO-30 last: where both exist the 30 m data wins
    srcs = sorted(str(p) for p in (c.RAW / "dem90").glob("*.tif")) + sorted(str(p) for p in (c.RAW / "dem").glob("*.tif"))
    h = c.DEM_RES / 2
    ds = gdal.Warp("", srcs, format="MEM", dstSRS=c.WORLD_PROJ, xRes=c.DEM_RES, yRes=c.DEM_RES,
                   outputBounds=(GX0 - h, GY0 - h, GX1 + h, GY1 + h),
                   resampleAlg="cubic", dstNodata=-9999, outputType=gdal.GDT_Float32)
    a = ds.GetRasterBand(1).ReadAsArray()[::-1].astype(np.float64)  # row 0 = south
    a[a < -500] = 0.0  # nodata (sea outside tiles) -> sea level
    return a


def downsample(a):
    """2x decimation with a [1 2 1]/4 filter, keeping corner-aligned samples."""
    p = np.pad(a, 1, mode="edge")
    f = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4
    f = (f[:, :-2] + 2 * f[:, 1:-1] + f[:, 2:]) / 4
    return f[::2, ::2]


def write_level(grid, level, out, meta):
    n, step = c.TILE_N, 2 ** level
    size = c.TILE_SIZE * step
    gx0, gy0 = int(c.X_MIN / size // 1), int(c.Y_MIN / size // 1)
    gx1, gy1 = math.ceil(c.X_MAX / size), math.ceil(c.Y_MAX / size)
    # grid sample (0,0) is at (X_MIN, Y_MIN); offset in level samples
    ox, oy = round((gx0 * size - GX0) / (c.DEM_RES * step)), round((gy0 * size - GY0) / (c.DEM_RES * step))
    d = out / "h" / str(level)
    d.mkdir(parents=True, exist_ok=True)
    tiles = {}
    for ty in range(gy0, gy1):
        for tx in range(gx0, gx1):
            j0, i0 = (ty - gy0) * n + oy, (tx - gx0) * n + ox
            jj = np.clip(np.arange(j0, j0 + n + 1), 0, grid.shape[0] - 1)
            ii = np.clip(np.arange(i0, i0 + n + 1), 0, grid.shape[1] - 1)
            t = grid[np.ix_(jj, ii)]
            v = np.clip(np.round((t - c.H_OFFSET) / c.H_SCALE), 0, 65535).astype("<u2")
            v.tofile(d / f"{tx}_{ty}.r16")
            tiles[f"{tx}_{ty}"] = [round(float(t.min()), 1), round(float(t.max()), 1)]
    meta["levels"].append({"level": level, "size_m": size, "tx": [gx0, gx1 - 1],
                           "ty": [gy0, gy1 - 1], "tiles": tiles})


def main_mumbai_pune():
    out = c.OUT / "terrain"
    a = warp_dem()
    print("dem grid", a.shape, "range", a.min(), a.max())
    flatten.X0, flatten.Y0 = GX0, GY0
    n_flat = flatten.apply(a)
    print("flattened features:", n_flat)
    meta = {"origin_lat": c.ORIGIN_LAT, "origin_lon": c.ORIGIN_LON, "proj": c.WORLD_PROJ,
            "tile_n": c.TILE_N, "tile_size_m": c.TILE_SIZE, "dem_res_m": c.DEM_RES,
            "extent": [c.X_MIN, c.Y_MIN, c.X_MAX, c.Y_MAX],
            "h_scale": c.H_SCALE, "h_offset": c.H_OFFSET, "levels": []}
    grid = a
    for level in range(c.LEVELS):
        write_level(grid, level, out, meta)
        grid = downsample(grid)
    (out / "meta.json").write_text(json.dumps(meta))
    print("tiles per level:", [len(l["tiles"]) for l in meta["levels"]])



# ------------------------------------------------------------------ corridor (block-wise)
BLK = 4 * c.TILE_N   # level-0 samples per level-2 block
MARGIN = 256         # level-0 samples around a block: whole runways for the flatten fit, and
                     # filter support for downsampling; a multiple of 4 keeps the global
                     # L2-aligned sample lattice, so block edges match neighbours and mumbai_pune
_FEAT = None


def _init(feat):
    global _FEAT
    _FEAT = feat


def corridor_block(job):
    bx, by, want = job
    L2s = c.TILE_SIZE * 4
    x0, y0 = bx * L2s - MARGIN * c.DEM_RES, by * L2s - MARGIN * c.DEM_RES
    m = BLK + 2 * MARGIN
    x1, y1 = x0 + m * c.DEM_RES, y0 + m * c.DEM_RES
    h = c.DEM_RES / 2
    srcs = R.dem_sources((x0, y0, x1, y1))
    if srcs:
        ds = gdal.Warp("", srcs, format="MEM", dstSRS=c.WORLD_PROJ, xRes=c.DEM_RES, yRes=c.DEM_RES,
                       outputBounds=(x0 - h, y0 - h, x1 + h, y1 + h), resampleAlg="cubic",
                       errorThreshold=0,  # exact transform: neighbouring blocks agree bit-for-bit
                       dstNodata=-9999, outputType=gdal.GDT_Float32)
        a = ds.GetRasterBand(1).ReadAsArray()[::-1].astype(np.float64)
        a[a < -500] = 0.0
    else:
        a = np.zeros((m + 1, m + 1))  # open sea
    flatten.X0, flatten.Y0 = x0, y0
    nf = flatten.apply_features(a, *_FEAT)
    out, n, res = [], c.TILE_N, []
    for level in range(3):
        size, sp = c.TILE_SIZE * 2 ** level, c.DEM_RES * 2 ** level
        d = R.T / "h" / str(level)
        for tx, ty in want[level]:
            i0, j0 = round((tx * size - x0) / sp), round((ty * size - y0) / sp)
            t = a[j0:j0 + n + 1, i0:i0 + n + 1]
            assert t.shape == (n + 1, n + 1)
            v = np.clip(np.round((t - c.H_OFFSET) / c.H_SCALE), 0, 65535).astype("<u2")
            v.tofile(d / f"{tx}_{ty}.r16")
            res.append((level, f"{tx}_{ty}", round(float(t.min()), 1), round(float(t.max()), 1)))
        a = downsample(a)
    return res, nf


STITCH = 8  # samples over which a corridor tile blends into its mumbai_pune neighbour's edge


def stitch_to_base(levels):
    """mumbai_pune tiles are fixed (byte-identical); their edge samples differ slightly from the
    corridor's (whole-grid warp, edge-padded downsampling at the old grid boundary). Copy the
    shared edge into each adjacent corridor tile and fade the correction out over STITCH samples."""
    base = {L["level"]: L["tiles"] for L in R.load_meta("mumbai_pune")["levels"][:3]}
    n, done = c.TILE_N, 0
    ramp = 1 - np.arange(STITCH) / STITCH
    load = lambda lv, k: np.fromfile(R.T / "h" / str(lv) / f"{k}.r16", "<u2").reshape(n + 1, n + 1)
    for L in levels:
        lv = L["level"]
        for key in L["tiles"]:
            tx, ty = map(int, key.split("_"))
            nb = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if f"{tx + dx}_{ty + dy}" in base[lv]]
            if not nb:
                continue
            a = load(lv, key).astype(np.float64)
            edges = []
            for dx, dy in nb:
                b = load(lv, f"{tx + dx}_{ty + dy}").astype(np.float64)
                # view the tile so that the shared edge is row 0 of `v`
                v = {(1, 0): a[:, ::-1].T, (-1, 0): a.T, (0, 1): a[::-1], (0, -1): a}[(dx, dy)]
                e = {(1, 0): b[:, 0], (-1, 0): b[:, n], (0, 1): b[0], (0, -1): b[n]}[(dx, dy)]
                v[:STITCH] += np.outer(ramp, e - v[0])
                edges.append((v, e))
                done += 1
            for v, e in edges:  # a later edge's fade touches an earlier edge near the corner
                v[0] = e
            np.clip(np.round(a), 0, 65535).astype("<u2").tofile(R.T / "h" / str(lv) / f"{key}.r16")
            h = a * c.H_SCALE + c.H_OFFSET
            L["tiles"][key][:2] = [round(float(h.min()), 1), round(float(h.max()), 1)]
    return done


def main_corridor(region, workers):
    sets = {L: c.region_tiles(region, L) for L in range(3)}
    blocks = {}
    for L, tiles in sets.items():
        for tx, ty in tiles:
            blocks.setdefault((tx >> (2 - L), ty >> (2 - L)), ([], [], []))[L].append((tx, ty))
    for L in range(3):
        (R.T / "h" / str(L)).mkdir(parents=True, exist_ok=True)
    feat = flatten.corridor_features()
    print(f"{region}: tiles per level {[len(sets[L]) for L in range(3)]}, {len(blocks)} blocks, "
          f"{len(feat[0])} runways, {len(feat[1])} aprons")
    jobs = [(bx, by, w) for (bx, by), w in sorted(blocks.items())]
    levels = [{"level": L, "size_m": c.TILE_SIZE * 2 ** L, "tiles": {}} for L in range(3)]
    nflat = 0
    with ProcessPoolExecutor(workers, initializer=_init, initargs=(feat,)) as ex:
        for res, nf in ex.map(corridor_block, jobs):
            nflat += nf
            for L, key, lo, hi in res:
                levels[L]["tiles"][key] = [lo, hi, 0]
    stitched = stitch_to_base(levels)
    print(f"{region}: stitched {stitched} tile edges onto mumbai_pune neighbours")
    for L in levels:
        ks = [tuple(map(int, k.split("_"))) for k in L["tiles"]]
        L["tx"] = [min(k[0] for k in ks), max(k[0] for k in ks)]
        L["ty"] = [min(k[1] for k in ks), max(k[1] for k in ks)]
    meta = {"region": region, "origin_lat": c.ORIGIN_LAT, "origin_lon": c.ORIGIN_LON,
            "proj": c.WORLD_PROJ, "tile_n": c.TILE_N, "tile_size_m": c.TILE_SIZE,
            "dem_res_m": c.DEM_RES, "h_scale": c.H_SCALE, "h_offset": c.H_OFFSET,
            "img_n": c.IMG_N, "img_min_level": c.CORRIDOR_IMG_LEVEL, "levels": levels}
    for bit, d, ext in ((R.F_IMG, "img", "dds"), (R.F_LC, "lc", "r8.gz")):  # keep 03/11 output flagged
        R.set_flag(meta, bit, lambda lv, tx, ty: lv >= c.CORRIDOR_IMG_LEVEL and
                   (R.T / d / str(lv) / f"{tx}_{ty}.{ext}").exists())
    R.save_meta(region, meta)
    print(f"{region}: flattened {nflat} feature cuts (incl. block overlaps); tiles per level:",
          [len(L["tiles"]) for L in levels])


def main():
    args = R.parse_args(__doc__)
    for region in args.regions:
        if region == "mumbai_pune":
            main_mumbai_pune()
        else:
            main_corridor(region, args.workers)


if __name__ == "__main__":
    main()
