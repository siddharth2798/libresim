"""Geometry building blocks for landmark terminal models (tools/16_terminal_models.py).

All inputs are in local metres: (east, north) footprints as shapely Polygons, heights z up.
Everything is written into a glb_writer.Glb in glTF axes: x = east, y = up, z = -north.
"""
import math

import mapbox_earcut as earcut
import numpy as np
from shapely.geometry import Polygon, MultiPolygon
from shapely.geometry.polygon import orient


def gl(e, n, z):
    return [e, z, -n]


def polys(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return list(geom.geoms)
    return [g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon)]


def walls(g, mat, poly, z0, z1, color=(0.8, 0.8, 0.8)):
    """Vertical walls (flat-shaded quads) around every ring of the polygon(s)."""
    for p in polys(poly):
        p = orient(p, 1.0)  # exterior CCW -> outward normals point right of travel
        for ring in [p.exterior] + list(p.interiors):
            c = np.asarray(ring.coords)[:, :2]
            pos, nrm, idx = [], [], []
            for i in range(len(c) - 1):
                (ax, ay), (bx, by) = c[i], c[i + 1]
                d = math.hypot(bx - ax, by - ay)
                if d < 0.05:
                    continue
                nx, ny = (by - ay) / d, -(bx - ax) / d  # right-hand normal (outward for CCW)
                k = len(pos)
                pos += [gl(ax, ay, z0), gl(bx, by, z0), gl(bx, by, z1), gl(ax, ay, z1)]
                nrm += [gl(nx, ny, 0)] * 4
                idx += [k, k + 1, k + 2, k, k + 2, k + 3]
            g.add(mat, pos, nrm, idx, color)


def cap(g, mat, poly, z, up=True, color=(0.8, 0.8, 0.8)):
    """Flat horizontal face (with holes) at height z."""
    for p in polys(poly):
        p = orient(p, 1.0)
        rings = [np.asarray(p.exterior.coords)[:-1, :2]] + [np.asarray(r.coords)[:-1, :2] for r in p.interiors]
        verts = np.vstack(rings)
        ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
        tri = earcut.triangulate_float64(verts, ends).reshape(-1, 3)
        if not up:
            tri = tri[:, ::-1]
        pos = [gl(e, n, z) for e, n in verts]
        g.add(mat, pos, [[0, 1 if up else -1, 0]] * len(pos), tri.ravel(), color)


def slab(g, mat, poly, z0, z1, color=(0.8, 0.8, 0.8), edge_mat=None):
    """Closed horizontal slab: roof plates, canopies, floor plates."""
    cap(g, mat, poly, z1, True, color)
    cap(g, mat, poly, z0, False, color)
    walls(g, edge_mat or mat, poly, z0, z1, color)


def mrr(poly):
    """Minimum rotated rectangle -> (centre (e, n), unit long axis, length, width)."""
    r = np.asarray(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    a, b, c = r[0], r[1], r[2]
    l1, l2 = np.linalg.norm(b - a), np.linalg.norm(c - b)
    axis = (b - a) / l1 if l1 >= l2 else (c - b) / l2
    return r.mean(0), axis, max(l1, l2), min(l1, l2)


def rect_poly(centre, axis, length, width):
    ax = np.asarray(axis)
    pe = np.array([-ax[1], ax[0]])
    hl, hw = ax * length / 2, pe * width / 2
    c = np.asarray(centre)
    return Polygon([c - hl - hw, c + hl - hw, c + hl + hw, c - hl + hw])


def _tri_face(g, mat, pts, color):
    """Planar convex polygon (list of (e, n, z)) with its geometric normal."""
    p = np.array([gl(*q) for q in pts], float)
    nrm = np.cross(p[1] - p[0], p[2] - p[0])
    if nrm[1] < 0:  # roof faces point up
        p = p[::-1]
        nrm = -nrm
    idx = []
    for i in range(1, len(p) - 1):
        idx += [0, i, i + 1]
    g.add(mat, p, [nrm] * len(p), idx, color)


def hip_roof(g, mat, centre, axis, length, width, z, rise, color=(0.6, 0.3, 0.2), gablet=0.0):
    """Hip roof over an oriented rectangle (eave height z). gablet > 0 cuts small vertical
    gables near the ridge ends (Kerala style), as a fraction of the end slope."""
    ax = np.asarray(axis, float)
    pe = np.array([-ax[1], ax[0]])
    c = np.asarray(centre, float)
    hl, hw = length / 2, width / 2
    ridge = max(hl - hw, 0.0)
    P = lambda u, v, h: (*(c + ax * u + pe * v), h)  # noqa: E731
    e = [P(-hl, -hw, z), P(hl, -hw, z), P(hl, hw, z), P(-hl, hw, z)]
    top = z + rise
    if gablet <= 0.0:
        r0, r1 = P(-ridge, 0, top), P(ridge, 0, top)
        _tri_face(g, mat, [e[0], e[1], r1, r0], color)
        _tri_face(g, mat, [e[2], e[3], r0, r1], color)
        _tri_face(g, mat, [e[1], e[2], r1], color)
        _tri_face(g, mat, [e[3], e[0], r0], color)
        return
    # hip with gablets: the end hips stop at height zg, a vertical triangle closes the gap
    zg = top - rise * gablet
    k = (zg - z) / rise  # fraction of the way up
    u_end = hl - k * hw
    v_end = hw * (1 - k)
    r0, r1 = P(-u_end, 0, top), P(u_end, 0, top)
    a0, b0 = P(-u_end, -v_end, zg), P(-u_end, v_end, zg)
    a1, b1 = P(u_end, -v_end, zg), P(u_end, v_end, zg)
    _tri_face(g, mat, [e[0], e[1], a1, r1, r0, a0], color)
    _tri_face(g, mat, [e[2], e[3], b0, r0, r1, b1], color)
    _tri_face(g, mat, [e[1], e[2], b1, a1], color)
    _tri_face(g, mat, [e[3], e[0], a0, b0], color)
    for a, b, r, s in [(a0, b0, r0, -1), (a1, b1, r1, 1)]:  # vertical gablet triangles
        p = np.array([gl(*q) for q in (a, b, r)], float)
        g.add("gable", p, [gl(*(ax * s), 0)] * 3, [0, 1, 2], (0.92, 0.9, 0.85))


def arch_panel(g, mat, a, b, z_spring, z_top, color, pointed=True, seg=10):
    """Vertical wall panel from a to b (e, n) with an arched opening below (pointed or round)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    d = float(np.linalg.norm(b - a))
    if d < 1.0:
        return
    rise = d * (0.62 if pointed else 0.5)
    rise = min(rise, (z_top - z_spring) * 0.85)
    prof = [(0.0, z_top), (0.0, z_spring)]
    for i in range(1, seg):
        t = i / seg
        x = d * t
        if pointed:  # two arcs meeting at the apex
            u = abs(2 * t - 1)
            z = z_spring + rise * math.sqrt(max(1 - u * u, 0.0)) ** 0.8
        else:
            z = z_spring + rise * math.sqrt(max(1 - (2 * t - 1) ** 2, 0.0))
        prof.append((x, z))
    prof += [(d, z_spring), (d, z_top)]
    pts2 = np.asarray(prof)
    tri = earcut.triangulate_float64(pts2, np.array([len(pts2)], np.uint32))
    ux = (b - a) / d
    nrm = gl(ux[1], -ux[0], 0)
    pos = [gl(*(a + ux * x), z) for x, z in pts2]
    g.add(mat, pos, [nrm] * len(pos), tri, color)


def vault(g, mat, centre, axis, length, width, z, rise, color=(0.85, 0.85, 0.85), seg=14):
    """Barrel vault along the long axis (curved roofs), smooth normals, with end caps."""
    ax = np.asarray(axis, float)
    pe = np.array([-ax[1], ax[0]])
    c = np.asarray(centre, float)
    hw = width / 2
    pos, nrm, idx = [], [], []
    for i in range(seg + 1):
        t = -1 + 2 * i / seg
        v = t * hw
        h = z + rise * (1 - t * t)
        slope = -2 * t * rise / hw  # dh/dv
        n2 = np.array([-slope, 1.0]) / math.hypot(slope, 1.0)
        for u in (-length / 2, length / 2):
            q = c + ax * u + pe * v
            pos.append(gl(q[0], q[1], h))
            nrm.append(gl(pe[0] * n2[0], pe[1] * n2[0], n2[1]))
        if i:
            k = len(pos) - 4
            idx += [k, k + 1, k + 3, k, k + 3, k + 2]
    g.add(mat, pos, nrm, idx, color)
    for u in (-length / 2, length / 2):  # end walls (gables) as glass
        prof = [(c + ax * u + pe * (t * hw), z + rise * (1 - t * t)) for t in np.linspace(-1, 1, seg + 1)]
        p = [gl(q[0], q[1], z) for q, _ in prof] + [gl(q[0], q[1], h) for q, h in prof]
        n = gl(*(ax * (1 if u > 0 else -1)), 0)
        m = seg + 1
        tri = []
        for i in range(seg):
            tri += [i, i + 1, m + i + 1, i, m + i + 1, m + i]
        g.add("glass", p, [n] * len(p), tri, (0.3, 0.4, 0.45))


def column(g, mat, e, n, z0, z1, r0, r1=None, color=(0.9, 0.9, 0.9), seg=10):
    """Round (optionally tapered) column."""
    r1 = r0 if r1 is None else r1
    pos, nrm, idx = [], [], []
    for i in range(seg + 1):
        a = 2 * math.pi * i / seg
        ca, sa = math.cos(a), math.sin(a)
        pos += [gl(e + ca * r0, n + sa * r0, z0), gl(e + ca * r1, n + sa * r1, z1)]
        nrm += [gl(ca, sa, 0)] * 2
        if i:
            k = len(pos) - 4
            idx += [k, k + 2, k + 3, k, k + 3, k + 1]
    g.add(mat, pos, nrm, idx, color)


def box(g, mat, centre, axis, length, width, z0, z1, color=(0.8, 0.8, 0.8)):
    slab(g, mat, rect_poly(centre, axis, length, width), z0, z1, color)
