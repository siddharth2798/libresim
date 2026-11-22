"""Leaf-card texture for the near tree meshes (game/world/tree_parts.gd, tree_mesh.gdshader).

Writes game/world/textures/trees/leaf_cards.png: 1024 x 512 RGBA, eight 256 px cells (4 x 2), all drawn here from
random shapes (libresim's own artwork, GPL-2.0-or-later like the code):
  (0, 0) broad leaves on twigs: mango, banyan, peepal, rain tree
  (1, 0) fine leaflets on pinnate twigs: acacia / babul scrub, casuarina
  (0, 1) one coconut frond seen from above: rachis down the middle (x = 0.5), leaflets to both sides, base at
         the bottom, tip at the top; the mesh maps the left half to one side of a V-shaped frond, the right
         half to the other
  (1, 1) large leaves: teak and the semi-evergreen Ghat forest
  (2, 0) casuarina needles hanging in strands     (3, 0) a grass tuft, base at the bottom (ground cover)
  (2, 1) fern / understorey fronds, base at the bottom   (3, 1) a dense small-leaved shrub (ground cover)
RGB is a near-grey brightness (per-leaf variation, darker midribs and twigs, a slight warm / cool shift per
leaf): the shader multiplies it by the species colour. Alpha is the leaf cover, anti-aliased by drawing at
4x and downsampling. Deterministic (fixed seed). Run: tools/.venv/bin/python -I tools/tree_leaf_cards.py
"""
import math
import pathlib
import random

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "world" / "textures" / "trees" / "leaf_cards.png"
CELL = 256
SS = 4  # supersampling
C = CELL * SS


def leaf_poly(cx, cy, ang, length, width, tip=1.0, n=14):
    """Outline of an elliptic leaf from its stalk point (cx, cy) along angle ang (radians)."""
    pts = []
    ca, sa = math.cos(ang), math.sin(ang)
    for k in range(n + 1):
        t = k / n
        w = width * 0.5 * math.sin(math.pi * t) ** (0.8 * tip)
        pts.append((t * length, w))
    for k in range(n, -1, -1):
        t = k / n
        w = width * 0.5 * math.sin(math.pi * t) ** (0.8 * tip)
        pts.append((t * length, -w))
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


class Cell:
    def __init__(self):
        self.lum = Image.new("L", (C, C), 0)
        self.warm = Image.new("L", (C, C), 128)
        self.alpha = Image.new("L", (C, C), 0)
        self.dl, self.dw, self.da = (ImageDraw.Draw(i) for i in (self.lum, self.warm, self.alpha))

    def poly(self, pts, lum, warm=128):
        self.dl.polygon(pts, fill=int(lum))
        self.dw.polygon(pts, fill=int(warm))
        self.da.polygon(pts, fill=255)

    def line(self, a, b, width, lum):
        self.dl.line([a, b], fill=int(lum), width=max(1, int(width)))
        self.dw.line([a, b], fill=110, width=max(1, int(width)))
        self.da.line([a, b], fill=255, width=max(1, int(width)))

    def leaf(self, rng, x, y, ang, length, width, tip=1.0):
        lum = rng.uniform(150, 235)
        self.poly(leaf_poly(x, y, ang, length, width, tip), lum, rng.uniform(100, 160))
        ex, ey = x + math.cos(ang) * length * 0.92, y + math.sin(ang) * length * 0.92
        self.dl.line([(x, y), (ex, ey)], fill=int(lum * 0.72), width=max(1, int(width * 0.06)))

    def rgba(self):
        out = []
        for im in (self.lum, self.warm, self.alpha):
            out.append(np.asarray(im.resize((CELL, CELL), Image.LANCZOS), np.float32))
        lum, warm, a = out
        t = (warm - 128.0) / 128.0 * 0.12
        rgb = np.stack([lum * (1 + t), lum, lum * (1 - t)], -1)
        return np.concatenate([np.clip(rgb, 0, 255), a[..., None]], -1)


def twigged(rng, cell, leaves, length, width, tip, spread):
    """Leaves grouped on a few twigs that start near the cell edge and reach in."""
    twigs = []
    for _ in range(5):
        a = rng.uniform(0, math.tau)
        sx, sy = C / 2 + math.cos(a) * C * 0.47, C / 2 + math.sin(a) * C * 0.47
        ex, ey = C / 2 + rng.uniform(-0.2, 0.2) * C, C / 2 + rng.uniform(-0.2, 0.2) * C
        cell.line((sx, sy), (ex, ey), C * 0.012, 70)
        twigs.append((sx, sy, ex, ey))
    for k in range(leaves):
        sx, sy, ex, ey = twigs[k % len(twigs)]
        t = rng.uniform(0.05, 0.95)
        x, y = sx + (ex - sx) * t, sy + (ey - sy) * t
        base = math.atan2(ey - sy, ex - sx)
        ang = base + rng.choice((-1, 1)) * rng.uniform(0.5, spread)
        L = length * rng.uniform(0.75, 1.15)
        cell.leaf(rng, x, y, ang, L, L * width, tip)


def broad(rng):
    cell = Cell()
    twigged(rng, cell, 70, C * 0.22, 0.38, 1.0, 1.3)
    return cell


def large(rng):
    cell = Cell()
    twigged(rng, cell, 26, C * 0.32, 0.6, 0.7, 1.4)
    return cell


def fine(rng):
    cell = Cell()
    for _ in range(11):
        a = rng.uniform(0, math.tau)
        sx, sy = C / 2 + math.cos(a) * C * 0.46, C / 2 + math.sin(a) * C * 0.46
        L = C * rng.uniform(0.35, 0.55)
        d = a + math.pi + rng.uniform(-0.5, 0.5)
        ex, ey = sx + math.cos(d) * L, sy + math.sin(d) * L
        cell.line((sx, sy), (ex, ey), C * 0.006, 80)
        for k in range(18):
            t = (k + 0.5) / 18
            x, y = sx + (ex - sx) * t, sy + (ey - sy) * t
            for side in (-1, 1):
                ll = C * 0.085 * (0.6 + 0.4 * math.sin(math.pi * t))
                cell.leaf(rng, x, y, d + side * rng.uniform(0.9, 1.3), ll, ll * 0.34)
    return cell


def frond(rng):
    """Coconut frond from above: thin midrib, ~50 pairs of long narrow leaflets with gaps between them."""
    cell = Cell()
    x0 = C * 0.5
    cell.line((x0, C * 0.99), (x0, C * 0.01), C * 0.012, 95)
    n = 50
    for k in range(n):
        t = (k + 0.5) / n  # 0 at the base (bottom), 1 at the tip (top)
        y = C * (1.0 - t) + rng.uniform(-2, 2) * SS
        L = C * 0.5 * (0.4 + 0.6 * math.sin(math.pi * (0.08 + 0.86 * t)) ** 0.6) * rng.uniform(0.85, 1.0)
        for side in (-1, 1):
            ang = -math.pi / 2 + side * (math.pi / 2 - rng.uniform(0.45, 0.7))  # leaflets lean towards the tip
            cell.leaf(rng, x0, y, ang, L, L * 0.045, 0.35)
    return cell


def needles(rng):
    """Casuarina: thin drooping needle strands hanging from twigs along the top."""
    cell = Cell()
    for _ in range(70):
        x = C * (0.5 + rng.triangular(-0.46, 0.46, 0.0))  # thicker in the middle: a ragged outline, not a block
        y0 = rng.uniform(0.0, 0.45) * C
        L = rng.uniform(0.25, 0.55) * C
        sway = rng.uniform(-0.12, 0.12) * C
        pts = [(x + sway * (k / 10) ** 2, y0 + L * k / 10) for k in range(11)]
        lum = rng.uniform(130, 220)
        for a, b in zip(pts, pts[1:]):
            cell.dl.line([a, b], fill=int(lum), width=int(C * 0.011))
            cell.dw.line([a, b], fill=int(rng.uniform(110, 150)), width=int(C * 0.011))
            cell.da.line([a, b], fill=255, width=int(C * 0.011))
    return cell


def grass(rng):
    """Grass tuft: tapered blades rising from the bottom centre, leaning out."""
    cell = Cell()
    for _ in range(38):
        bx = C * (0.5 + rng.uniform(-0.18, 0.18))
        lean = rng.uniform(-0.45, 0.45)
        L = C * rng.uniform(0.55, 0.98)
        w = C * rng.uniform(0.012, 0.022)
        tip = (bx + lean * L * 0.6, C - L)
        mid = (bx + lean * L * 0.25, C - L * 0.5)
        pts = [(bx - w, C), (mid[0] - w * 0.6, mid[1]), tip, (mid[0] + w * 0.6, mid[1]), (bx + w, C)]
        cell.poly(pts, rng.uniform(140, 235), rng.uniform(110, 170))
    return cell


def fern(rng):
    """Fern / understorey frond seen from the side: an arching rachis with paired pinnae, base at the bottom."""
    cell = Cell()
    for f in range(3):
        bx = C * (0.5 + (f - 1) * 0.12)
        lean = (f - 1) * 0.7 + rng.uniform(-0.1, 0.1)
        pts = [(bx + lean * C * 0.45 * (k / 12) ** 1.4, C - C * 0.92 * (k / 12) + C * 0.25 * (k / 12) ** 2 * abs(lean)) for k in range(13)]
        for a, b in zip(pts, pts[1:]):
            cell.line(a, b, C * 0.006, 90)
        for k in range(1, 12):
            x, y = pts[k]
            t = k / 12
            ll = C * 0.13 * math.sin(math.pi * (0.15 + 0.8 * t))
            d = math.atan2(pts[k + 1][1] - y, pts[k + 1][0] - x)
            for side in (-1, 1):
                cell.leaf(rng, x, y, d + side * 1.25, ll, ll * 0.3, 0.6)
    return cell


def shrub(rng):
    """Dense small-leaved bush (lantana, karvanda): many small leaves on short twigs."""
    cell = Cell()
    twigged(rng, cell, 110, C * 0.12, 0.5, 1.0, 1.5)
    return cell


def main():
    rng = random.Random(1729)
    cells = {(0, 0): broad(rng), (1, 0): fine(rng), (2, 0): needles(rng), (3, 0): grass(rng),
             (0, 1): frond(rng), (1, 1): large(rng), (2, 1): fern(rng), (3, 1): shrub(rng)}
    img = np.zeros((CELL * 2, CELL * 4, 4), np.float32)
    for (cx, cy), cell in cells.items():
        img[cy * CELL:(cy + 1) * CELL, cx * CELL:(cx + 1) * CELL] = cell.rgba()
    # colour under transparent texels: the mean leaf brightness, so mip levels do not bleed black
    a = img[..., 3:4] / 255.0
    mean = (img[..., :3] * a).sum((0, 1)) / max(a.sum(), 1.0)
    img[..., :3] = img[..., :3] * a + mean * (1.0 - a)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(img + 0.5, 0, 255).astype(np.uint8), "RGBA").save(OUT, optimize=True)
    print("wrote", OUT, OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
