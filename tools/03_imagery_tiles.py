"""data/raw/imagery/s2.tif (world frame, 10 m) -> data/processed/terrain/img/<L>/<tx>_<ty>.dds

One IMG_N x IMG_N BC1/DXT1 DDS (full mip chain, sRGB data) per terrain tile (same L/tx/ty as the heightmaps, see
02_dem_tiles.py). Image row 0 is the NORTH edge (normal image order); the tile
covers world x in [tx*S, (tx+1)*S], y in [ty*S, (ty+1)*S], S = TILE_SIZE * 2^L.
Run 02_dem_tiles.py first (reads terrain/meta.json for the tile list).

--region mumbai_pune | konkan_kerala | all (default all), --workers N (default 8).
konkan_kerala: tiles at levels >= CORRIDOR_IMG_LEVEL of meta_konkan_kerala.json, from the 20 m
corridor mosaic over the 80 m outer mosaics; pixels with no imagery get a flat sea/land colour
chosen from the tile heights. Sets flag bit 0 in meta_konkan_kerala.json for tiles that exist.
"""
import json
from concurrent.futures import ProcessPoolExecutor

import numpy as np

from osgeo import gdal

import bc1
import common as c
import regions as R

gdal.UseExceptions()
SRC = c.RAW / "imagery" / "s2.tif"
OUTER_SRC = c.RAW / "imagery" / "s2_outer.tif"  # 01c_fetch_outer_imagery.sh (optional)


def ensure_overviews():
    ds = gdal.Open(str(SRC))
    if ds.GetRasterBand(1).GetOverviewCount() == 0:
        print("building overviews...")
        ds = None
        ds = gdal.Open(str(SRC), gdal.GA_Update)
        ds.BuildOverviews("AVERAGE", [2, 4, 8, 16])
    ds = None


def make_tile(job):
    level, tx, ty, size = job
    out = c.OUT / "terrain" / "img" / str(level) / f"{tx}_{ty}.dds"
    if out.exists():
        return
    x0, y0 = tx * size, ty * size
    # outer 80 m mosaic underneath, inner 10 m imagery on top (no black past the inner edge)
    srcs = [str(p) for p in (OUTER_SRC, SRC) if p.exists()]
    ds = gdal.Warp("", srcs, format="MEM", outputBounds=(x0, y0, x0 + size, y0 + size),
                   width=c.IMG_N, height=c.IMG_N, resampleAlg="average")
    img = np.dstack([ds.GetRasterBand(b).ReadAsArray() for b in (1, 2, 3)]).astype(np.uint8)
    bc1.write_dds(out, img)


SEA, LAND = np.array([28, 52, 66], np.float32), np.array([112, 108, 80], np.float32)


def corridor_tile(job):
    level, tx, ty, size = job
    out = R.T / "img" / str(level) / f"{tx}_{ty}.dds"
    if out.exists():
        return
    x0, y0 = tx * size, ty * size
    ds = gdal.Warp("", R.corridor_img_sources(), format="MEM", dstSRS=c.WORLD_PROJ,
                   outputBounds=(x0, y0, x0 + size, y0 + size), width=c.IMG_N, height=c.IMG_N,
                   resampleAlg="average", srcNodata=0, dstNodata=0)
    img = np.dstack([ds.GetRasterBand(b).ReadAsArray() for b in (1, 2, 3)]).astype(np.uint8)
    hole = img.max(axis=2) == 0
    if hole.any():
        n = c.TILE_N
        h = np.fromfile(R.T / "h" / str(level) / f"{tx}_{ty}.r16", "<u2").reshape(n + 1, n + 1)
        idx = np.round(np.linspace(0, n, c.IMG_N)).astype(int)
        hs = h[::-1][np.ix_(idx, idx)] * c.H_SCALE + c.H_OFFSET  # row 0 = north
        fill = np.where((hs <= 0.5)[..., None], SEA, LAND)
        img = np.where(hole[..., None], fill, img).astype(np.uint8)
    bc1.write_dds(out, img)


def main_corridor(region, workers):
    meta = R.load_meta(region)
    jobs = []
    for L in meta["levels"]:
        if L["level"] < c.CORRIDOR_IMG_LEVEL:
            continue
        (R.T / "img" / str(L["level"])).mkdir(parents=True, exist_ok=True)
        jobs += [(L["level"], *map(int, k.split("_")), L["size_m"]) for k in L["tiles"]]
    print(f"{region}: {len(jobs)} imagery tiles from {[p.split('/')[-1] for p in R.corridor_img_sources()]}")
    with ProcessPoolExecutor(workers) as ex:
        list(ex.map(corridor_tile, jobs, chunksize=4))
    R.set_flag(meta, R.F_IMG, lambda lv, tx, ty: lv >= c.CORRIDOR_IMG_LEVEL and
               (R.T / "img" / str(lv) / f"{tx}_{ty}.dds").exists())
    R.save_meta(region, meta)


def main():
    args = R.parse_args(__doc__)
    for region in args.regions:
        if region == "mumbai_pune":
            main_mumbai_pune(args.workers)
        else:
            main_corridor(region, args.workers)


def main_mumbai_pune(workers):
    ensure_overviews()
    meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
    jobs = []
    for L in meta["levels"]:
        (c.OUT / "terrain" / "img" / str(L["level"])).mkdir(parents=True, exist_ok=True)
        for key in L["tiles"]:
            tx, ty = map(int, key.split("_"))
            jobs.append((L["level"], tx, ty, L["size_m"]))
    with ProcessPoolExecutor(workers) as ex:
        list(ex.map(make_tile, jobs))
    meta["img_n"] = c.IMG_N
    (c.OUT / "terrain" / "meta.json").write_text(json.dumps(meta))
    print("imagery tiles:", len(jobs))


if __name__ == "__main__":
    main()
