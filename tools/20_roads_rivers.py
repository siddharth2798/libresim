"""Road and river masks for the terrain shader: crisp ribbons the 10-20 m imagery cannot show.

Reads OSM highway (motorway ... residential, service, track) and waterway (river, canal, stream, drain) lines
for both regions (ways_extract.py: one pass over the Geofabrik extracts the first time, ~5 min, cached in
data/processed/osm/ways.npz) and writes, for every level-0 terrain tile that has any,
  data/processed/terrain/ro/0/<tx>_<ty>.png   1920 x 1920 (4 m texels), 2 channels (see road_raster.py)
a signed-distance field (0.16 m steps within 4 m of an edge) to the nearest ribbon edge plus the ribbon class, filtered bilinearly by the game so
3-8 m ribbons stay crisp. Roads never cross water (OSM water polygons + the land-class water mask) except on
bridges, never cross airport aprons / runways / taxiways, and minor roads and all waterways stop at aerodrome
fences. Run after 11 / 12 / 17 (needs the final land-class water mask), 04 (aeroways, water). Tiles are only
re-written with --force. --workers N (default 10), --refresh-osm re-reads the OSM extracts, --only tx_ty,...
"""
import argparse
import gzip
import json
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import zoom

import common as c
import regions as R
import road_raster as rr
import ways_extract as wx

OUT = c.OUT / "terrain" / "ro" / "0"
LC = c.OUT / "terrain" / "lc"
PAD = 30.0       # m: a tile also takes ways that end within PAD of it (distance field reach)
MAX_SEG = 100.0  # m: longer segments are split so their raster windows stay small
RWY_W, TWY_W, MARGIN = 60.0, 25.0, 8.0  # m, drawn widths of aeroway lines (+ margin on both sides)


def level0_tiles():
    tiles = set()
    for region in c.REGIONS:
        for key in R.load_meta(region)["levels"][0]["tiles"]:
            tx, ty = map(int, key.split("_"))
            if (R.T / "h" / "0" / f"{tx}_{ty}.r16").exists():
                tiles.add((tx, ty))
    return tiles


def segments(z):
    """All way segments (split at MAX_SEG): arrays p (n, 4), kind (n,), bridge (n,)."""
    pts, off = z["pts"].astype(np.float64), z["off"]
    wid = np.repeat(np.arange(len(off) - 1), np.diff(off))
    ok = wid[:-1] == wid[1:]
    a, b, w = pts[:-1][ok], pts[1:][ok], wid[:-1][ok]
    n = np.maximum(np.ceil(np.hypot(*(b - a).T) / MAX_SEG).astype(int), 1)
    idx = np.repeat(np.arange(len(a)), n)
    k = np.arange(n.sum()) - np.repeat(np.cumsum(n) - n, n)
    f0, f1 = (k / n[idx])[:, None], ((k + 1) / n[idx])[:, None]
    p = np.hstack([a[idx] + (b[idx] - a[idx]) * f0, a[idx] + (b[idx] - a[idx]) * f1])
    w = w[idx]
    return p, z["kind"][w], z["bridge"][w]


def by_tile(p, kind, bridge, tiles):
    """-> {(tx, ty): (p, kind, bridge)}: every segment goes to each tile its padded box touches."""
    S = c.TILE_SIZE
    x0 = np.floor((np.minimum(p[:, 0], p[:, 2]) - PAD) / S).astype(np.int64)
    x1 = np.floor((np.maximum(p[:, 0], p[:, 2]) + PAD) / S).astype(np.int64)
    y0 = np.floor((np.minimum(p[:, 1], p[:, 3]) - PAD) / S).astype(np.int64)
    y1 = np.floor((np.maximum(p[:, 1], p[:, 3]) + PAD) / S).astype(np.int64)
    ok = np.array(sorted(tx * 100000 + ty for tx, ty in tiles), np.int64)
    idxs, keys = [], []
    for dx in range(int((x1 - x0).max()) + 1):
        for dy in range(int((y1 - y0).max()) + 1):
            sel = np.nonzero((x0 + dx <= x1) & (y0 + dy <= y1))[0]
            key = (x0[sel] + dx) * 100000 + (y0[sel] + dy)
            keep = np.isin(key, ok)
            idxs.append(sel[keep])
            keys.append(key[keep])
    idx, key = np.concatenate(idxs), np.concatenate(keys)
    order = np.argsort(key, kind="stable")
    idx, key = idx[order], key[order]
    cuts = np.concatenate([[0], np.nonzero(np.diff(key))[0] + 1, [len(key)]])
    out = {}
    for a, b in zip(cuts[:-1], cuts[1:]):
        k = int(key[a])
        tx, ty = (k + 50000) // 100000, k - ((k + 50000) // 100000) * 100000
        i = idx[a:b]
        out[(int(tx), int(ty))] = (p[i], kind[i], bridge[i])
    return out


def lc_water(tx, ty):
    """Boolean water mask of the tile at RN x RN (rows from the south), from the finest land-class mask."""
    for lv in range(0, 4):
        sx, sy, span = tx >> lv, ty >> lv, 1 << lv
        f = LC / str(lv) / f"{sx}_{sy}.r8.gz"
        if f.exists():
            a = np.frombuffer(gzip.decompress(f.read_bytes()), np.uint8).reshape(c.IMG_N, c.IMG_N)
            q = c.IMG_N // span
            r0, c0 = (span - 1 - (ty - sy * span)) * q, (tx - sx * span) * q
            w = (a[r0:r0 + q, c0:c0 + q] == 255).astype(np.float32)
            return np.flipud(zoom(w, rr.RN / q, order=1, mode="nearest") > 0.5)
    return np.zeros((rr.RN, rr.RN), bool)


def raster_mask(tx, ty, polys, lines=()):
    """polys: [pts], lines: [(pts, width_m)] -> bool mask, rows from the south."""
    x0, y0 = tx * c.TILE_SIZE, ty * c.TILE_SIZE
    img = Image.new("L", (rr.RN, rr.RN), 0)
    d = ImageDraw.Draw(img)
    tp = lambda pts: [((x - x0) / rr.RES, (y - y0) / rr.RES) for x, y in pts]
    for pts in polys:
        d.polygon(tp(pts), fill=1)
    for pts, w in lines:
        d.line(tp(pts), fill=1, width=max(1, round(w / rr.RES)))
    return np.asarray(img) > 0


def make_tile(job):
    tx, ty, (p, kind, bridge), vec, force = job
    dst = OUT / f"{tx}_{ty}.png"
    if dst.exists() and not force:
        return tx, ty, -1
    brg = (bridge == 1) & (kind < rr.N_ROAD)
    sel = {"major": (kind < 5) & ~brg, "minor": (kind >= 5) & (kind < rr.N_ROAD) & ~brg,
           "bridge": brg, "river": kind >= rr.N_ROAD}
    F = {n: rr.field(p[m], kind[m], tx, ty) if m.any() else (np.full((rr.RN, rr.RN), rr.E_MAX, np.float32),
                                                             np.zeros((rr.RN, rr.RN), np.uint8))
         for n, m in sel.items()}
    water = lc_water(tx, ty) | raster_mask(tx, ty, vec["water"])
    hard = raster_mask(tx, ty, vec["aero_areas"], vec["aero_lines"])
    fence = raster_mask(tx, ty, vec["aerodromes"]) if vec["aerodromes"] else None
    nowater = water | hard
    sd_now = rr.signed_dist(nowater)  # shared by every road layer that must stay off water / aprons
    major = (np.maximum(F["major"][0], -sd_now), F["major"][1])
    sd_minor = rr.signed_dist(nowater | fence) if fence is not None else sd_now
    minor = (np.maximum(F["minor"][0], -sd_minor), F["minor"][1])
    bridge_l = (rr.cut(F["bridge"][0], hard), F["bridge"][1]) if hard.any() else F["bridge"]
    river_mask = water | hard | (fence if fence is not None else False) | (bridge_l[0] < -1.5)
    river_e = np.maximum(F["river"][0], -rr.signed_dist(river_mask)) if river_mask.any() else F["river"][0]
    E, C = rr.merge([major, minor, bridge_l, (river_e, F["river"][1])])
    arr = rr.encode(E, C)
    if not (arr[..., 1] > 0).any():
        return tx, ty, 0
    Image.fromarray(arr, "LA").save(dst, optimize=True, compress_level=9)
    return tx, ty, dst.stat().st_size


def _boxes(lists):
    return np.array([[np.min(np.asarray(p)[:, 0]), np.min(np.asarray(p)[:, 1]),
                      np.max(np.asarray(p)[:, 0]), np.max(np.asarray(p)[:, 1])] for p in lists]).reshape(-1, 4)


def vectors():
    """OSM polygons / aeroway lines used as masks, each with a bounding-box array for tile lookups."""
    osm = c.OUT / "osm"
    water = json.loads((osm / "water.json").read_text())
    aero = json.loads((osm / "aeroways.json").read_text())
    drome = [d["pts"] for d in json.loads((osm / "aerodromes.json").read_text())]
    lines = [(l["pts"], (RWY_W if l["kind"] == "runway" else TWY_W) + 2 * MARGIN) for l in aero["lines"]]
    areas = [a["pts"] for a in aero["areas"]]
    items = {"water": water, "aero_areas": areas, "aero_lines": lines, "aerodromes": drome}
    boxes = {"water": _boxes(water), "aero_areas": _boxes(areas), "aero_lines": _boxes([l for l, _ in lines]),
             "aerodromes": _boxes(drome)}
    return items, boxes


def near(vec, tx, ty):
    """The vector features whose bounding boxes touch tile (tx, ty) (a few KB per job instead of all of OSM)."""
    items, boxes = vec
    S = c.TILE_SIZE
    x0, y0, x1, y1 = tx * S - 100, ty * S - 100, (tx + 1) * S + 100, (ty + 1) * S + 100
    out = {}
    for name, b in boxes.items():
        hit = np.nonzero((b[:, 2] >= x0) & (b[:, 0] <= x1) & (b[:, 3] >= y0) & (b[:, 1] <= y1))[0]
        out[name] = [items[name][i] for i in hit]
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--force", action="store_true", help="rebuild existing tiles")
    ap.add_argument("--refresh-osm", action="store_true")
    ap.add_argument("--only", help="comma list of tx_ty tiles (testing)")
    args = ap.parse_args()
    t0 = time.time()
    z = wx.load(args.refresh_osm)
    tiles = level0_tiles()
    if args.only:
        tiles &= {tuple(map(int, t.split("_"))) for t in args.only.split(",")}
    groups = by_tile(*segments(z), tiles)
    print(f"{len(z['kind'])} ways -> {len(groups)} of {len(tiles)} tiles have ways [{time.time() - t0:.0f} s]")
    OUT.mkdir(parents=True, exist_ok=True)
    vec = vectors()
    jobs = [(tx, ty, g, near(vec, tx, ty), args.force) for (tx, ty), g in sorted(groups.items(), key=lambda kv: -len(kv[1][1]))]
    with ProcessPoolExecutor(args.workers) as ex:
        res = list(ex.map(make_tile, jobs, chunksize=1))
    done = [r for r in res if r[2] > 0]
    print(f"road/river tiles: {len(done)} written, {sum(1 for r in res if r[2] == -1)} kept, "
          f"{sum(1 for r in res if r[2] == 0)} empty [{time.time() - t0:.0f} s]")
    size = sum(f.stat().st_size for f in OUT.glob("*.png"))
    print(f"ro output {size / 1e6:.1f} MB in {len(list(OUT.glob('*.png')))} tiles")


if __name__ == "__main__":
    main()
