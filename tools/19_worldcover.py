"""ESA WorldCover 2021 v200 land-cover class masks aligned with the imagery / land-class tiles.

Source: ESA WorldCover 2021 v200, 10 m, 11 classes, CC BY 4.0 (https://esa-worldcover.org),
public bucket, 3x3 degree cloud-optimised GeoTIFFs named by their SW corner (e.g. N18E072).
Nothing is downloaded whole: GDAL /vsicurl/ windowed reads into data/raw/worldcover/
  coarse/<tile>.tif   the 3x3 deg tile's 80 m overview (whole tile; underlay for coarse levels)
  cells/<lat>_<lon>.tif  0.5 deg windows at the full 10 m, only where level 0/1 terrain tiles are
Both steps are resumable (existing files are kept; atomic writes). Then for every terrain tile that
has an lc tile (same L/tx/ty, IMG_N px, row 0 = north) it writes
  data/processed/terrain/wc/<L>/<tx>_<ty>.r8.gz  (gzip of raw uint8, IMG_N x IMG_N)
holding a compact class code (0 = unknown / no data):
  1 tree cover(10)  2 shrubland(20)  3 grassland(30)  4 cropland(40)  5 built-up(50)
  6 bare/sparse(60)  7 snow/ice(70)  8 permanent water(80)  9 herbaceous wetland(90)
  10 mangroves(95)  11 moss/lichen(100)
Where a tile has lc a wc tile exists (all zero without data), so the runtime borrows both from the
same ancestor. Categorical resampling: nearest where a tile pixel is ~10 m, else mode (majority).
Levels <= 2 read the 10 m cells over the 80 m underlay, coarser levels the 80 m mosaic only.
Run after 11 (needs the lc tiles; covers every region's lc tiles). --workers N, --force (rebuild
tiles), --download-only.
"""
import argparse
import gzip
import math
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from osgeo import gdal

import common as c
import regions as R

gdal.UseExceptions()
N = c.IMG_N
LC = c.OUT / "terrain" / "lc"
WC = c.OUT / "terrain" / "wc"
RAW = c.RAW / "worldcover"
BASE = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/"
NAME = "ESA_WorldCover_10m_2021_v200_%s_Map.tif"
CELL_DEG = 0.5
PX_DEG = 1.0 / 12000.0           # 10 m
COARSE_OVR = 2                   # overview index 2 = 80 m
FINE_MAX_LEVEL = 2
CODES = {10: 1, 20: 2, 30: 3, 40: 4, 50: 5, 60: 6, 70: 7, 80: 8, 90: 9, 95: 10, 100: 11}
LUT = np.zeros(256, np.uint8)
for _k, _v in CODES.items():
    LUT[_k] = _v
GTIFF = ["COMPRESS=DEFLATE", "TILED=YES", "BLOCKXSIZE=512", "BLOCKYSIZE=512", "ZLEVEL=9"]
_ds_cache = {}


def src_name(lat3, lon3):
    return f"{'N' if lat3 >= 0 else 'S'}{abs(lat3):02d}{'E' if lon3 >= 0 else 'W'}{abs(lon3):03d}"


def tile_url(name):
    return "/vsicurl/" + BASE + NAME % name


def open_src(name):
    if name not in _ds_cache:
        gdal.SetConfigOption("GDAL_HTTP_MAX_RETRY", "5")
        gdal.SetConfigOption("GDAL_HTTP_RETRY_DELAY", "2")
        gdal.SetConfigOption("CPL_VSIL_CURL_ALLOWED_EXTENSIONS", ".tif")
        try:
            _ds_cache[name] = gdal.OpenEx(tile_url(name), open_options=[])
        except RuntimeError:
            _ds_cache[name] = None  # no such tile: open sea
    return _ds_cache[name]


def lc_tiles():
    out = []
    for d in sorted(LC.iterdir(), key=lambda p: int(p.name)):
        for f in sorted(d.glob("*.r8.gz")):
            tx, ty = map(int, f.name[:-6].split("_"))
            out.append((int(d.name), tx, ty))
    return out


def tile_lonlat_box(level, tx, ty, inv, pad=0.01):
    s = c.TILE_SIZE * 2 ** level
    pts = [inv(tx * s + i * s / 4, ty * s + j * s / 4) for i in range(5) for j in range(5)]
    return (min(p[0] for p in pts) - pad, min(p[1] for p in pts) - pad,
            max(p[0] for p in pts) + pad, max(p[1] for p in pts) + pad)


def plan(tiles, inv):
    """-> (set of 3 deg source tile names, set of (lat0, lon0) 0.5 deg cell origins)."""
    srcs, cells = set(), set()
    for level, tx, ty in tiles:
        x0, y0, x1, y1 = tile_lonlat_box(level, tx, ty, inv)
        for lat3 in range(math.floor(y0 / 3) * 3, math.floor(y1 / 3) * 3 + 1, 3):
            for lon3 in range(math.floor(x0 / 3) * 3, math.floor(x1 / 3) * 3 + 1, 3):
                srcs.add(src_name(lat3, lon3))
        if level <= 1:
            for i in range(math.floor(y0 / CELL_DEG), math.floor(y1 / CELL_DEG) + 1):
                for j in range(math.floor(x0 / CELL_DEG), math.floor(x1 / CELL_DEG) + 1):
                    cells.add((i * CELL_DEG, j * CELL_DEG))
    return srcs, cells


def _atomic_translate(dst, src, **kw):
    tmp = dst.with_name(dst.stem + ".part.tif")
    gdal.Translate(str(tmp), src, format="GTiff", creationOptions=GTIFF, **kw)
    os.replace(tmp, dst)


def fetch_coarse(name):
    dst = RAW / "coarse" / f"{name}.tif"
    if dst.exists():
        return name, dst.stat().st_size, "cached"
    try:
        ds = gdal.OpenEx(tile_url(name), open_options=[f"OVERVIEW_LEVEL={COARSE_OVR}"])
    except RuntimeError:
        return name, 0, "no tile (open sea)"
    _atomic_translate(dst, ds)
    return name, dst.stat().st_size, "ok"


def cell_file(lat0, lon0):
    return RAW / "cells" / f"{lat0:+06.1f}_{lon0:+07.1f}.tif"


def fetch_cell(cell):
    lat0, lon0 = cell
    dst = cell_file(lat0, lon0)
    if dst.exists():
        return cell, dst.stat().st_size, "cached"
    lat3, lon3 = math.floor(lat0 / 3) * 3, math.floor(lon0 / 3) * 3
    ds = open_src(src_name(lat3, lon3))
    if ds is None:
        return cell, 0, "no tile"
    n = round(CELL_DEG / PX_DEG)
    xo, yo = round((lon0 - lon3) / PX_DEG), round((lat3 + 3 - (lat0 + CELL_DEG)) / PX_DEG)
    _atomic_translate(dst, ds, srcWin=[xo, yo, n, n])
    return cell, dst.stat().st_size, "ok"


def build_vrts():
    coarse = sorted(str(p) for p in (RAW / "coarse").glob("*.tif") if ".part" not in p.name)
    cells = sorted(str(p) for p in (RAW / "cells").glob("*.tif") if ".part" not in p.name)
    gdal.BuildVRT(str(RAW / "coarse.vrt"), coarse, srcNodata=0, VRTNodata=0)
    gdal.BuildVRT(str(RAW / "fine.vrt"), coarse + cells, srcNodata=0, VRTNodata=0, resolution="highest")
    return len(coarse), len(cells)


def make_tile(job):
    level, tx, ty, force = job
    dst = WC / str(level) / f"{tx}_{ty}.r8.gz"
    if dst.exists() and not force:
        return level, tx, ty, None
    s = c.TILE_SIZE * 2 ** level
    px = s / N
    vrt = RAW / ("fine.vrt" if level <= FINE_MAX_LEVEL else "coarse.vrt")
    ds = gdal.Warp("", str(vrt), format="MEM", dstSRS=c.WORLD_PROJ,
                   outputBounds=(tx * s, ty * s, (tx + 1) * s, (ty + 1) * s), width=N, height=N,
                   resampleAlg="near" if px < 10.5 else "mode", srcNodata=0, dstNodata=0)
    raw = ds.GetRasterBand(1).ReadAsArray()
    out = LUT[raw]
    tmp = dst.with_name(dst.name + ".part")
    tmp.write_bytes(gzip.compress(out.tobytes(), 6))
    os.replace(tmp, dst)
    return level, tx, ty, np.bincount(out.ravel(), minlength=12)


def report(res, groups):
    names = ["nodata", "tree", "shrub", "grass", "crop", "built", "bare", "snow", "water", "wetland", "mangrove", "moss"]
    for gname, keys in groups.items():
        tot = np.zeros(12)
        for level, tx, ty, h in res:
            if h is not None and (level, tx, ty) in keys:
                tot += h
        if tot.sum():
            print(f"  {gname}: " + ", ".join(f"{n} {v / tot.sum() * 100:.1f}%" for n, v in zip(names, tot) if v))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--force", action="store_true", help="rebuild existing wc tiles")
    ap.add_argument("--download-only", action="store_true")
    args = ap.parse_args()
    force = args.force
    t0 = time.time()
    inv = R.inverse_transformer()
    tiles = [t for t in lc_tiles()]
    if not tiles:
        sys.exit("no lc tiles: run tools/11_landclass.py first")
    srcs, cells = plan(tiles, inv)
    print(f"{len(tiles)} lc tiles -> {len(srcs)} source tiles, {len(cells)} fine cells (0.5 deg)")
    for d in ("coarse", "cells"):
        (RAW / d).mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(args.workers) as ex:
        coarse = list(ex.map(fetch_coarse, sorted(srcs)))
        for name, size, st in coarse:
            print(f"  coarse {name}: {size / 1e6:.1f} MB {st}")
        fine = list(ex.map(fetch_cell, sorted(cells), chunksize=2))
    print(f"download: coarse {sum(r[1] for r in coarse) / 1e6:.1f} MB, cells {sum(r[1] for r in fine) / 1e6:.1f} MB "
          f"({sum(1 for r in fine if r[2] == 'no tile')} cells outside any tile) [{time.time() - t0:.0f} s]")
    print("vrt: %d coarse, %d cells" % build_vrts())
    if args.download_only:
        return
    for level in {t[0] for t in tiles}:
        (WC / str(level)).mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(args.workers) as ex:
        res = list(ex.map(make_tile, [(*t, force) for t in tiles], chunksize=4))
    mp0 = {(0, *t) for t in c.region_tiles("mumbai_pune", 0)}
    kk1 = {(1, *t) for t in c.region_tiles("konkan_kerala", 1)}
    lvl3 = {t for t in tiles if t[0] == 3}
    print(f"wc tiles: {len(res)} ({sum(1 for r in res if r[3] is not None)} written) [{time.time() - t0:.0f} s]")
    report(res, {"mumbai_pune L0": mp0, "konkan_kerala L1": kk1, "outer L3": lvl3})
    size = sum(f.stat().st_size for f in WC.rglob("*.r8.gz"))
    print(f"wc output {size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
