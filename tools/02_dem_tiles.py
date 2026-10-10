"""Copernicus DEM -> world-frame heightmap tiles with runway/apron flattening.

Output data/processed/terrain/:
  meta.json                 grid constants + per-tile min/max height
  h/<L>/<tx>_<ty>.r16       (TILE_N+1)^2 uint16 LE, h = v*H_SCALE + H_OFFSET
Sample (i, j) of tile (L, tx, ty) sits at world x = tx*S + i*S/TILE_N,
y = ty*S + j*S/TILE_N with S = TILE_SIZE * 2^L (row j = 0 is the SOUTH edge).
Run 04_osm_extract.py and 05_airports_navaids.py first (used for flattening).
"""
import json
import math

import numpy as np
from osgeo import gdal

import common as c
import flatten

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


def main():
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


if __name__ == "__main__":
    main()
