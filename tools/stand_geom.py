"""Geometry helpers for airport_stands.py: an A320-class (ICAO code C) reference aircraft.

Local frame of a stand: origin = the nose-gear stop point (what airport_ops.json stores as x, y),
s metres forward along the heading, u metres to the right. Heading is compass degrees (0 = north,
clockwise), world frame x east / y north, so  fwd = (sin h, cos h)  and  right = (cos h, -sin h).
"""
import math

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union

NOSE = 4.8        # nose tip ahead of the nose gear
TAIL = 32.8       # tail end behind it (37.6 m long)
SPAN = 35.8
FUSE_R = 2.0      # fuselage radius
CLEAR = 4.5       # ICAO wingtip clearance, code C
BAY_W = SPAN + 2 * CLEAR  # 44.8 m: the width of one bay
DOOR_STANDOFF = FUSE_R + 0.4  # cab tip to the centre line: fuselage radius plus the cab's rubber


def fwd(h_deg):
    h = math.radians(h_deg)
    return (math.sin(h), math.cos(h))


def right(h_deg):
    h = math.radians(h_deg)
    return (math.cos(h), -math.sin(h))


def bearing(dx, dy):
    return math.degrees(math.atan2(dx, dy)) % 360.0


def angle_diff(a, b):
    """Signed smallest difference a - b in degrees, -180..180."""
    return (a - b + 180.0) % 360.0 - 180.0


def place(p, h_deg, s, u):
    """World point at s ahead and u to the right of p for a stand heading h_deg."""
    f, r = fwd(h_deg), right(h_deg)
    return (p[0] + f[0] * s + r[0] * u, p[1] + f[1] * s + r[1] * u)


def _poly(p, h_deg, pts):
    return Polygon([place(p, h_deg, s, u) for u, s in pts])


def aircraft(p, h_deg):
    """Plan-view outline of the reference aircraft: fuselage, swept wings, tailplane."""
    fuse = [(-FUSE_R, -TAIL), (-FUSE_R, 1.0), (-0.8, NOSE), (0.8, NOSE), (FUSE_R, 1.0), (FUSE_R, -TAIL)]
    parts = [_poly(p, h_deg, fuse)]
    for sg in (1, -1):
        parts.append(_poly(p, h_deg, [(sg * FUSE_R, -7.7), (sg * SPAN / 2, -16.0),
                                      (sg * SPAN / 2, -17.8), (sg * FUSE_R, -14.7)]))
        parts.append(_poly(p, h_deg, [(sg * FUSE_R, -28.0), (sg * 6.2, -31.2),
                                      (sg * 6.2, -32.6), (sg * FUSE_R, -32.0)]))
    return unary_union(parts).buffer(0.1)   # the 0.1 m merges wings and tail with the fuselage


def bay(p, h_deg, margin=0.0):
    """The bay rectangle: wingtip clearance sideways, nose and tail ends padded the same way."""
    w = BAY_W / 2 + margin
    return _poly(p, h_deg, [(-w, -(TAIL + CLEAR + margin)), (-w, NOSE + CLEAR + margin),
                            (w, NOSE + CLEAR + margin), (w, -(TAIL + CLEAR + margin))])


def lane(p, h_deg, length, half_w=9.0):
    """Straight strip behind the stand (the lead-in / pushback line), length metres from p."""
    return _poly(p, h_deg, [(-half_w, 0.0), (-half_w, -length), (half_w, -length), (half_w, 0.0)])


def polyline_len(pts):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:]))


def line(pts):
    return LineString([(p[0], p[1]) for p in pts])
