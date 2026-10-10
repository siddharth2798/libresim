"""Cut smooth, flat pads into the DEM grid under runways and aprons.

Runways: OSM runway centrelines (fallback: OurAirports runway ends). Height along
the runway = least-squares line through DEM samples on the centreline; blended
into the terrain over FEATHER metres beyond the shoulder.
Aprons/taxiway areas: flattened to their median DEM height.
Grid convention: a[j, i] at x = X0 + i*DEM_RES, y = Y0 + j*DEM_RES (module globals).
"""
import json

import numpy as np

import common as c

SHOULDER = 20.0   # extra flat margin each side of the paved width
FEATHER = 120.0   # blend distance back to natural terrain
DEFAULT_W = 45.0
X0, Y0 = c.X_MIN, c.Y_MIN  # grid origin (02_dem_tiles sets these to its grid bounds)


def _sample(a, x, y):
    i = np.clip(np.round((x - X0) / c.DEM_RES).astype(int), 0, a.shape[1] - 1)
    j = np.clip(np.round((y - Y0) / c.DEM_RES).astype(int), 0, a.shape[0] - 1)
    return a[j, i]


def _window(a, xmin, ymin, xmax, ymax):
    i0 = max(int((xmin - X0) / c.DEM_RES), 0)
    i1 = min(int((xmax - X0) / c.DEM_RES) + 2, a.shape[1])
    j0 = max(int((ymin - Y0) / c.DEM_RES), 0)
    j1 = min(int((ymax - Y0) / c.DEM_RES) + 2, a.shape[0])
    if i0 >= i1 or j0 >= j1:
        return None
    xs = X0 + np.arange(i0, i1) * c.DEM_RES
    ys = Y0 + np.arange(j0, j1) * c.DEM_RES
    X, Y = np.meshgrid(xs, ys)
    return (slice(j0, j1), slice(i0, i1)), X, Y


def flatten_runway(a, p0, p1, width):
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    length = float(np.hypot(*d))
    if length < 100:
        return False
    u = d / length
    s = np.arange(0, length + 1, c.DEM_RES / 2)
    pts = p0 + np.outer(s, u)
    h = _sample(a, pts[:, 0], pts[:, 1])
    k, b = np.polyfit(s, h, 1)
    half = width / 2 + SHOULDER
    r = half + FEATHER
    lo, hi = np.minimum(p0, p1) - r, np.maximum(p0, p1) + r
    w = _window(a, lo[0], lo[1], hi[0], hi[1])
    if w is None:
        return False
    sl, X, Y = w
    rx, ry = X - p0[0], Y - p0[1]
    along = rx * u[0] + ry * u[1]
    cross = np.abs(-rx * u[1] + ry * u[0])
    over = np.maximum(np.maximum(-along, along - length), 0)  # beyond the ends
    dist = np.maximum(cross - half, 0) + over
    t = np.clip(1 - dist / FEATHER, 0, 1)
    t = t * t * (3 - 2 * t)  # smoothstep
    target = k * np.clip(along, 0, length) + b
    a[sl] = a[sl] * (1 - t) + target * t
    return True


def flatten_area(a, pts):
    pts = np.asarray(pts, float)
    lo, hi = pts.min(0) - FEATHER, pts.max(0) + FEATHER
    w = _window(a, lo[0], lo[1], hi[0], hi[1])
    if w is None:
        return False
    sl, X, Y = w
    from matplotlib.path import Path  # numpy-only point-in-polygon
    inside = Path(pts).contains_points(np.c_[X.ravel(), Y.ravel()]).reshape(X.shape)
    if not inside.any():
        return False
    target = float(np.median(a[sl][inside]))
    # distance-ish falloff: dilate inside mask by FEATHER using repeated max-filter
    t = inside.astype(float)
    steps = int(FEATHER / c.DEM_RES)
    m = t.copy()
    for k in range(1, steps + 1):
        p = np.pad(m, 1, mode="edge")
        m = np.maximum.reduce([p[1:-1, 1:-1], p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]])
        t = np.maximum(t, m * (1 - k / (steps + 1)))
    t = t * t * (3 - 2 * t)
    a[sl] = a[sl] * (1 - t) + target * t
    return True


def _width(tag, default):
    try:
        return float(str(tag).replace("m", "").strip())
    except ValueError:
        return default


def _axis(pts):
    d = pts[-1] - pts[0]
    return d / (np.hypot(*d) or 1)


def merge_runways(lines):
    """OSM often splits one runway into several ways: join collinear, touching pieces.
    Returns [(p0, p1, width)] spanning the full merged extent."""
    segs = [(np.asarray(l["pts"], float), _width(l["width"], 0.0)) for l in lines]
    groups = []
    for pts, w in segs:
        u = _axis(pts)
        for g in groups:
            gu = g["u"]
            off = pts[0] - g["pts"][0]
            if abs(abs(u @ gu) - 1) < 0.01 and abs(off[0] * gu[1] - off[1] * gu[0]) < 30:
                g["pts"] = np.vstack([g["pts"], pts])
                g["w"] = max(g["w"], w)
                break
        else:
            groups.append({"pts": pts, "u": u, "w": w})
    out = []
    for g in groups:
        s = (g["pts"] - g["pts"][0]) @ g["u"]
        out.append((g["pts"][0] + s.min() * g["u"], g["pts"][0] + s.max() * g["u"], g["w"] or DEFAULT_W))
    return out


def apply(a):
    n = 0
    aero = c.OUT / "osm" / "aeroways.json"
    airports = c.OUT / "airports.json"
    osm = json.loads(aero.read_text()) if aero.exists() else {"lines": [], "areas": []}
    # Aprons first so runways (which must be exact) win where they overlap.
    for ar in osm["areas"]:
        if ar["kind"] == "apron" and len(ar["pts"]) >= 4:
            n += flatten_area(a, ar["pts"])
    osm_rwys = [l for l in osm["lines"] if l["kind"] == "runway"]
    for p0, p1, w in merge_runways(osm_rwys):
        n += flatten_runway(a, p0, p1, w)
    if not osm_rwys and airports.exists():
        for ap in json.loads(airports.read_text()):
            for r in ap["runways"]:
                if r["le"] and r["he"]:
                    n += flatten_runway(a, (r["le"]["x"], r["le"]["y"]), (r["he"]["x"], r["he"]["y"]),
                                        r["width_m"] or DEFAULT_W)
    return n
