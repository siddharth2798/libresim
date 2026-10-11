"""Sanity preview: mosaic terrain tiles of one level into a hillshaded PNG with
airports (red) and navaids (blue) overlaid, read back exactly as the game will.
Usage: 07_preview.py [level=1] [x0 y0 x1 y1 world-metre crop]
Output: data/processed/preview_L<level>.png
Quick-look of all regions (every meta*.json): 07_preview.py quicklook [level=2] [out.png]
  imagery (DDS mip 3, 96 px per tile) x hillshade, black where a tile has no imagery.
"""
import json
import sys

import numpy as np
from matplotlib import pyplot as plt

import common as c


def load_level(level):
    meta = json.loads((c.OUT / "terrain" / "meta.json").read_text())
    L = meta["levels"][level]
    n = meta["tile_n"]
    (tx0, tx1), (ty0, ty1) = L["tx"], L["ty"]
    mos = np.zeros(((ty1 - ty0 + 1) * n + 1, (tx1 - tx0 + 1) * n + 1))
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            v = np.fromfile(c.OUT / "terrain" / "h" / str(level) / f"{tx}_{ty}.r16", "<u2")
            h = v.reshape(n + 1, n + 1) * meta["h_scale"] + meta["h_offset"]
            j, i = (ty - ty0) * n, (tx - tx0) * n
            mos[j:j + n + 1, i:i + n + 1] = h
    S = L["size_m"]
    return mos, (tx0 * S, (tx1 + 1) * S, ty0 * S, (ty1 + 1) * S)


def bc1_decode(buf, w):
    """BC1 blocks (bytes) of a w x w image -> w x w x 3 uint8."""
    b = np.frombuffer(buf, "<u4").reshape(-1, 2)
    c0, c1 = b[:, 0] & 0xFFFF, b[:, 0] >> 16
    rgb = lambda v: np.stack([(v >> 11 & 31) * 255 / 31, (v >> 5 & 63) * 255 / 63, (v & 31) * 255 / 31], -1)
    p0, p1 = rgb(c0), rgb(c1)
    four = (c0 > c1)[:, None]
    pal = np.stack([p0, p1, np.where(four, (2 * p0 + p1) / 3, (p0 + p1) / 2),
                    np.where(four, (p0 + 2 * p1) / 3, 0)], 1)
    idx = (b[:, 1:2] >> (2 * np.arange(16, dtype=np.uint32))) & 3
    px = np.take_along_axis(pal, idx[..., None].astype(int), 1)  # (blocks, 16, 3)
    k = w // 4
    return px.reshape(k, k, 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(w, w, 3).astype(np.uint8)


def dds_mip(path, mip):
    raw = path.read_bytes()
    w, off = 768, 128
    for _ in range(mip):
        off += max(w // 4, 1) ** 2 * 8
        w //= 2
    return bc1_decode(raw[off:off + (w // 4) ** 2 * 8], w)


def quicklook(level, out):
    T = c.OUT / "terrain"
    tiles = {}
    for mp in sorted(T.glob("meta*.json")):
        for L in json.loads(mp.read_text())["levels"]:
            if L["level"] == level:
                for k, v in L["tiles"].items():
                    tiles[tuple(map(int, k.split("_")))] = (v[2] if len(v) > 2 else 3)
    W, n = 96, c.TILE_N
    xs, ys = [k[0] for k in tiles], [k[1] for k in tiles]
    tx0, ty0, tx1, ty1 = min(xs), min(ys), max(xs), max(ys)
    img = np.zeros(((ty1 - ty0 + 1) * W, (tx1 - tx0 + 1) * W, 3), np.float32)
    hm = np.full(img.shape[:2], np.nan)
    idx = np.round(np.linspace(0, n, W)).astype(int)
    for (tx, ty), flags in tiles.items():
        r, q = (ty1 - ty) * W, (tx - tx0) * W
        h = np.fromfile(T / "h" / str(level) / f"{tx}_{ty}.r16", "<u2").reshape(n + 1, n + 1)
        hm[r:r + W, q:q + W] = (h[::-1][np.ix_(idx, idx)] * c.H_SCALE + c.H_OFFSET)
        p = T / "img" / str(level) / f"{tx}_{ty}.dds"
        if flags & 1 and p.exists():
            img[r:r + W, q:q + W] = dds_mip(p, 3)
    S = c.TILE_SIZE * 2 ** level / W
    gy, gx = np.gradient(np.nan_to_num(hm), S)
    shade = np.clip(0.75 + (-gx + gy) * 2.0, 0.35, 1.3)
    rgb = np.clip(img * shade[..., None], 0, 255).astype(np.uint8)
    rgb[np.isnan(hm)] = (255, 255, 255)
    ext = (tx0 * S * W, (tx1 + 1) * S * W, ty0 * S * W, (ty1 + 1) * S * W)
    fig, ax = plt.subplots(1, 2, figsize=(14, 14 * rgb.shape[0] / rgb.shape[1] / 2 + 1), dpi=100)
    ax[0].imshow(rgb, extent=ext)
    ax[1].imshow(np.ma.masked_invalid(hm), extent=ext, cmap="terrain", vmin=-150, vmax=1800)
    ax[1].imshow(shade, extent=ext, cmap="gray", alpha=0.3)
    ax[0].set_title(f"level {level} imagery x hillshade ({len(tiles)} tiles)")
    ax[1].set_title("heights (m)")
    fig.savefig(out, bbox_inches="tight")
    print(out, rgb.shape)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "quicklook":
        level = int(sys.argv[2]) if len(sys.argv) > 2 else 2
        return quicklook(level, sys.argv[3] if len(sys.argv) > 3 else c.OUT / f"quicklook_L{level}.png")
    level = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    h, ext = load_level(level)
    res = (ext[1] - ext[0]) / (h.shape[1] - 1)
    gy, gx = np.gradient(h, res)
    shade = np.clip(0.6 + (-gx + gy) * 1.5 / np.sqrt(1 + gx ** 2 + gy ** 2), 0, 1)
    fig, ax = plt.subplots(figsize=(14, 11), dpi=110)
    ax.imshow(h, origin="lower", extent=ext, cmap="terrain", vmin=-150, vmax=1400)
    ax.imshow(shade, origin="lower", extent=ext, cmap="gray", alpha=0.35)
    for a in json.loads((c.OUT / "airports.json").read_text()):
        ax.plot(a["x"], a["y"], "r^", ms=5)
        ax.annotate(a["icao"] or a["ident"], (a["x"], a["y"]), fontsize=7, color="darkred")
    for nv in json.loads((c.OUT / "navaids.json").read_text()):
        ax.plot(nv["x"], nv["y"], "bs", ms=4)
        ax.annotate(f'{nv["ident"]} {nv["type"]}', (nv["x"], nv["y"]), fontsize=7, color="navy")
    if len(sys.argv) > 5:
        x0, y0, x1, y1 = map(float, sys.argv[2:6])
    else:
        x0, y0, x1, y1 = c.X_MIN, c.Y_MIN, c.X_MAX, c.Y_MAX
    ax.set_xlim(x0, x1)
    ax.set_ylim(y0, y1)
    ax.set_title(f"terrain level {level} (world metres, origin {c.ORIGIN_LAT}N {c.ORIGIN_LON}E)")
    out = c.OUT / f"preview_L{level}.png"
    fig.savefig(out, bbox_inches="tight")
    print(out)


if __name__ == "__main__":
    main()
