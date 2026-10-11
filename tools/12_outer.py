"""Outer ring: coarse real data for terrain levels >= OUTER_MIN_LEVEL over OUTER_TOTAL
(~980 x 1475 km: level-6 tiles tx -1..0, ty -2..0, reaching Kochi).

Heights: Copernicus GLO-90 (+ GLO-30) warped at 240 m; cells with no data are filled
by GDAL FillNodata (sea extends seaward, plateau inland) plus fractal detail, so the
world never ends abruptly. Imagery: s2_outer.tif + s2_outer_south.tif (80 m, over OUTER and
OUTER_SOUTH) where available, else a synthetic texture (sea / land colours from the real imagery + noise).
Land class: water where the height is ~0 m.
Writes h/, img/, lc/ tiles for levels 3..6 (overwriting the clamped ones from 02/03/11)
and extends terrain/meta.json. Run after 02, 03, 11.
"""
import gzip
import json
import math

import numpy as np
from osgeo import gdal

import bc1
import common as c

gdal.UseExceptions()
T = c.OUT / "terrain"
RES = c.TILE_SIZE * 8 / c.TILE_N  # 240 m = level-3 sample spacing
TOP = c.LEVELS_TOTAL - 1
X0, Y0, X1, Y1 = c.OUTER_TOTAL  # whole level-6 tiles


def fbm(shape, scale, seed, octaves=5):
    rng = np.random.default_rng(seed)
    out = np.zeros(shape)
    amp = 1.0
    for o in range(octaves):
        n = max(2, int(shape[0] / scale * 2 ** o))
        g = rng.random((n + 1, n + 1))
        yi = np.linspace(0, n, shape[0])
        xi = np.linspace(0, n, shape[1])
        y0 = np.floor(yi).astype(int).clip(0, n - 1)
        x0 = np.floor(xi).astype(int).clip(0, n - 1)
        fy = (yi - y0)[:, None]
        fx = (xi - x0)[None, :]
        a = g[np.ix_(y0, x0)] * (1 - fx) + g[np.ix_(y0, x0 + 1)] * fx
        b = g[np.ix_(y0 + 1, x0)] * (1 - fx) + g[np.ix_(y0 + 1, x0 + 1)] * fx
        out += amp * (a * (1 - fy) + b * fy)
        amp *= 0.5
    return out / 1.9 - 0.5


def height_grid():
    srcs = sorted(str(p) for p in (c.RAW / "dem90").glob("*.tif")) + sorted(str(p) for p in (c.RAW / "dem").glob("*.tif"))
    h = RES / 2
    ds = gdal.Warp("", srcs, format="MEM", dstSRS=c.WORLD_PROJ, xRes=RES, yRes=RES,
                   outputBounds=(X0 - h, Y0 - h, X1 + h, Y1 + h), resampleAlg="average",
                   dstNodata=-9999, outputType=gdal.GDT_Float32)
    band = ds.GetRasterBand(1)
    nodata = band.ReadAsArray() < -500
    # 1000 px = 240 km reach; cost grows ~quadratically (4000 px took 5 h over OUTER_TOTAL)
    gdal.FillNodata(band, None, maxSearchDist=1000, smoothingIterations=3)
    a = band.ReadAsArray()[::-1].astype(np.float64)
    nodata = nodata[::-1]
    a[a < -500] = 0.0
    detail = fbm(a.shape, 60, 7) * 160.0  # synthetic relief only where there was no data
    land = a > 2.0
    a = np.where(nodata & land, a + detail, a)
    print(f"height grid {a.shape}, filled {nodata.mean() * 100:.0f}% synthetically")
    return a, nodata


def imagery_grid(res):
    """Real outer imagery (uint8, 0 = none) at res metres over OUTER_TOTAL; row 0 = north."""
    srcs = [str(p) for p in (c.RAW / "imagery" / "s2_outer.tif", c.RAW / "imagery" / "s2_outer_south.tif") if p.exists()]
    w, hgt = int((X1 - X0) / res), int((Y1 - Y0) / res)
    if not srcs:
        return np.zeros((hgt, w, 3), np.uint8)
    ds = gdal.Warp("", srcs, format="MEM", outputBounds=(X0, Y0, X1, Y1),
                   width=w, height=hgt, resampleAlg="average", dstNodata=0)
    return np.dstack([ds.GetRasterBand(b).ReadAsArray() for b in (1, 2, 3)]).astype(np.uint8)


def main():
    meta = json.loads((T / "meta.json").read_text())
    hgrid, filled = height_grid()
    n = c.TILE_N
    # imagery mosaic at 160 m over the whole box (level-4 tile resolution)
    img = imagery_grid(160.0)
    have = img.sum(axis=2, dtype=np.int32) > 0
    sel = img[have & (img.mean(axis=2) > 40)]
    land_col = np.median(sel, axis=0).astype(np.float32) if len(sel) else np.array([120, 110, 85])
    del sel
    sea_col = np.array([28, 52, 66], np.float32)
    meta["levels"] = meta["levels"][:c.OUTER_MIN_LEVEL]
    grid = hgrid
    for level in range(3, TOP + 1):
        size = c.TILE_SIZE * 2 ** level
        step = int(size / n / RES)  # grid samples per tile sample
        g = grid[::step, ::step] if step > 1 else grid
        tx0, ty0 = int(round(X0 / size)), int(round(Y0 / size))
        cx, cy = int(round((X1 - X0) / size)), int(round((Y1 - Y0) / size))
        tiles = {}
        for d in ("h", "img", "lc"):
            (T / d / str(level)).mkdir(parents=True, exist_ok=True)
        for j in range(cy):
            for i in range(cx):
                tx, ty = tx0 + i, ty0 + j
                jj = np.clip(np.arange(j * n, j * n + n + 1), 0, g.shape[0] - 1)
                ii = np.clip(np.arange(i * n, i * n + n + 1), 0, g.shape[1] - 1)
                t = g[np.ix_(jj, ii)]
                v = np.clip(np.round((t - c.H_OFFSET) / c.H_SCALE), 0, 65535).astype("<u2")
                v.tofile(T / "h" / str(level) / f"{tx}_{ty}.r16")
                tiles[f"{tx}_{ty}"] = [round(float(t.min()), 1), round(float(t.max()), 1)]
                # imagery: crop the 160 m mosaic (rows north->south), resample to IMG_N
                px = img.shape[1] / (X1 - X0)
                r0 = int((Y1 - (ty + 1) * size) * px)
                c0 = int((tx * size - X0) * px)
                k = int(size * px)
                crop = img[r0:r0 + k, c0:c0 + k]
                hv = have[r0:r0 + k, c0:c0 + k]
                idx = (np.linspace(0, k - 1, c.IMG_N)).astype(int)
                crop = crop[np.ix_(idx, idx)].astype(np.float32)
                hv = hv[np.ix_(idx, idx)]
                hs = t[::-1][np.ix_((np.linspace(0, n, c.IMG_N)).astype(int), (np.linspace(0, n, c.IMG_N)).astype(int))]
                sea = hs <= 0.5
                noise = fbm((c.IMG_N, c.IMG_N), 24, (tx * 31 + ty * 17 + level) % 100003, 4)[..., None] * 60.0
                synth = np.where(sea[..., None], sea_col, land_col + noise)
                out = np.where(hv[..., None], crop, synth)
                bc1.write_dds(T / "img" / str(level) / f"{tx}_{ty}.dds", np.clip(out, 0, 255).astype(np.uint8))
                lc = np.where(sea, 255, 0).astype(np.uint8)
                (T / "lc" / str(level) / f"{tx}_{ty}.r8.gz").write_bytes(gzip.compress(lc.tobytes(), 6))
        meta["levels"].append({"level": level, "size_m": size, "tx": [tx0, tx0 + cx - 1],
                               "ty": [ty0, ty0 + cy - 1], "tiles": tiles})
        print(f"level {level}: {len(tiles)} tiles of {size / 1000:.0f} km")
    meta["outer_box"] = list(c.OUTER_TOTAL)
    (T / "meta.json").write_text(json.dumps(meta))


if __name__ == "__main__":
    main()
