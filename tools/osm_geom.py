"""Small numpy-only polygon helpers for 15_terminals.py (shoelace area / centroid, point in ring,
segment distances, convex hull, minimum-area oriented box)."""
import math

import numpy as np


def ring_ac(r):
    """Shoelace -> (|area|, centroid) of a ring."""
    x, y, x2, y2 = r[:, 0], r[:, 1], np.roll(r[:, 0], -1), np.roll(r[:, 1], -1)
    cr = x * y2 - x2 * y
    a = cr.sum() / 2
    cen = r.mean(axis=0) if abs(a) < 1e-9 else np.array([((x + x2) * cr).sum(), ((y + y2) * cr).sum()]) / (6 * a)
    return abs(float(a)), cen


def inside(p, r):
    x, y = r[:, 0], r[:, 1]
    x2, y2 = np.roll(x, -1), np.roll(y, -1)
    m = (y > p[1]) != (y2 > p[1])
    xs = x[m] + (p[1] - y[m]) * (x2[m] - x[m]) / (y2[m] - y[m])
    return int((xs > p[0]).sum()) % 2 == 1


def seg_dist(pts, r):
    """Min distance from points (N, 2) to the edges of ring/polyline r (M, 2)."""
    a, b = r[:-1], r[1:]
    ab = b - a
    ap = pts[:, None, :] - a[None]
    t = np.clip((ap * ab).sum(-1) / np.maximum((ab * ab).sum(-1), 1e-9), 0, 1)
    return float(np.sqrt(((ap - t[..., None] * ab) ** 2).sum(-1)).min())


def densify(r, step=20.0):
    n = [max(1, int(np.hypot(*(b - a)) // step)) for a, b in zip(r[:-1], r[1:])]
    return np.array([r[0]] + [a + (b - a) * k / m for a, b, m in zip(r[:-1], r[1:], n) for k in range(1, m + 1)])


def poly_dist(f, poly):
    """Distance from feature f to an area feature poly (0 if they touch/overlap)."""
    pts = densify(np.vstack(f["xy"]))
    rings = poly["xy"]
    if (any(inside(p, r) for p in pts[::max(1, len(pts) // 50)] for r in rings)
            or f["kind"] == "area" and any(inside(r[0], o) for r in rings for o in f["xy"])):
        return 0.0
    return min(seg_dist(pts, densify(r)) for r in rings)


def hull(pts):
    """Monotone-chain convex hull, closed ring."""
    P = sorted(set(map(tuple, pts)))
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])  # noqa: E731
    half = []
    for seq in (P, P[::-1]):
        h = []
        for p in seq:
            while len(h) >= 2 and cross(h[-2], h[-1], p) <= 0:
                h.pop()
            h.append(p)
        half += h[:-1]
    return np.array(half + half[:1])


def obb(pts):
    """Minimum-area oriented box over hull edges -> (length, width, heading_deg of long axis)."""
    h = hull(pts)
    d = np.diff(h, axis=0)
    u = d / np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)[:, None]
    v = np.stack([-u[:, 1], u[:, 0]], 1)
    du, dv = np.ptp(h @ u.T, axis=0), np.ptp(h @ v.T, axis=0)
    k = int(np.argmin(du * dv))
    du, dv = du[k], dv[k]
    ax = u[k] if du >= dv else v[k]
    return [round(max(du, dv), 1), round(min(du, dv), 1),
            round(math.degrees(math.atan2(ax[0], ax[1])) % 180.0, 1)]
