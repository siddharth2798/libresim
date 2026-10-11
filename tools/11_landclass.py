"""Land-class masks aligned with the imagery tiles (same L/tx/ty, IMG_N px, row 0 = north).

Output data/processed/terrain/lc/<L>/<tx>_<ty>.r8.gz (gzip of raw uint8, IMG_N x IMG_N):
  255      water (sea from the DEM ~0 m + blue imagery, OSM water polygons)
  1..200   tree density (vegetation index of the imagery, minus buildings/roads/aeroways)
  0        other
Level 0 is classified; higher levels are 2x2-downsampled (majority water, mean density).
Run after 02, 03 (needs s2.tif), 04.

--region mumbai_pune | konkan_kerala | all (default all), --workers N (default 10).
konkan_kerala: levels >= CORRIDOR_IMG_LEVEL classified directly from the 20 m corridor imagery
(over the 80 m outer mosaics), sea from the tile heights, OSM water polygons and aeroways if
osm/water.json / aeroways.json exist (optional). Level 0 gets no lc (borrows the level-1 parent).
Sets flag bit 1 in meta_konkan_kerala.json.
"""
import gzip
import json
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from osgeo import gdal
from PIL import Image, ImageDraw

import common as c
import regions as R

gdal.UseExceptions()
N = c.IMG_N
PX = c.TILE_SIZE / N  # 10 m
OUT = c.OUT / "terrain" / "lc"


def load_vectors():
    osm = c.OUT / "osm"
    roads = json.loads((osm / "roads.json").read_text())
    water = json.loads((osm / "water.json").read_text())
    aero = json.loads((osm / "aeroways.json").read_text())
    return roads, water, aero


def _bbox(pts):
    a = np.asarray(pts)
    return a[:, 0].min(), a[:, 1].min(), a[:, 0].max(), a[:, 1].max()


def classify(job):
    tx, ty, roads, water, aero = job
    x0, y0, S = tx * c.TILE_SIZE, ty * c.TILE_SIZE, c.TILE_SIZE
    ds = gdal.Translate("", str(c.RAW / "imagery" / "s2.tif"), format="MEM",
                        projWin=[x0, y0 + S, x0 + S, y0], width=N, height=N)
    rgb = np.dstack([ds.GetRasterBand(b).ReadAsArray() for b in (1, 2, 3)]).astype(np.float32) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    exg = (2 * g - r - b) / (2 * g + r + b + 1e-3)
    bright = (r + g + b) / 3
    dens = np.clip((exg - 0.03) / 0.12, 0, 1) * (bright < 0.42)
    # heights at pixel centres from the level-0 DEM tile
    meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
    n = meta["tile_n"]
    hp = c.OUT / "terrain" / "h" / "0" / f"{tx}_{ty}.r16"
    h = np.fromfile(hp, "<u2").reshape(n + 1, n + 1) * meta["h_scale"] + meta["h_offset"]
    jj = (N - 1 - np.arange(N) + 0.5) * PX / c.DEM_RES  # row 0 = north
    ii = (np.arange(N) + 0.5) * PX / c.DEM_RES
    hgrid = h[np.clip(np.round(jj).astype(int), 0, n)][:, np.clip(np.round(ii).astype(int), 0, n)]
    sea = hgrid <= 0.3  # Copernicus flattens sea/water bodies to ~0 m (mangroves sit higher)
    # rasterise vector exclusions / water
    canvas = Image.new("L", (N, N), 0)  # 1 = no trees, 2 = water
    d = ImageDraw.Draw(canvas)
    tp = lambda pts: [((x - x0) / PX, (y0 + S - y) / PX) for x, y in pts]
    inside = lambda bb: not (bb[2] < x0 or bb[0] > x0 + S or bb[3] < y0 or bb[1] > y0 + S)
    for w in water:
        if inside(_bbox(w)):
            d.polygon(tp(w), fill=2)
    for rd in roads:
        if inside(_bbox(rd["pts"])):
            wid = {"motorway": 3, "trunk": 3, "primary": 2}.get(rd["cls"], 1)
            d.line(tp(rd["pts"]), fill=1, width=wid)
    for a in aero["areas"]:
        if inside(_bbox(a["pts"])):
            d.polygon(tp(a["pts"]), fill=1)
    for l in aero["lines"]:
        if inside(_bbox(l["pts"])):
            d.line(tp(l["pts"]), fill=1, width=8 if l["kind"] == "runway" else 3)
    bf = c.OUT / "osm" / "buildings" / f"{tx}_{ty}.bin"
    if bf.exists():
        raw = bf.read_bytes()
        i = 0
        while i < len(raw):
            k = int.from_bytes(raw[i:i + 2], "little")
            i += 6
            p = np.frombuffer(raw, "<f4", 2 * k, i).reshape(k, 2)
            i += 8 * k
            d.polygon(tp(p), fill=1, outline=1)
    m = np.asarray(canvas)
    out = np.round(dens * 200).astype(np.uint8)
    out[m == 1] = 0
    out[(m == 2) | sea] = 255
    (OUT / "0" / f"{tx}_{ty}.r8.gz").write_bytes(gzip.compress(out.tobytes(), 6))
    return (out == 255).mean(), (out > 0).mean()


def downsample(level, key, meta):
    tx, ty = map(int, key.split("_"))
    acc = np.zeros((N, N), np.float32)
    wat = np.zeros((N, N), np.float32)
    for dy in (0, 1):
        for dx in (0, 1):
            src = OUT / str(level - 1) / f"{2 * tx + dx}_{2 * ty + dy}.r8.gz"
            if not src.exists():
                continue
            a = np.frombuffer(gzip.decompress(src.read_bytes()), np.uint8).reshape(N, N).astype(np.float32)
            a2 = a.reshape(N // 2, 2, N // 2, 2)
            w = (a2 == 255).mean(axis=(1, 3))
            t = np.where(a2 == 255, 0, a2).mean(axis=(1, 3))
            r0 = (1 - dy) * (N // 2)  # north half is row 0
            c0 = dx * (N // 2)
            acc[r0:r0 + N // 2, c0:c0 + N // 2] = t
            wat[r0:r0 + N // 2, c0:c0 + N // 2] = w
    out = np.round(acc).astype(np.uint8)
    out[wat > 0.5] = 255
    (OUT / str(level) / f"{tx}_{ty}.r8.gz").write_bytes(gzip.compress(out.tobytes(), 6))


# The corridor mosaic (Sentinel-2 cloudless) is much greener than s2.tif: land excess-green
# median ~0.19 vs ~0.07, so the tree ramp is shifted (calibrated on Konkan / Kerala tiles).
CORR_EXG0, CORR_EXG_RAMP = 0.17, 0.14


def density(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    exg = (2 * g - r - b) / (2 * g + r + b + 1e-3)
    return np.clip((exg - CORR_EXG0) / CORR_EXG_RAMP, 0, 1) * ((r + g + b) / 3 < 0.42)


def classify_corridor(job):
    level, tx, ty, size, water, areas, lines = job
    x0, y0, px = tx * size, ty * size, size / N
    ds = gdal.Warp("", R.corridor_img_sources(), format="MEM", dstSRS=c.WORLD_PROJ,
                   outputBounds=(x0, y0, x0 + size, y0 + size), width=N, height=N,
                   resampleAlg="average", srcNodata=0, dstNodata=0)
    rgb = np.dstack([ds.GetRasterBand(b).ReadAsArray() for b in (1, 2, 3)]).astype(np.float32) / 255.0
    n = c.TILE_N
    h = np.fromfile(R.T / "h" / str(level) / f"{tx}_{ty}.r16", "<u2").reshape(n + 1, n + 1) * c.H_SCALE + c.H_OFFSET
    jj = np.clip(np.round((N - 1 - np.arange(N) + 0.5) * n / N).astype(int), 0, n)  # row 0 = north
    ii = np.clip(np.round((np.arange(N) + 0.5) * n / N).astype(int), 0, n)
    sea = h[jj][:, ii] <= 0.3
    canvas = Image.new("L", (N, N), 0)  # 1 = no trees, 2 = water
    d = ImageDraw.Draw(canvas)
    tp = lambda pts: [((x - x0) / px, (y0 + size - y) / px) for x, y in pts]
    for w in water:
        d.polygon(tp(w), fill=2)
    for a in areas:
        d.polygon(tp(a), fill=1)
    for pts, rwy in lines:
        d.line(tp(pts), fill=1, width=max(1, round((60 if rwy else 25) / px)))
    m = np.asarray(canvas)
    out = np.round(density(rgb) * 200).astype(np.uint8)
    out[m == 1] = 0
    out[(m == 2) | sea] = 255
    (OUT / str(level) / f"{tx}_{ty}.r8.gz").write_bytes(gzip.compress(out.tobytes(), 6))
    return (out == 255).mean(), (out > 0).mean()


def _pick(items, bbs, box):
    x0, y0, x1, y1 = box
    sel = (bbs[:, 2] >= x0) & (bbs[:, 0] <= x1) & (bbs[:, 3] >= y0) & (bbs[:, 1] <= y1)
    return [items[i] for i in np.nonzero(sel)[0]]


def main_corridor(region, workers):
    meta = R.load_meta(region)
    osm = c.OUT / "osm"
    water = json.loads((osm / "water.json").read_text()) if (osm / "water.json").exists() else []
    aero = json.loads((osm / "aeroways.json").read_text()) if (osm / "aeroways.json").exists() else {"lines": [], "areas": []}
    areas = [a["pts"] for a in aero["areas"]]
    lines = [(l["pts"], l["kind"] == "runway") for l in aero["lines"]]
    bb = lambda lst: np.array([_bbox(p) for p in lst]).reshape(-1, 4)
    wbb, abb, lbb = bb(water), bb(areas), bb([p for p, _ in lines])
    print(f"{region}: {len(water)} water polygons, {len(areas)} aeroway areas")
    jobs = []
    for L in meta["levels"]:
        if L["level"] < c.CORRIDOR_IMG_LEVEL:
            continue
        S = L["size_m"]
        (OUT / str(L["level"])).mkdir(parents=True, exist_ok=True)
        for k in L["tiles"]:
            tx, ty = map(int, k.split("_"))
            box = (tx * S, ty * S, (tx + 1) * S, (ty + 1) * S)
            jobs.append((L["level"], tx, ty, S, _pick(water, wbb, box), _pick(areas, abb, box), _pick(lines, lbb, box)))
    with ProcessPoolExecutor(workers) as ex:
        res = list(ex.map(classify_corridor, jobs, chunksize=4))
    print(f"{region}: {len(res)} lc tiles, water {np.mean([r[0] for r in res]) * 100:.0f}%, "
          f"trees {np.mean([r[1] for r in res]) * 100:.0f}%")
    R.set_flag(meta, R.F_LC, lambda lv, tx, ty: lv >= c.CORRIDOR_IMG_LEVEL and
               (OUT / str(lv) / f"{tx}_{ty}.r8.gz").exists())
    R.save_meta(region, meta)


def main():
    args = R.parse_args(__doc__, default_workers=10)
    for region in args.regions:
        if region == "mumbai_pune":
            main_mumbai_pune(args.workers)
        else:
            main_corridor(region, args.workers)


def main_mumbai_pune(workers):
    meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
    for L in meta["levels"]:
        (OUT / str(L["level"])).mkdir(parents=True, exist_ok=True)
    roads, water, aero = load_vectors()
    keys = list(meta["levels"][0]["tiles"])
    jobs = [(*map(int, k.split("_")), roads, water, aero) for k in keys]
    with ProcessPoolExecutor(workers) as ex:
        res = list(ex.map(classify, jobs, chunksize=4))
    print(f"level 0: {len(res)} tiles, water {np.mean([r[0] for r in res]) * 100:.0f}%, trees {np.mean([r[1] for r in res]) * 100:.0f}%")
    for L in meta["levels"][1:]:
        for key in L["tiles"]:
            downsample(L["level"], key, meta)
    print("levels done")


if __name__ == "__main__":
    main()
