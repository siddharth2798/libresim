"""Shore distance and openness of the water, for shore foam, depth colour and calm backwaters.

For every land-class tile that has water (terrain/lc/<L>/<tx>_<ty>.r8.gz, 255 = water) writes
  data/processed/terrain/sd/<L>/<tx>_<ty>.rg8.gz   gzip of raw interleaved uint8 pairs, IMG_N x IMG_N, row 0 = north
    R  signed distance to the shore in metres: 128 + d (1 m steps, +127 m deep water side, -128 m inland),
       from the mask smoothed by one texel so the 10-80 m raster staircase does not show in the foam lines
    G  openness 0..255: how far open water reaches around the point, mean of the 6 longest of 8 compass runs
       over water, capped at FETCH_M (open sea 255, offshore lake or backwater 100-130, narrow river ~20)
The mask is mosaicked with the 8 neighbouring tiles of the same level first (edge-replicated where a
neighbour does not exist), so there is no seam at tile borders. Tiles without any water get no file (the game
falls back to "deep, open"). Run after 11 / 12 / 17 (final lc masks). --workers N, --force.
"""
import argparse
import gzip
import time
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from scipy.ndimage import distance_transform_edt, gaussian_filter, zoom

import common as c

N = c.IMG_N
LC = c.OUT / "terrain" / "lc"
SD = c.OUT / "terrain" / "sd"
FETCH_M = 7500.0
DIRS = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)]  # (dy, dx) in image rows / cols


def read_lc(level, tx, ty):
    f = LC / str(level) / f"{tx}_{ty}.r8.gz"
    if not f.exists():
        return None
    return np.frombuffer(gzip.decompress(f.read_bytes()), np.uint8).reshape(N, N) == 255


def mosaic(level, tx, ty, pad):
    """Water mask of the tile plus `pad` texels around it from the neighbours (row 0 = north)."""
    centre = read_lc(level, tx, ty)
    A = np.pad(centre, pad, mode="edge")
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nb = read_lc(level, tx + dx, ty + dy)  # dy = +1 is north = above
            if nb is None:
                continue
            r0, c0 = pad + (-dy) * N, pad + dx * N
            ra, rb, ca, cb = max(r0, 0), min(r0 + N, N + 2 * pad), max(c0, 0), min(c0 + N, N + 2 * pad)
            A[ra:rb, ca:cb] = nb[ra - r0:rb - r0, ca - c0:cb - c0]
    return A


def runs(w, step_m):
    """Metres of water ahead (capped at FETCH_M) in each of the 8 directions, stacked (8, H, W)."""
    H, W = w.shape
    out = np.zeros((8, H, W), np.float32)
    cap = FETCH_M
    for k, (dy, dx) in enumerate(DIRS):
        r = np.zeros((H, W), np.float32)
        inc = step_m * (1.41421356 if dy and dx else 1.0)
        rows = range(H) if dy >= 0 else range(H - 1, -1, -1)
        if dy == 0:
            cols = range(W) if dx > 0 else range(W - 1, -1, -1)
            prev = None
            for x in cols:
                col = w[:, x]
                r[:, x] = np.where(col, (0.0 if prev is None else prev) + inc, 0.0)
                prev = r[:, x]
        else:
            for y in rows:
                py = y - dy
                if not 0 <= py < H:
                    r[y] = np.where(w[y], inc, 0.0)
                    continue
                prev = np.zeros(W, np.float32)
                if dx > 0:
                    prev[1:] = r[py, :-1]
                elif dx < 0:
                    prev[:-1] = r[py, 1:]
                else:
                    prev = r[py]
                r[y] = np.where(w[y], prev + inc, 0.0)
        out[k] = np.minimum(r, cap)
    return out


def make_tile(job):
    level, tx, ty, force = job
    dst = SD / str(level) / f"{tx}_{ty}.rg8.gz"
    if dst.exists() and not force:
        return level, tx, ty, -1
    px = c.TILE_SIZE * 2 ** level / N
    pad = int(min(N, FETCH_M / px + 2)) // 4 * 4  # a multiple of the coarse factor (<= 4)
    A = mosaic(level, tx, ty, pad)
    if not A.any():
        return level, tx, ty, 0
    sp = min(pad, int(160 / px) + 4)  # the signed distance only reaches +-128 m
    S = A[pad - sp:pad + N + sp, pad - sp:pad + N + sp]
    if S.all():
        sdf = np.full(S.shape, 127.0, np.float32)
    else:
        d_in = distance_transform_edt(S) - 0.5
        d_out = distance_transform_edt(~S) - 0.5
        sdf = gaussian_filter(np.where(S, d_in, -d_out).astype(np.float32), 1.0) * px
    # openness varies slowly: run the compass scans on a coarser grid, then interpolate
    f = max(1, int(round(8 * 10.0 / px)) // 2) if px < 40 else 1
    H = A.shape[0] // f * f
    coarse = A[:H, :H].reshape(H // f, f, H // f, f).mean(axis=(1, 3)) > 0.5
    ru = runs(coarse, px * f)
    open_c = np.sort(ru, axis=0)[2:].mean(axis=0) / FETCH_M
    q = pad // f
    cen = open_c[q:q + N // f, q:q + N // f]
    open_ = zoom(cen, f, order=1, mode="nearest") if f > 1 else cen
    out = np.empty((N, N, 2), np.uint8)
    out[..., 0] = np.clip(np.round(128.0 + sdf[sp:sp + N, sp:sp + N]), 0, 255)
    out[..., 1] = np.clip(np.round(open_ * 255.0), 0, 255)
    tmp = dst.with_name(dst.name + ".part")
    tmp.write_bytes(gzip.compress(out.tobytes(), 6))
    tmp.replace(dst)
    return level, tx, ty, dst.stat().st_size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", help="comma list of level:tx_ty (testing)")
    args = ap.parse_args()
    t0 = time.time()
    jobs = []
    for d in sorted(LC.iterdir(), key=lambda p: int(p.name)):
        (SD / d.name).mkdir(parents=True, exist_ok=True)
        for f in d.glob("*.r8.gz"):
            tx, ty = map(int, f.name[:-6].split("_"))
            jobs.append((int(d.name), tx, ty, args.force))
    if args.only:
        want = set(args.only.split(","))
        jobs = [j for j in jobs if f"{j[0]}:{j[1]}_{j[2]}" in want]
    with ProcessPoolExecutor(args.workers) as ex:
        res = list(ex.map(make_tile, jobs, chunksize=2))
    written = [r for r in res if r[3] > 0]
    print(f"shore tiles: {len(jobs)} lc tiles, {len(written)} written, {sum(1 for r in res if r[3] == -1)} kept, "
          f"{sum(1 for r in res if r[3] == 0)} without water [{time.time() - t0:.0f} s]")
    print(f"sd output {sum(f.stat().st_size for f in SD.rglob('*.rg8.gz')) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
