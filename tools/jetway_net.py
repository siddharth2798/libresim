"""Jet-bridge networks: which part of each OSM aeroway=jet_bridge way moves and which is a fixed link.

OSM maps a jet bridge as one way from the terminal wall to the cab, often through a long fixed
walkway (VABB T2: 40-70 m) to a rotunda where one or two apron-drive bridges start, or as a chain
of short ways (VOGA). The game draws one movable bridge (game/world/jetway_rig.gd) per cab tip,
hinged at its rotunda, and a fixed corridor (game/world/jetway_links.gd) between rotunda and building.

Per airport (called by 13_airport_ops.py, or `python jetway_net.py` to patch airport_ops.json in place):
  jetbridges[i] gets  rot [x, y]   the rotunda column (hinge) of its movable bridge
                      tip [x, y]   the cab end
                      back [x, y]  unit vector from the rotunda toward the building (the fixed stub)
                      own_rot      false when another bridge already draws this rotunda
                or    fixed: true  (only a fixed link / joins, no cab end)
                or    orphan: true (no building within ORPHAN_M of the network: not drawn)
  jetlinks: [{a: [x, y], b: [x, y]}]  fixed corridors; an end at a building runs INSET_M into it.
"pts" stays the full OSM way (apron_flatten.py levels the ground under it).
"""
import json
import math
import sys

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points, unary_union

ANCHOR_M = 6.0     # a node this close to a footprint (or inside it) is attached to the building
ORPHAN_M = 15.0    # a network with no node this close to a building is not drawn
MIN_TAIL = 12.0    # a movable bridge (rotunda to cab tip) is at least this long ...
MAX_TAIL = 45.0    # ... and at most this (longer: the rest towards the building is a fixed link)
BEND_DEG = 20.0    # a bend this sharp in the way is a rotunda
STUB_M = 7.28      # the jetway glb's fixed stub reaches this far behind the rotunda column (JetwayPose)
ROT_CLEAR = 3.5    # the rotunda column stands at least this far out of the wall (its room is 1.5 m deep)
INSET_M = 2.0      # fixed links and stubs run this far into the building


def _key(p):
    return (round(p[0], 1), round(p[1], 1))


def _unit(a, b):
    d = math.dist(a, b)
    return ((b[0] - a[0]) / d, (b[1] - a[1]) / d) if d > 1e-6 else (0.0, 0.0)


def _bend(prev, cur, nxt):
    a = _unit(cur, prev)
    b = _unit(cur, nxt)
    return 180.0 - math.degrees(math.acos(max(-1.0, min(1.0, a[0] * b[0] + a[1] * b[1]))))


class Net:
    """The jet-bridge graph of one airport, nodes keyed by their (0.1 m rounded) position."""

    def __init__(self, ways, bld):
        self.ways = ways
        self.bld = bld  # union of the building footprints near the bridges (or None)
        self.adj = {}
        for w in ways:
            ks = [_key(p) for p in w["pts"]]
            for a, b in zip(ks, ks[1:]):
                if a != b:
                    self.adj.setdefault(a, set()).add(b)
                    self.adj.setdefault(b, set()).add(a)
        self.dist = {k: self._sdist(k) for k in self.adj}

    def _sdist(self, p):
        """Signed distance to the nearest footprint wall: < 0 inside."""
        if self.bld is None:
            return 1e9
        pt = Point(p)
        d = self.bld.boundary.distance(pt)
        return -d if self.bld.contains(pt) else d

    def anchored(self, k):
        return self.dist[k] <= ANCHOR_M

    def deg(self, k):
        return len(self.adj[k])

    def component(self, k):
        seen, todo = {k}, [k]
        while todo:
            for n in self.adj[todo.pop()]:
                if n not in seen:
                    seen.add(n)
                    todo.append(n)
        return seen

    def walk_back(self, tip):
        """Path tip -> rotunda: through plain (degree 2) nodes until a junction, the building, a
        sharp bend or MAX_TAIL, but at least MIN_TAIL when it can."""
        path = [tip, next(iter(self.adj[tip]))]
        acc = math.dist(path[0], path[1])
        while True:
            cur = path[-1]
            if self.deg(cur) != 2 or self.anchored(cur):
                return path
            nxt = next(n for n in self.adj[cur] if n != path[-2])
            seg = math.dist(cur, nxt)
            if acc >= MIN_TAIL and (_bend(path[-2], cur, nxt) > BEND_DEG or acc + seg > MAX_TAIL):
                return path
            if nxt in path:
                return path
            path.append(nxt)
            acc += seg

    def into_building(self, p, d):
        """A link end at the building (p, link arriving along unit d): continued to INSET_M inside
        the first wall ahead (within ANCHOR_M + INSET_M), or pulled back when p is deeper."""
        if self.bld is None:
            return None
        if Point(p).within(self.bld):
            s = INSET_M - (-self._sdist(p))  # < 0: pull back toward the wall
            return (p[0] + d[0] * s, p[1] + d[1] * s) if s < 0 else p
        ray = LineString([p, (p[0] + d[0] * (ANCHOR_M + INSET_M + 2.0), p[1] + d[1] * (ANCHOR_M + INSET_M + 2.0))])
        hit = ray.intersection(self.bld)
        if hit.is_empty:
            q, _ = self.to_wall(p)
            return q
        s = min(math.dist(p, c) for g in getattr(hit, "geoms", [hit]) for c in g.coords) + INSET_M
        return (p[0] + d[0] * s, p[1] + d[1] * s)

    def to_wall(self, p):
        """The point INSET_M inside the nearest wall, seen from p (outside)."""
        _, q = nearest_points(Point(p), self.bld.boundary)
        d = _unit(p, (q.x, q.y))
        return (q.x + d[0] * INSET_M, q.y + d[1] * INSET_M), d


def solve(ways, bld):
    """Annotate ways in place; return the fixed links [{a, b}]."""
    net = Net(ways, bld)
    tips = [k for k in net.adj if net.deg(k) == 1 and not net.anchored(k)]
    moving, links, rots = set(), [], {}
    for w in ways:
        for f in ("rot", "tip", "back", "own_rot", "fixed", "orphan"):
            w.pop(f, None)
    owner = {}
    for w in ways:
        for k in (_key(w["pts"][0]), _key(w["pts"][-1])):
            if k in tips and k not in owner:
                owner[k] = w
    paths, used = {}, set()
    for tip in sorted(tips, key=lambda k: -net.dist[k]):  # the end farthest from the building is the cab
        if tip in used or min(net.dist[k] for k in net.component(tip)) > ORPHAN_M:
            continue
        path = net.walk_back(tip)
        if net.deg(path[-1]) == 1 and not net.anchored(path[-1]) and len(path) == 2 and path[-1] in tips:
            used.add(path[-1])  # a lone way: its other end is the rotunda, not a second cab
        used.update(path)
        paths[tip] = path
        for a, b in zip(path, path[1:]):
            moving.add(frozenset((a, b)))
    for tip, path in paths.items():
        rot = path[-1]
        d = _unit(rot, path[-2])  # rotunda -> cab
        rot_xy = rot
        if net.deg(rot) == 1 and net.dist[rot] < ROT_CLEAR:
            # at (or inside) the wall: move the column out along the bridge, ROT_CLEAR clear of the wall
            for s in [i * 0.5 for i in range(1, 80)]:
                q = (rot[0] + d[0] * s, rot[1] + d[1] * s)
                if net._sdist(q) >= ROT_CLEAR:
                    if math.dist(q, tip) >= MIN_TAIL * 0.75:
                        rot_xy = q
                    break
        back = (-d[0], -d[1])
        others = [n for n in net.adj[rot] if frozenset((rot, n)) not in moving]
        dr = net._sdist(rot_xy)
        if others:  # a fixed link leaves the rotunda: the stub lies along it, toward the building
            back = _unit(rot, min(others, key=lambda n: net.dist[n]))
        elif STUB_M - INSET_M < dr < ORPHAN_M:  # a free rotunda near a wall the stub does not reach: link it in
            q, back = net.to_wall(rot_xy)
            links.append({"a": [round(rot_xy[0], 2), round(rot_xy[1], 2)], "b": [round(q[0], 2), round(q[1], 2)]})
        w = owner[tip]
        w["rot"] = [round(rot_xy[0], 2), round(rot_xy[1], 2)]
        w["tip"] = [tip[0], tip[1]]
        w["back"] = [round(back[0], 4), round(back[1], 4)]
        w["own_rot"] = _key(rot_xy) not in rots
        rots[_key(rot_xy)] = True
    # every other edge of a drawn network is a fixed link; an end at the building runs into it
    drawn = set()
    for w in ways:
        if "tip" in w:
            drawn |= net.component(_key(w["tip"]))
    for a in net.adj:
        for b in net.adj[a]:
            if a < b and frozenset((a, b)) not in moving and a in drawn:
                ea, eb = a, b
                if net.deg(a) == 1 and net.anchored(a):
                    ea = net.into_building(a, _unit(b, a)) or a
                if net.deg(b) == 1 and net.anchored(b):
                    eb = net.into_building(b, _unit(a, b)) or b
                links.append({"a": [round(ea[0], 2), round(ea[1], 2)], "b": [round(eb[0], 2), round(eb[1], 2)]})
    for w in ways:
        if "tip" not in w:
            ks = {_key(p) for p in w["pts"]}
            if ks & drawn:
                w["fixed"] = True
            else:
                w["orphan"] = True
    return links


def footprints_near(ways, polys):
    """Union of the footprints within 200 m of any bridge node (shapely)."""
    if not ways or not polys:
        return None
    xs = [p[0] for w in ways for p in w["pts"]]
    ys = [p[1] for w in ways for p in w["pts"]]
    box = Polygon([(min(xs) - 200, min(ys) - 200), (max(xs) + 200, min(ys) - 200),
                   (max(xs) + 200, max(ys) + 200), (min(xs) - 200, max(ys) + 200)])
    near = [p for p in polys if p.intersects(box)]
    return unary_union(near) if near else None


def apply(ops, polys_of):
    """ops: airport_ops dict; polys_of(icao, ways) -> [shapely Polygon] footprints. Adds jetlinks."""
    for icao, a in ops.items():
        ways = a.get("jetbridges", [])
        a["jetlinks"] = solve(ways, footprints_near(ways, polys_of(icao, ways))) if ways else []
        if ways:
            n = sum("tip" in w for w in ways)
            print(f"{icao}: jet bridges {len(ways)} ways -> {n} movable, {len(a['jetlinks'])} fixed links, "
                  f"{sum(w.get('orphan', False) for w in ways)} orphan ways")


if __name__ == "__main__":
    import jetway_footprints as JF
    import common as c
    path = c.OUT / "airport_ops.json"
    ops = json.loads(path.read_text())
    apply(ops, JF.polys_of)
    path.write_text(json.dumps(ops))
    sys.exit(0)
