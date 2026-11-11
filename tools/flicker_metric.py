#!/usr/bin/env python3
"""Frame-to-frame flicker metric for a burst of consecutive screenshots (docs/FLICKER-PLAN.md, phase 0).

    tools/.venv/bin/python tools/flicker_metric.py <dir> [--pattern 'burst_*.png'] [--ui 0.64]
        [--edge v,320,350,250,350,450] [--heat out.png] [--threshold 24]

Prints the share of pixels that change by more than --threshold (0..255, any channel) between consecutive
frames, the largest changing regions, and optionally the sub-pixel position of one edge per frame (the 50 %
crossing of the strongest step along a line: axis h = along x at the given rows, v = along y at the given
columns). --ui is the share of the frame height that is 3D (the instruments below are ignored); the HUD
strip at the top is ignored as well. --heat writes frame 0 dimmed with the changing pixels in red (yellow:
changing in three or more frame pairs).

Acceptance (a still camera at a gate, DOF off): Mobile <= 0.3 % with the UI excluded; Forward+ see the plan.
"""
import argparse
import glob
import sys

import numpy as np
from PIL import Image

HUD_TOP = 0.10  # share of the height taken by the HUD strip


def load(d, pattern):
    fs = sorted(glob.glob(f"{d}/{pattern}"))
    if len(fs) < 2:
        sys.exit(f"need at least two frames matching {pattern} in {d}")
    return fs, [np.asarray(Image.open(f).convert("RGB")).astype(np.int16) for f in fs]


def changes(ims, thr):
    """Per-pixel count of consecutive pairs that differ by more than thr, and the largest difference."""
    cnt = np.zeros(ims[0].shape[:2], np.int16)
    mx = np.zeros_like(cnt)
    for a, b in zip(ims, ims[1:]):
        dd = np.abs(a - b).max(axis=2)
        cnt += dd > thr
        mx = np.maximum(mx, dd)
    return cnt, mx


def regions(cnt, mask, n=8):
    """The n largest connected groups of changing pixels (needs scipy; skipped without it)."""
    try:
        from scipy import ndimage
    except ImportError:
        print("   (scipy not installed: no region list)")
        return
    lab, k = ndimage.label(ndimage.binary_dilation(mask, iterations=2))
    if k == 0:
        return
    sizes = ndimage.sum(mask, lab, range(1, k + 1))
    objs = ndimage.find_objects(lab)
    for i in np.argsort(sizes)[::-1][:n]:
        sl = objs[i]
        c = cnt[sl][mask[sl]]
        print(f"   region x{sl[1].start}-{sl[1].stop} y{sl[0].start}-{sl[0].stop}  {int(sizes[i])} px"
              f"  changes in {c.mean():.1f} pairs/px (max {c.max()})")


def edge_position(im, axis, a0, a1, line):
    """50 % crossing of the strongest step of the median profile over 5 neighbouring lines; nan if none."""
    g = im.mean(axis=2)
    band = g[line - 2:line + 3, a0:a1] if axis == "h" else g[a0:a1, line - 2:line + 3].T
    p = np.median(band, axis=0)
    d = np.abs(np.diff(p))
    k = int(np.argmax(d))
    lo = p[:max(k - 3, 1)].mean()
    hi = p[k + 4:].mean() if k + 4 < len(p) else p[-1]
    mid = 0.5 * (lo + hi)
    for i in range(max(k - 4, 0), min(k + 5, len(p) - 1)):
        if (p[i] - mid) * (p[i + 1] - mid) <= 0 and p[i] != p[i + 1]:
            return a0 + i + (mid - p[i]) / (p[i + 1] - p[i])
    return float("nan")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dir")
    ap.add_argument("--pattern", default="burst_*.png")
    ap.add_argument("--threshold", type=int, default=24)
    ap.add_argument("--ui", type=float, default=0.64, help="share of the height that is 3D (below is UI)")
    ap.add_argument("--edge", help="axis,a0,a1,line[,line...]  e.g. v,320,350,250,350")
    ap.add_argument("--heat", help="write a heat map PNG here")
    args = ap.parse_args()

    fs, ims = load(args.dir, args.pattern)
    h, w = ims[0].shape[:2]
    cnt, mx = changes(ims, args.threshold)
    mask = cnt >= 1
    scene = np.zeros_like(mask)
    scene[int(h * HUD_TOP):int(h * args.ui), :] = True
    in3d = mask & scene
    print(f"{args.dir}: {len(ims)} frames {w}x{h}, threshold {args.threshold}")
    print(f"  pixels changing in any pair: {mask.sum()} ({100 * mask.mean():.2f} %); "
          f"3D area only: {in3d.sum()} ({100 * in3d.sum() / scene.sum():.2f} %); in >= 3 pairs: {(cnt >= 3).sum()}")
    regions(cnt, in3d)
    if args.edge:
        parts = args.edge.split(",")
        axis, a0, a1 = parts[0], int(parts[1]), int(parts[2])
        for line in [int(v) for v in parts[3:]]:
            xs = np.array([edge_position(im, axis, a0, a1, line) for im in ims])
            span = np.nanmax(xs) - np.nanmin(xs) if np.isfinite(xs).any() else float("nan")
            print(f"  edge {axis} line {line}: " + " ".join(f"{x:7.2f}" for x in xs) + f"  | wander {span:.2f} px")
    if args.heat:
        base = (ims[0] * 0.45).astype(np.uint8)
        base[mask] = [255, 40, 40]
        base[cnt >= 3] = [255, 255, 0]
        Image.fromarray(base).save(args.heat)
        print(f"  heat map: {args.heat}")


if __name__ == "__main__":
    main()
