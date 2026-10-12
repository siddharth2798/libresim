"""Remote airliner bays and the clash test for GA tie-downs (see airport_stands.py).

Remote bays: nose-in rows beside the apron's taxi lanes. For a point q on a lane, the stand stands
REMOTE_ROW_M to the side with the nose pointing away from the lane, so the lead-in is the
perpendicular back to q (tail 33 m plus wingtip clearance 18 m from a taxiing aircraft). Only edges
along the apron's long axis count (not the connectors across it). Candidates are walked along each
edge nearest the terminal first and accepted when the bay rectangle is inside the apron, clear of
buildings and bridges, 18 m from every taxi centre line (80 m from a runway) and clear of the bays
and lead-in strips already taken.
"""
import math

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

import stand_geom as G

REMOTE_ROW_M = 58.0
TAXI_CLEAR_M = 18.0
RUNWAY_CLEAR_M = 80.0
STEP_M = 2.0
MIN_EDGE_M = 45.0
AXIS_TOL_DEG = 25.0
APRON_EDGE_M = 15.0   # a lane this close to the apron polygon counts (OSM taxiways run along its edge)
MAX_REMOTE = 30
GA_TAXI_CLEAR_M = 15.0   # a C172 tie-down: 9 m taxiway half width plus a wing
GA_LANE_CLEAR_M = 11.0   # ... 5 m taxilane half width plus a wing
GA_OBSTACLE_CLEAR_M = 8.0
GA_EDGE_M = 9.0          # a tie-down this far inside the apron polygon: its edge is not survey-grade and
                         # the land-class / terrain patches under it are 10-30 m cells (water showed at 5 m)


def _long_axis(poly):
    """Bearing (0..180) of the long side of the polygon's minimum rotated rectangle."""
    c = list(poly.minimum_rotated_rectangle.exterior.coords)
    sides = [(math.dist(c[i], c[i + 1]), G.bearing(c[i + 1][0] - c[i][0], c[i + 1][1] - c[i][1])) for i in range(2)]
    return max(sides)[1] % 180.0


class Site:
    """Per-airport clearance geometry; add() records bays and lanes that later candidates must avoid."""

    def __init__(self, taxi, aprons, obstacles):
        n = taxi["nodes"]
        lines = [LineString([n[e[0]], n[e[1]]]) for e in taxi["edges"] if e[4] in ("taxiway", "taxilane")]
        lanes = [LineString([n[e[0]], n[e[1]]]) for e in taxi["edges"] if e[4] == "taxilane"]
        ways = [LineString([n[e[0]], n[e[1]]]) for e in taxi["edges"] if e[4] == "taxiway"]
        runs = [LineString([n[e[0]], n[e[1]]]) for e in taxi["edges"] if e[4] == "runway"]
        self.taxi_edges = [(e, n[e[0]], n[e[1]]) for e in taxi["edges"] if e[4] in ("taxiway", "taxilane")]
        self.lines = unary_union(lines) if lines else None
        self.lanes = unary_union(lanes) if lanes else None   # taxilanes: narrower, tie-downs may stand closer
        self.ways = unary_union(ways) if ways else None
        self.runways = unary_union(runs) if runs else None
        self.apron = unary_union(aprons).buffer(-1.0) if aprons else None
        self.axis = _long_axis(max(aprons, key=lambda a: a.area)) if aprons else None
        self.obstacles = obstacles
        self.ga_area = self.apron.buffer(-GA_EDGE_M) if self.apron is not None else None
        self.taken = []   # shapely geometries
        self._taken_u = None

    def add(self, geom):
        self.taken.append(geom)
        self._taken_u = None

    def taken_union(self):
        if self._taken_u is None and self.taken:
            self._taken_u = unary_union(self.taken)
        return self._taken_u

    def bay_ok(self, p, h):
        bay = G.bay(p, h)
        if self.apron is None or not self.apron.contains(bay):
            return False
        if self.obstacles is not None and self.obstacles.distance(bay) < 5.0:
            return False
        if self.lines is not None and self.lines.distance(bay) < TAXI_CLEAR_M:
            return False
        if self.runways is not None and self.runways.distance(bay) < RUNWAY_CLEAR_M:
            return False
        t = self.taken_union()
        return t is None or not bay.intersects(t)

    def ga_ok(self, x, y):
        """A GA tie-down point: off the taxiways, runways, buildings and the airliner stands."""
        pt = Point(x, y)
        if self.ga_area is not None and not self.ga_area.contains(pt):
            return False
        if self.ways is not None and self.ways.distance(pt) < GA_TAXI_CLEAR_M:
            return False
        if self.lanes is not None and self.lanes.distance(pt) < GA_LANE_CLEAR_M:
            return False
        if self.runways is not None and self.runways.distance(pt) < RUNWAY_CLEAR_M:
            return False
        if self.obstacles is not None and self.obstacles.distance(pt) < GA_OBSTACLE_CLEAR_M:
            return False
        t = self.taken_union()
        return t is None or t.distance(pt) > 4.0


def remote_bays(site, anchor, max_n):
    """[(p, heading)] nose-in rows along the apron's taxi edges, nearest the anchor point first."""
    def lane(a, b):   # along the apron's long axis: lanes, not the connectors that cross it
        return abs(G.angle_diff(G.bearing(b[0] - a[0], b[1] - a[1]) % 180.0, site.axis)) < AXIS_TOL_DEG
    edges = [(e, a, b) for e, a, b in site.taxi_edges if math.dist(a, b) >= MIN_EDGE_M and site.apron is not None
             and site.apron.distance(Point((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)) < APRON_EDGE_M and lane(a, b)]
    edges.sort(key=lambda t: math.dist(anchor, ((t[1][0] + t[2][0]) / 2, (t[1][1] + t[2][1]) / 2)))
    out = []
    for e, a, b in edges:
        length = math.dist(a, b)
        ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        for side in (1.0, -1.0):
            nx, ny = uy * side, -ux * side            # unit normal; the nose points along it
            h = G.bearing(nx, ny)
            t = G.BAY_W / 2
            while t <= length - G.BAY_W / 2 and len(out) < max_n:
                q = (a[0] + ux * t, a[1] + uy * t)
                p = (q[0] + nx * REMOTE_ROW_M, q[1] + ny * REMOTE_ROW_M)
                if site.bay_ok(p, h):
                    out.append((p, h))
                    site.add(G.bay(p, h))
                    site.add(LineString([p, q]).buffer(TAXI_CLEAR_M))
                    t += G.BAY_W
                else:
                    t += STEP_M
    return out


def _polygon(w):
    pts = [(p[1], p[2]) for p in w["pts"]]
    return Polygon(pts).buffer(0) if len(pts) >= 4 else None


def build_site(A, ws, aprons):
    """(Site, terminal polygons, buildings) of one airport. Site obstacles = buildings (terminals,
    hangars) and bridge tunnels; buildings alone are what the gate poses are checked against."""
    terms = [p for p in (_polygon(w) for w in ws if w["kind"] == "terminal") if p is not None]
    hang = [p for p in (_polygon(w) for w in ws if w["kind"] == "hangar") if p is not None]
    tunnels = [G.line([(q[1], q[2]) for q in w["pts"]]).buffer(3.0) for w in ws if w["kind"] == "jet_bridge" and len(w["pts"]) > 1]
    buildings = unary_union(terms + hang) if terms + hang else None
    parts = terms + hang + tunnels
    return Site(A["taxi"], aprons, unary_union(parts) if parts else None), terms, buildings
