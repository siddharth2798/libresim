"""data/raw/imagery/s2.tif (world frame, 10 m) -> data/processed/terrain/img/<L>/<tx>_<ty>.jpg

One IMG_N x IMG_N JPEG per terrain tile (same L/tx/ty as the heightmaps, see
02_dem_tiles.py). Image row 0 is the NORTH edge (normal image order); the tile
covers world x in [tx*S, (tx+1)*S], y in [ty*S, (ty+1)*S], S = TILE_SIZE * 2^L.
Run 02_dem_tiles.py first (reads terrain/meta.json for the tile list).
"""
import json
import sys
from concurrent.futures import ThreadPoolExecutor

from osgeo import gdal

import common as c

gdal.UseExceptions()
SRC = c.RAW / "imagery" / "s2.tif"


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
    out = c.OUT / "terrain" / "img" / str(level) / f"{tx}_{ty}.jpg"
    if out.exists():
        return
    x0, y0 = tx * size, ty * size
    gdal.Translate(str(out), str(SRC), format="JPEG", projWin=[x0, y0 + size, x0 + size, y0],
                   width=c.IMG_N, height=c.IMG_N, resampleAlg="average",
                   creationOptions=["QUALITY=85"])
    aux = out.with_suffix(".jpg.aux.xml")
    if aux.exists():
        aux.unlink()


def main():
    ensure_overviews()
    meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
    jobs = []
    for L in meta["levels"]:
        (c.OUT / "terrain" / "img" / str(L["level"])).mkdir(parents=True, exist_ok=True)
        for key in L["tiles"]:
            tx, ty = map(int, key.split("_"))
            jobs.append((L["level"], tx, ty, L["size_m"]))
    with ThreadPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 8) as ex:
        list(ex.map(make_tile, jobs))
    meta["img_n"] = c.IMG_N
    (c.OUT / "terrain" / "meta.json").write_text(json.dumps(meta))
    print("imagery tiles:", len(jobs))


if __name__ == "__main__":
    main()
