"""Per-tile road / river signed-distance raster (used by 20_roads_rivers.py).

A level-0 tile (7680 m) becomes RN x RN texels of RES metres, row 0 = north (same orientation as the
imagery / land-class tiles). Each texel holds e = distance to the nearest road or waterway centreline minus
that class's drawn half-width (so e < 0 inside the ribbon) and the class of the nearest edge. Texels are
filtered bilinearly at runtime, so edges stay crisp at any zoom: the level set e = 0 of a linearly
interpolated distance field is exact once the half-width is at least half a texel (HW_MIN), whatever the
phase of the lattice; narrower real roads are drawn slightly wider than life.
Encoding (PNG, 2 channels: L = e byte, A = class): e = L * E_STEP + E_MIN (L = 0..63), class 0 = none,
class = kind + 1 (ways_extract.WAY_KINDS), >= 10 are waterways. Keep KIND_HW in step with RO_HW in
game/world/terrain_roads.gdshaderinc.
"""
import numpy as np
from scipy.ndimage import distance_transform_edt

import common as c

RES = 4.0
RN = int(c.TILE_SIZE / RES)  # 1920
E_MIN, E_MAX, E_STEP = -6.0, 4.0, 0.16  # 63 levels: coarse enough for PNG to stay ~375 MB over 2200 tiles
HW_MIN = 2.2  # half-width floor: RES / 2 plus a margin (see module doc)
# true half-widths (m): motorway trunk primary secondary tertiary unclassified residential service track
# river canal stream drain
KIND_HW = [5.5, 5.0, 4.5, 3.8, 3.2, 2.8, 2.5, 2.0, 1.6, 6.0, 4.0, 1.5, 1.5]
HW_DRAWN = np.maximum(KIND_HW, HW_MIN).astype(np.float32)
N_ROAD = 9
MINOR_ROADS = (5, 6, 7, 8)  # kinds not allowed inside an aerodrome fence


def _xy_centres(tx, ty):
    x0, y0 = tx * c.TILE_SIZE, ty * c.TILE_SIZE
    xs = x0 + (np.arange(RN) + 0.5) * RES
    ys = y0 + (np.arange(RN) + 0.5) * RES  # row j from the SOUTH here; flipped on save
    return x0, y0, xs, ys


def field(segs, kinds, tx, ty):
    """Distance field over the kinds present in segs [(x0, y0, x1, y1) rows]. -> (E float32 (RN, RN) rows
    from the south, C uint8 class). E = E_MAX / C = 0 where nothing is within range."""
    x0, y0, xs, ys = _xy_centres(tx, ty)
    E = np.full((RN, RN), E_MAX, np.float32)
    C = np.zeros((RN, RN), np.uint8)
    for (ax, ay, bx, by), k in zip(segs.tolist(), kinds.tolist()):
        hw = float(HW_DRAWN[k])
        r = hw + E_MAX
        i0 = max(0, int((min(ax, bx) - r - x0) / RES))
        i1 = min(RN, int((max(ax, bx) + r - x0) / RES) + 1)
        j0 = max(0, int((min(ay, by) - r - y0) / RES))
        j1 = min(RN, int((max(ay, by) + r - y0) / RES) + 1)
        if i1 <= i0 or j1 <= j0:
            continue
        dx, dy = bx - ax, by - ay
        l2 = dx * dx + dy * dy
        px = xs[i0:i1][None, :] - ax
        py = ys[j0:j1][:, None] - ay
        t = np.clip((px * dx + py * dy) / l2, 0.0, 1.0) if l2 > 0 else 0.0
        e = np.hypot(px - t * dx, py - t * dy) - hw
        sub = E[j0:j1, i0:i1]
        m = e < sub
        if m.any():
            sub[m] = e[m]
            C[j0:j1, i0:i1][m] = k + 1
    return E, C


def signed_dist(mask):
    """Metres to the boundary of a boolean mask: negative inside, positive outside."""
    if not mask.any():
        return np.full(mask.shape, 1e4, np.float32)
    if mask.all():
        return np.full(mask.shape, -1e4, np.float32)
    # distances to the nearest texel of the other side, minus half a texel: the border lies between texels,
    # so the field is 1-Lipschitz (a plain difference of the two transforms jumps by 2 texels across it)
    out = distance_transform_edt(~mask) - 0.5
    inside = -(distance_transform_edt(mask) - 0.5)
    return (np.where(mask, inside, out) * RES).astype(np.float32)


def cut(E, mask):
    """Hide the ribbon inside mask with a rounded taper at its border (continuous in e)."""
    return np.maximum(E, -signed_dist(mask))


def merge(layers):
    """layers: [(E, C), ...] -> (E, C) of the union (nearest edge wins)."""
    E, C = layers[0]
    E, C = E.copy(), C.copy()
    for e2, c2 in layers[1:]:
        m = e2 < E
        E[m] = e2[m]
        C[m] = c2[m]
    return E, C


def encode(E, C):
    """-> uint8 (RN, RN, 2) [L = e byte, A = class], row 0 = north."""
    keep = E < E_MAX - 0.02
    top = round((E_MAX - E_MIN) / E_STEP)
    byte = np.clip(np.round((E - E_MIN) / E_STEP), 0, top).astype(np.uint8)
    byte[~keep] = top
    cls = np.where(keep, C, 0).astype(np.uint8)
    return np.flipud(np.dstack([byte, cls]))
