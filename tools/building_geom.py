"""Building mesh pieces for 10_buildings.py (BLD2 vertex layout).

Per vertex: position, CUSTOM0 = (roof rgb from imagery, style) and CUSTOM1 = (height cm lo, hi, band, wall).
  style = (pid << 2) | roof type (0 flat, 1 hip roof); pid 0..63 is a per-building hash the shader
          turns into wall colour, window style and so on.
  height cm = the wall height incl. parapet (16 bit), the shader lays floors out from the ground.
  band  = 0..200 across a roof's parapet strip (0 outer edge, 200 inside), 250 rooftop box, 253 water tank.
  wall  = 0 on the ground ring, 255 on every other ring (the shader interpolates the height above ground).
Flat roofs of footprints >= PARAPET_MIN_AREA get a sloped parapet strip (outer edge raised by PARAPET_H);
small 4-corner footprints often get a hipped roof; big flat roofs get a stairwell box and/or a (hexagonal) water tank.
"""
import math

import mapbox_earcut as earcut
import numpy as np
from shapely.geometry import Polygon

KIND_BOX, KIND_TANK = 250, 253
BAND_IN = 200
PARAPET_W, PARAPET_H = 0.55, 0.45
PARAPET_MIN_AREA = 90.0
BOX_MIN_AREA, TANK_MIN_AREA = 250.0, 400.0


class Acc:
    """Vertex / index accumulator for one tile."""

    def __init__(self):
        self.pos, self.c0, self.c1, self.idx = [], [], [], []

    def vert(self, x, y, z, rgb, style, hcm, band, wall):
        self.pos.append((x, y, z))
        self.c0.append((*rgb, style))
        self.c1.append((hcm & 255, hcm >> 8, band, wall))
        return len(self.pos) - 1

    def ccw(self, a, b, c):
        """A triangle counter-clockwise seen from above in the world frame (Godot front = clockwise)."""
        self.idx.extend((a, c, b))

    def walls(self, lo, hi, n):
        for k in range(n):
            k2 = (k + 1) % n
            self.idx.extend((lo + k, hi + k, lo + k2, lo + k2, hi + k, hi + k2))


def inset_ring(ring, d):
    """The ring moved inwards by d with the same vertex count and order, or None."""
    n = len(ring)
    g = Polygon(ring).buffer(-d, join_style=2, mitre_limit=2.5)
    if g.is_empty or g.geom_type != "Polygon" or len(g.interiors) or len(g.exterior.coords) - 1 != n:
        return None
    c = np.asarray(g.exterior.coords)[:-1]
    if (np.dot(c[:, 0], np.roll(c[:, 1], -1)) - np.dot(c[:, 1], np.roll(c[:, 0], -1))) < 0:
        c = c[::-1]
    k = min(range(n), key=lambda s: float(np.abs(np.roll(c, -s, axis=0) - ring).sum()))
    c = np.roll(c, -k, axis=0)
    return c if float(np.abs(c - ring).max()) < d * 3.0 else None


def _rect(p, ang, w, dp):
    """Corners (CCW, world) of a w x dp metre rectangle centred on p, rotated by ang."""
    ca, sa = math.cos(ang), math.sin(ang)
    return [(p[0] + ca * a - sa * b, p[1] + sa * a + ca * b) for a, b in ((-w / 2, -dp / 2), (w / 2, -dp / 2), (w / 2, dp / 2), (-w / 2, dp / 2))]


def _stack(acc, ring2d, y0, y1, x0, yy0, rgb, style, hcm, kind):
    """Vertical prism over a CCW ring (world x/y) from y0 to y1, flat top."""
    n = len(ring2d)
    base = len(acc.pos)
    for y in (y0, y1):
        for (x, yw) in ring2d:
            acc.vert(x - x0, y, -(yw - yy0), rgb, style, hcm, kind, 255)
    acc.walls(base, base + n, n)
    tri = earcut.triangulate_float64(np.asarray(ring2d, float), np.array([n], np.uint32))
    for t in range(0, len(tri), 3):
        acc.ccw(base + n + int(tri[t]), base + n + int(tri[t + 1]), base + n + int(tri[t + 2]))


def rooftop(acc, ring_in, y_roof, area, rnd, x0, y0, rgb, style, hcm):
    """A stairwell / lift box and a water tank on a big flat roof (when they fit inside it)."""
    poly = Polygon(ring_in).buffer(-1.6, join_style=2, mitre_limit=2.0)
    if poly.is_empty or poly.geom_type != "Polygon":
        return
    cen = np.array(poly.centroid.coords[0])
    e = ring_in[1] - ring_in[0]
    ang = math.atan2(e[1], e[0])
    n = len(ring_in)
    if rnd(2) < 0.65:
        w, d = 2.2 + 1.2 * rnd(3), 2.2 + 0.9 * rnd(4)
        k = int(rnd(5) * n)
        for t in (0.45, 0.25, 0.0):
            p = cen + (ring_in[k] - cen) * t
            corners = _rect(p, ang, w, d)
            if poly.contains(Polygon(corners)):
                _stack(acc, corners, y_roof, y_roof + 2.3 + 0.5 * rnd(6), x0, y0, rgb, style, hcm, KIND_BOX)
                break
    if area >= TANK_MIN_AREA and rnd(7) < 0.7:
        k = (int(rnd(8) * n) + 2) % n
        for t in (0.5, 0.3, 0.0):
            p = cen + (ring_in[k] - cen) * t
            r = 0.85 + 0.25 * rnd(9)
            pts = [(p[0] + r * math.cos(a * math.pi / 3), p[1] + r * math.sin(a * math.pi / 3)) for a in range(6)]
            if poly.contains(Polygon(pts)):
                _stack(acc, pts, y_roof, y_roof + 1.15 + 0.3 * rnd(10), x0, y0, rgb, style, hcm, KIND_TANK)
                break


def hip_roof(acc, q, y_eave, rise_k, t, rgb, style, hcm, x0, y0, base_idx):
    """Hip roof over 4 eave vertices (acc indices base_idx..+3, CCW). Returns the rise in metres."""
    P = np.asarray(q, float)
    if np.hypot(*(P[1] - P[2])) > np.hypot(*(P[0] - P[1])):
        P = np.roll(P, -1, axis=0)  # make edge 0-1 the long one
        order = [(base_idx + (i + 1) % 4) for i in range(4)]
    else:
        order = [base_idx + i for i in range(4)]
    m12, m30 = (P[1] + P[2]) / 2, (P[3] + P[0]) / 2
    half = float(np.hypot(*(P[2] - P[1]))) / 2
    rise = min(half * rise_k, 3.0)
    r1 = m12 + (m30 - m12) * t
    r0 = m30 + (m12 - m30) * t
    ids = [acc.vert(p[0] - x0, y_eave + rise, -(p[1] - y0), rgb, style, hcm, 0, 255) for p in (r0, r1)]
    q0, q1, q2, q3 = order
    ra, rb = ids
    acc.ccw(q0, q1, rb), acc.ccw(q0, rb, ra)
    acc.ccw(q1, q2, rb)
    acc.ccw(q2, q3, ra), acc.ccw(q2, ra, rb)
    acc.ccw(q3, q0, ra)
    return rise


def add_building(acc, ring, x0, y0, base, h, rgb, pid, rnd, pitch_prob, area):
    """Walls + roof of one CCW footprint; returns extra height above base + h (hip roof rise)."""
    n = len(ring)
    pitched = n == 4 and area < 150.0 and h <= 7.5 and rnd(1) < pitch_prob
    inner = None if pitched or area < PARAPET_MIN_AREA else inset_ring(ring, PARAPET_W)
    ph = PARAPET_H if inner is not None else 0.0
    hcm = int(min(65535, round((h + ph) * 100)))
    style = (pid << 2) | (1 if pitched else 0)
    g = len(acc.pos)
    for p in ring:
        acc.vert(p[0] - x0, base, -(p[1] - y0), rgb, style, hcm, 0, 0)
    t0 = len(acc.pos)
    for p in ring:
        acc.vert(p[0] - x0, base + h + ph, -(p[1] - y0), rgb, style, hcm, 0 if inner is not None else BAND_IN, 255)
    acc.walls(g, t0, n)
    if pitched:
        return hip_roof(acc, ring, base + h, 0.4 + 0.25 * rnd(11), 0.12 + 0.3 * rnd(12), rgb, style, hcm, x0, y0, t0)
    roof_ring, roof0 = ring, t0
    if inner is not None:
        i0 = len(acc.pos)
        for p in inner:
            acc.vert(p[0] - x0, base + h, -(p[1] - y0), rgb, style, hcm, BAND_IN, 255)
        for k in range(n):
            k2 = (k + 1) % n
            acc.ccw(t0 + k, t0 + k2, i0 + k2)
            acc.ccw(t0 + k, i0 + k2, i0 + k)
        roof_ring, roof0 = inner, i0
    tri = earcut.triangulate_float64(roof_ring, np.array([n], np.uint32))
    for t in range(0, len(tri), 3):
        acc.ccw(roof0 + int(tri[t]), roof0 + int(tri[t + 1]), roof0 + int(tri[t + 2]))
    if inner is not None and area >= BOX_MIN_AREA:
        rooftop(acc, inner, base + h, area, rnd, x0, y0, rgb, style, hcm)
    return 0.0
