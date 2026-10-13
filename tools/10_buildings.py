"""OSM building footprints -> per-tile 3D building meshes for Godot.

Input:  data/processed/osm/buildings/<tx>_<ty>.bin (04_osm_extract.py), level-0 DEM tiles,
        roof colours from data/raw/imagery/s2.tif (10 m, Mumbai-Pune grid tiles) or
        data/raw/imagery/corridor/s2_corridor.vrt (20 m, Konkan-Kerala corridor tiles).
        Tiles whose level-0 heights do not exist yet are skipped (re-run after 02).
Output: data/processed/buildings/<tx>_<ty>.bin  (gzip) =
        b"BLD1", u32 nverts, u32 nidx,
        nverts * f32 xyz  (tile-local render axes: x = east - tile_x0, y = height AMSL, z = -(north - tile_y0)),
        nverts * u8 rgba  (rgb = roof colour from imagery, a = facade style 0..255),
        nidx * u32 indices (walls + earcut roofs; flat normals are made in the shader)
Also data/processed/buildings/<tx>_<ty>.col (gzip): b"COL1", u32 count, then per building
        u16 n, f32 base, f32 top, n * (f32 east, f32 north) world metres -- for collisions.
Two vertex rings per footprint (ground + roof line), shared between walls and roof.
Footprints listed in terminals/landmarks.json (16_terminal_models.py) are skipped in the
mesh (but kept in .col): those buildings are drawn as landmark terminal models.
Heights: OSM height / building:levels when tagged, else a deterministic synthetic
height from footprint area (Mumbai: small = 1-4 floors, large blocks up to ~40 m).
"""
import gzip
import json
import math
import os
import struct
import sys
from concurrent.futures import ProcessPoolExecutor

import mapbox_earcut as earcut
import numpy as np
from osgeo import gdal

import common as c
import osm_regions as R

gdal.UseExceptions()
SRC = c.OUT / "osm" / "buildings"
DST = c.OUT / "buildings"
MIN_AREA = 20.0
SIMPLIFY = 0.6  # m, Douglas-Peucker
DEFAULT_H = 9.0  # 04_osm_extract marks untagged buildings with this
CORRIDOR_VRT = c.RAW / "imagery" / "corridor" / "s2_corridor.vrt"
GRID = R.grid_tiles()


def read_tile(path):
    b = path.read_bytes()
    i, out = 0, []
    while i < len(b):
        n, h = struct.unpack_from("<Hf", b, i)
        i += 6
        out.append((h, np.frombuffer(b, "<f4", 2 * n, i).reshape(n, 2).astype(np.float64)))
        i += 8 * n
    return out


def dp(pts, eps):
    if len(pts) < 4:
        return pts
    a, b = pts[0], pts[-1]
    d = b - a
    L = np.hypot(*d) or 1e-9
    dist = np.abs(d[0] * (pts[:, 1] - a[1]) - d[1] * (pts[:, 0] - a[0])) / L
    k = int(np.argmax(dist))
    if dist[k] > eps:
        return np.vstack([dp(pts[:k + 1], eps)[:-1], dp(pts[k:], eps)])
    return np.vstack([a, b])


def simplify(ring):
    if len(ring) <= 4:
        return ring
    # split the closed ring at the farthest point so DP has two open chains
    k = int(np.argmax(np.hypot(*(ring - ring[0]).T)))
    p = np.vstack([dp(ring[:k + 1], SIMPLIFY)[:-1], dp(np.vstack([ring[k:], ring[:1]]), SIMPLIFY)[:-1]])
    return p if len(p) >= 3 else ring


def area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * (np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


MAX_TAGGED_H = 320.0  # tallest Mumbai towers are ~300 m; larger tags are OSM errors


def synth_height(a, cx, cy, tagged):
    if tagged != DEFAULT_H and 2.0 <= tagged <= MAX_TAGGED_H:
        return tagged
    r = (math.sin(cx * 12.9898 + cy * 78.233) * 43758.5453) % 1.0  # deterministic per building
    if a < 80:
        floors = 1 + int(r * 2)
    elif a < 400:
        floors = 2 + int(r * 4)
    elif a < 1500:
        floors = 3 + int(r * 8)
    else:
        floors = 4 + int(r * 10)
    return floors * 3.1 + 0.8


class Heights:
    def __init__(self, tx, ty):
        meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
        self.n = meta["tile_n"]
        p = c.OUT / "terrain" / "h" / "0" / f"{tx}_{ty}.r16"
        self.a = (np.fromfile(p, "<u2").reshape(self.n + 1, self.n + 1) * meta["h_scale"] + meta["h_offset"]
                  if p.exists() else np.zeros((self.n + 1, self.n + 1)))
        self.x0, self.y0 = tx * c.TILE_SIZE, ty * c.TILE_SIZE

    def at(self, x, y):
        fx = np.clip((x - self.x0) / c.DEM_RES, 0, self.n - 1e-6)
        fy = np.clip((y - self.y0) / c.DEM_RES, 0, self.n - 1e-6)
        i, j = fx.astype(int), fy.astype(int)
        u, v = fx - i, fy - j
        a = self.a
        return (a[j, i] * (1 - u) + a[j, i + 1] * u) * (1 - v) + (a[j + 1, i] * (1 - u) + a[j + 1, i + 1] * u) * v


def roof_colours(tx, ty):
    """(rgb image, metres per pixel) for a level-0 tile; both sources are in the world TM."""
    x0, y0, s = tx * c.TILE_SIZE, ty * c.TILE_SIZE, c.TILE_SIZE
    src, res = ((c.RAW / "imagery" / "s2.tif", 10.0) if (tx, ty) in GRID
                else (CORRIDOR_VRT, c.CORRIDOR_IMG_RES))
    n = int(s / res)
    ds = gdal.Translate("", str(src), format="MEM", projWin=[x0, y0 + s, x0 + s, y0], width=n, height=n)
    return np.dstack([ds.GetRasterBand(b).ReadAsArray() for b in (1, 2, 3)]), res


def landmark_paths():
    """Footprints replaced by landmark terminal models (16_terminal_models.py)."""
    f = c.OUT / "terminals" / "landmarks.json"
    if not f.exists():
        return []
    from matplotlib.path import Path
    return [Path(np.asarray(r)) for rings in json.loads(f.read_text()).values() for r in rings]


LANDMARKS = landmark_paths()


def write_atomic(path, data):
    """Temp file + rename: a running game never reads a half-written tile."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def build_tile(path):
    tx, ty = map(int, path.stem.split("_"))
    if not (c.OUT / "terrain" / "h" / "0" / f"{tx}_{ty}.r16").exists():
        return path.stem, -1, 0  # heights not generated yet
    hts = Heights(tx, ty)
    img, res = roof_colours(tx, ty)
    npx = img.shape[0] - 1
    x0, y0 = hts.x0, hts.y0
    pos, col, idx = [], [], []
    colrec = []
    nv = 0
    for tagged_h, ring in read_tile(path):
        if len(ring) < 3:
            continue
        ring = simplify(ring)
        a = area(ring)
        if abs(a) < MIN_AREA:
            continue
        if a < 0:
            ring = ring[::-1]  # CCW seen from above
        n = len(ring)
        cx, cy = ring.mean(0)
        base = float(hts.at(ring[:, 0], ring[:, 1]).min()) - 0.3
        h = synth_height(abs(a), cx, cy, tagged_h)
        pi = int(np.clip((cx - x0) / res, 0, npx))
        pj = int(np.clip((y0 + c.TILE_SIZE - cy) / res, 0, npx))
        rgb = img[pj, pi].astype(int)
        if (tx, ty) not in GRID and not rgb.any():  # corridor imagery gap
            rgb = np.array([150, 140, 130])
        style = int((math.sin(cx * 3.1 + cy * 7.7) * 9999.0) % 1.0 * 255)
        colrec.append(struct.pack("<Hff", n, base, base + h) + ring.astype("<f4").tobytes())
        if any(lp.contains_point((cx, cy)) for lp in LANDMARKS):
            continue  # drawn by the landmark terminal model instead (still collides)
        lx, lz = ring[:, 0] - x0, -(ring[:, 1] - y0)
        for k in range(n):  # ground ring then roof ring
            pos.append((lx[k], base, lz[k]))
        for k in range(n):
            pos.append((lx[k], base + h, lz[k]))
        col.extend([(*rgb, style)] * (2 * n))
        for k in range(n):
            k2 = (k + 1) % n
            b0, b1, t0, t1 = nv + k, nv + k2, nv + n + k, nv + n + k2
            idx.extend((b0, t0, b1, b1, t0, t1))  # clockwise seen from outside (Godot front)
        tri = earcut.triangulate_float64(ring, np.array([n], np.uint32))
        for t in range(0, len(tri), 3):  # earcut gives CCW in x/y; flip for Godot
            idx.extend((nv + n + int(tri[t]), nv + n + int(tri[t + 2]), nv + n + int(tri[t + 1])))
        nv += 2 * n
    if nv == 0:
        return path.stem, 0, 0
    p = np.asarray(pos, "<f4")
    cl = np.asarray(col, np.uint8)
    ix = np.asarray(idx, "<u4")
    data = b"BLD1" + struct.pack("<II", len(p), len(ix)) + p.tobytes() + cl.tobytes() + ix.tobytes()
    write_atomic(DST / f"{path.stem}.bin", gzip.compress(data, 6))
    cdata = b"COL1" + struct.pack("<I", len(colrec)) + b"".join(colrec)
    write_atomic(DST / f"{path.stem}.col", gzip.compress(cdata, 6))
    return path.stem, len(p), len(ix)


def main():
    DST.mkdir(parents=True, exist_ok=True)
    files = sorted(SRC.glob("*.bin"))
    if not CORRIDOR_VRT.exists():
        print(f"WARNING: {CORRIDOR_VRT} missing: corridor tiles skipped")
        files = [f for f in files if tuple(map(int, f.stem.split("_"))) in GRID]
    tv, skipped = 0, []
    with ProcessPoolExecutor(int(sys.argv[1]) if len(sys.argv) > 1 else 12) as ex:
        for name, nv, ni in ex.map(build_tile, files):
            if nv < 0:
                skipped.append(name)
            else:
                tv += nv
    size = sum(f.stat().st_size for f in DST.glob("*.bin"))
    size_c = sum(f.stat().st_size for f in DST.glob("*.col"))
    print(f"tiles {len(files) - len(skipped)}, vertices {tv}, meshes {size / 1e6:.0f} MB, collision {size_c / 1e6:.0f} MB")
    if skipped:
        print(f"SKIPPED {len(skipped)} tiles: no level-0 heights yet in terrain/h/0 (corridor terrain from 02); "
              f"re-run 10_buildings.py once they exist. e.g. {' '.join(sorted(skipped)[:8])}")


if __name__ == "__main__":
    main()
