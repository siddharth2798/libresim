"""Phase R raw data: Konkan-Kerala corridor (Mumbai -> Kochi). Resumable; re-run to finish.

  tools/.venv/bin/python tools/01d_fetch_corridor.py [all|dem|dem90|img|outer|osm]

dem    Copernicus GLO-30 tiles for every 1x1 deg cell touching corridor_lonlat() -> data/raw/dem/
       (all-sea cells have no tile in the bucket: 404 -> listed in data/raw/dem/missing_sea.txt)
dem90  Copernicus GLO-90 tiles covering OUTER_SOUTH -> data/raw/dem90/
img    Sentinel-2 cloudless at CORRIDOR_IMG_RES (20 m) in world-y bands of 7 level-1 tiles
       (107.52 km); each band = bbox of the level-1 tiles (15.36 km) touching the corridor in it,
       snapped to that grid, +1 tile margin north/south. -> data/raw/imagery/corridor/s2c_<k>.tif
       + s2_corridor.vrt
outer  Sentinel-2 cloudless at 80 m over OUTER_SOUTH -> data/raw/imagery/s2_outer_south.tif
osm    Geofabrik southern-zone extract (md5 checked) -> data/raw/osm/
"""
import hashlib
import math
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common as c  # noqa: E402

RAW = c.RAW
LAYER = os.environ.get("LAYER", "s2cloudless-2024_3857")
WMTS = ("WMTS:https://tiles.maps.eox.at/wmts/1.0.0/WMTSCapabilities.xml,"
        f"layer={LAYER},tilematrixset=GoogleMapsCompatible")
GDAL_ENV = dict(os.environ, GDAL_HTTP_MAX_RETRY="12", GDAL_HTTP_RETRY_DELAY="4",
                GDAL_CACHEMAX="1024",
                GDAL_DEFAULT_WMS_CACHE_PATH=str(RAW / "imagery" / "wmscache"))
JPEG_CO = ["-co", "COMPRESS=JPEG", "-co", "JPEG_QUALITY=90", "-co", "PHOTOMETRIC=YCBCR",
           "-co", "TILED=YES", "-co", "BIGTIFF=IF_SAFER"]
BAND_TILES = 7  # level-1 tiles per imagery band (north-south)
_lock = threading.Lock()


def log(*a):
    with _lock:
        print(time.strftime("%H:%M:%S"), *a, flush=True)


def cell_name(lat, lon):
    return f"{'N' if lat >= 0 else 'S'}{abs(lat):02d}_00_{'E' if lon >= 0 else 'W'}{abs(lon):03d}_00"


def download(url, dest, tries=5):
    """-> 'ok' | 'have' | '404'. Writes to .part then renames."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return "have"
    part = str(dest) + ".part"
    for i in range(tries):
        try:
            with urllib.request.urlopen(url, timeout=120) as r, open(part, "wb") as f:
                while True:
                    b = r.read(1 << 20)
                    if not b:
                        break
                    f.write(b)
            os.replace(part, dest)
            return "ok"
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):  # S3 answers 403/404 for missing keys
                return "404"
            log(f"  retry {i + 1}: {url}: {e}")
        except Exception as e:  # connection resets etc.
            log(f"  retry {i + 1}: {url}: {e}")
        time.sleep(4 * (i + 1))
    raise RuntimeError(f"failed: {url}")


def fetch_dem_cells(cells, res_code, bucket, outdir):
    os.makedirs(outdir, exist_ok=True)
    stats = {"ok": 0, "have": 0, "404": 0}
    sea = []
    for lat, lon in cells:
        t = f"Copernicus_DSM_COG_{res_code}_{cell_name(lat, lon)}_DEM"
        r = download(f"https://{bucket}.s3.amazonaws.com/{t}/{t}.tif", os.path.join(outdir, t + ".tif"))
        stats[r] += 1
        if r == "404":
            sea.append(cell_name(lat, lon))
    return stats, sea


def step_dem():
    from shapely.geometry import box
    poly = c.corridor_lonlat()
    x0, y0, x1, y1 = poly.bounds
    cells = [(la, lo) for la in range(math.floor(y0), math.ceil(y1))
             for lo in range(math.floor(x0), math.ceil(x1)) if box(lo, la, lo + 1, la + 1).intersects(poly)]
    log(f"dem: {len(cells)} GLO-30 cells touch the corridor")
    stats, sea = fetch_dem_cells(cells, "10", "copernicus-dem-30m", RAW / "dem")
    with open(RAW / "dem" / "missing_sea.txt", "w") as f:
        f.write("\n".join(sea) + "\n")
    log(f"dem: done {stats}; no tile (sea): {sea}")


def outer_south_lonlat_bounds():
    from osgeo import osr
    osr.UseExceptions()
    src = osr.SpatialReference()
    src.ImportFromProj4(c.WORLD_PROJ)
    dst = osr.SpatialReference()
    dst.ImportFromEPSG(4326)
    dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    ct = osr.CoordinateTransformation(src, dst)
    x0, y0, x1, y1 = c.OUTER_SOUTH
    pts = []
    for i in range(41):  # densified edges
        t = i / 40
        for x, y in ((x0 + (x1 - x0) * t, y0), (x0 + (x1 - x0) * t, y1),
                     (x0, y0 + (y1 - y0) * t), (x1, y0 + (y1 - y0) * t)):
            pts.append(ct.TransformPoint(x, y)[:2])
    lons, lats = [p[0] for p in pts], [p[1] for p in pts]
    return min(lons), min(lats), max(lons), max(lats)


def step_dem90():
    lo0, la0, lo1, la1 = outer_south_lonlat_bounds()
    log(f"dem90: OUTER_SOUTH lon {lo0:.3f}..{lo1:.3f} lat {la0:.3f}..{la1:.3f}")
    cells = [(la, lo) for la in range(math.floor(la0), math.ceil(la1))
             for lo in range(math.floor(lo0), math.ceil(lo1))]
    stats, sea = fetch_dem_cells(cells, "30", "copernicus-dem-90m", RAW / "dem90")
    log(f"dem90: done {stats} of {len(cells)} cells; no tile (sea): {len(sea)}")


def band_boxes():
    """[(k, xmin, ymin, xmax, ymax)] world metres, snapped to the level-1 tile grid."""
    from shapely.geometry import box
    poly = c.corridor_world()
    size = c.TILE_SIZE * 2 ** c.CORRIDOR_IMG_LEVEL
    x0, y0, x1, y1 = poly.bounds
    tiles = [(tx, ty) for ty in range(math.floor(y0 / size), math.ceil(y1 / size))
             for tx in range(math.floor(x0 / size), math.ceil(x1 / size))
             if box(tx * size, ty * size, (tx + 1) * size, (ty + 1) * size).intersects(poly)]
    ty_top = max(t[1] for t in tiles)
    bands = {}
    for tx, ty in tiles:
        bands.setdefault((ty_top - ty) // BAND_TILES, []).append((tx, ty))
    out = []
    for k in sorted(bands):
        ts = bands[k]
        txs, tys = [t[0] for t in ts], [t[1] for t in ts]
        # +1 tile margin north/south so neighbouring bands overlap (diagonal coast)
        out.append((k, min(txs) * size, (min(tys) - 1) * size, (max(txs) + 1) * size, (max(tys) + 2) * size))
    return out


def valid_tif(path):
    if not os.path.exists(path):
        return False
    r = subprocess.run(["gdalinfo", path], capture_output=True, text=True)
    return r.returncode == 0 and "Band 3" in r.stdout


def warp(ext, res, resampling, out, tries=4):
    if valid_tif(out):
        log(f"  have {out}")
        return
    part = out + ".part.tif"
    for i in range(tries):
        t0 = time.time()
        cmd = ["gdalwarp", "-overwrite", "-q", "-multi", "-wo", "NUM_THREADS=4",
               "-srcband", "1", "-srcband", "2", "-srcband", "3", "-nosrcalpha",
               "-t_srs", c.WORLD_PROJ, "-tr", str(res), str(res), "-r", resampling,
               "-te", *map(str, ext), *JPEG_CO, WMTS, part]
        r = subprocess.run(cmd, capture_output=True, text=True, env=GDAL_ENV)
        errs = [ln for ln in r.stderr.splitlines() if "ERROR" in ln]
        if r.returncode == 0 and not errs and valid_tif(part):
            os.replace(part, out)
            log(f"  wrote {out} in {time.time() - t0:.0f} s")
            return
        log(f"  attempt {i + 1} failed for {out} (rc {r.returncode}): {(errs or [r.stderr[-300:]])[:3]}")
        time.sleep(10)
    raise RuntimeError(f"imagery failed: {out}")


def step_img(workers=2):
    d = RAW / "imagery" / "corridor"
    os.makedirs(d, exist_ok=True)
    bands = band_boxes()
    res = c.CORRIDOR_IMG_RES
    for k, *e in bands:
        log(f"img band {k}: x {e[0]:.0f}..{e[2]:.0f} y {e[1]:.0f}..{e[3]:.0f} "
            f"({(e[2] - e[0]) / res:.0f} x {(e[3] - e[1]) / res:.0f} px)")
    with ThreadPoolExecutor(workers) as ex:
        list(ex.map(lambda b: warp(b[1:], res, "cubic", str(d / f"s2c_{b[0]}.tif")), bands))
    tifs = [str(d / f"s2c_{k}.tif") for k, *_ in bands]
    subprocess.run(["gdalbuildvrt", "-overwrite", str(d / "s2_corridor.vrt"), *tifs], check=True,
                   capture_output=True)
    log(f"img: done, {len(tifs)} bands + s2_corridor.vrt")


def step_outer():
    warp(c.OUTER_SOUTH, 80, "average", str(RAW / "imagery" / "s2_outer_south.tif"))
    log("outer: done")


def step_osm():
    d = RAW / "osm"
    url = "https://download.geofabrik.de/asia/india/southern-zone-latest.osm.pbf"
    dest = d / "southern-zone-latest.osm.pbf"
    want = urllib.request.urlopen(url + ".md5", timeout=60).read().decode().split()[0]
    for _ in range(3):
        download(url, dest)
        h = hashlib.md5()
        with open(dest, "rb") as f:
            for b in iter(lambda: f.read(1 << 22), b""):
                h.update(b)
        if h.hexdigest() == want:
            log(f"osm: md5 ok {want}, {os.path.getsize(dest) / 1e6:.0f} MB")
            return
        log(f"osm: md5 mismatch ({h.hexdigest()} != {want}), re-downloading")
        os.remove(dest)
    raise RuntimeError("osm: md5 never matched")


def main():
    step = sys.argv[1] if len(sys.argv) > 1 else "all"
    t0 = time.time()
    steps = {"dem": step_dem, "dem90": step_dem90, "img": step_img, "outer": step_outer, "osm": step_osm}
    if step == "all":
        # small downloads in one thread, imagery (slow, WMTS-bound) alongside
        def downloads():
            step_dem(); step_dem90(); step_osm()
        with ThreadPoolExecutor(2) as ex:
            fs = [ex.submit(downloads), ex.submit(lambda: (step_img(), step_outer()))]
            for f in fs:
                f.result()
    else:
        steps[step]()
    log(f"{step}: finished in {(time.time() - t0) / 60:.1f} min")


if __name__ == "__main__":
    main()
