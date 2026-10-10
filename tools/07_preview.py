"""Sanity preview: mosaic terrain tiles of one level into a hillshaded PNG with
airports (red) and navaids (blue) overlaid, read back exactly as the game will.
Usage: 07_preview.py [level=1] [x0 y0 x1 y1 world-metre crop]
Output: data/processed/preview_L<level>.png
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


def main():
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
