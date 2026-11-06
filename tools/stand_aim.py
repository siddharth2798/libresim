"""Aim an OSM jetbridge stand at the bridge that can meet its left door.

The game docks only when a cab is within JetwayDocks.REACH_M of the door and JetwayPose
accepts the tunnel (length and cab twist). Two OSM habits miss that, so the jetway stays
at rest:

- a parking_position line drawn out to the taxiway and shorter than the 60 m reversal in
  13_airport_ops.py, so the stored point is the lead-in end (Calicut)
- a parking node headed at the terminal centroid, so the door looks along the pier and the
  bridge sits ahead of the nose or on the right (Mumbai, Goa)

Called after jetway_net has marked each bridge's cab. A stand that already docks is left
alone. Otherwise the stand slides to the end of its parking line the bridge can serve, or
its heading turns so the left door faces the nearest cab. A pose that puts the aircraft
outline inside a building is refused. Derived stands stay as airport_stands placed them.

`python tools/stand_aim.py` rewrites data/processed/airport_ops.json in place.
"""
import json
import math

from shapely.ops import unary_union

import jetway_footprints as JF
import stand_geom as G

REACH = 26.0          # JetwayDocks.REACH_M
CAB = 17.01 - 14.33   # JetwayPose hood face to the cab drum
MIN_LEN, MAX_LEN, MAX_TWIST = 8.0, 70.0, 85.0
DOOR_OFF = -1.95 - 0.15  # A320 door_y_m, then DOOR_GAP_M outside the skin
SLIDE_M = 80.0        # a lead-in end, not a hop onto the next gate's line
CLEAR_M = 12.0        # another stand already owns this stop


def _ways(A):
    """[(rotunda, cab)] of the movable bridges."""
    out = []
    for jb in A.get("jetbridges", []):
        if "tip" in jb and not jb.get("fixed") and not jb.get("orphan"):
            out.append((tuple(jb["rot"]), tuple(jb["tip"])))
    return out


def _docks(x, y, hd, ways):
    """True when some bridge within REACH can put its hood on the left door."""
    r = G.right(hd)
    tip = (x + r[0] * DOOR_OFF, y + r[1] * DOOR_OFF)
    for d, rot in sorted((math.dist(cab, tip), rot) for rot, cab in ways):
        if d >= REACH:
            break
        drum = (tip[0] - r[0] * CAB, tip[1] - r[1] * CAB)
        dx, dy = drum[0] - rot[0], drum[1] - rot[1]
        ln = math.hypot(dx, dy)
        if not MIN_LEN <= ln <= MAX_LEN:
            continue
        yaw = math.degrees(math.atan2(dy, dx))
        face = math.degrees(math.atan2(r[1], r[0]))
        if abs(G.angle_diff(face, yaw)) <= MAX_TWIST:
            return True
    return False


def _face(x, y, cab):
    """Heading whose left side points at the cab."""
    vx, vy = cab[0] - x, cab[1] - y
    n = math.hypot(vx, vy) or 1.0
    return G.bearing(vy / n, -vx / n)


def _turns(h0):
    yield h0
    for step in range(5, 180, 5):
        yield (h0 + step) % 360.0
        yield (h0 - step) % 360.0


def _clear(buildings, x, y, hd):
    if buildings is None or buildings.is_empty:
        return True
    return not G.aircraft((x, y), hd).intersects(buildings)


def _graph(A):
    nodes = {k: tuple(v) for k, v in A["taxi"]["nodes"].items()}
    adj = {}
    for e in A["taxi"]["edges"]:
        if len(e) > 4 and e[4] == "parking_position":
            adj.setdefault(e[0], set()).add(e[1])
            adj.setdefault(e[1], set()).add(e[0])
    return nodes, adj


def _node_at(nodes, x, y):
    best, bd = None, 2.0
    for k, p in nodes.items():
        d = math.hypot(p[0] - x, p[1] - y)
        if d < bd:
            best, bd = k, d
    return best


def _leaves(adj, start):
    seen, todo = {start}, [start]
    while todo:
        i = todo.pop()
        for j in adj.get(i, ()):
            if j not in seen:
                seen.add(j)
                todo.append(j)
    return [k for k in seen if k != start and len(adj.get(k, ())) <= 1]


def _free(pts, i, x, y):
    return all(j == i or math.dist(pts[j], (x, y)) > CLEAR_M for j in range(len(pts)))


def _slide(st, i, pts, nodes, adj, ways, buildings):
    """Move to a parking-line end the bridge can serve. The painted line sets the heading."""
    start = _node_at(nodes, st["x"], st["y"])
    if start is None or start not in adj:
        return False
    best = None
    for leaf in _leaves(adj, start):
        p = nodes[leaf]
        if not SLIDE_M >= math.dist(p, (st["x"], st["y"])) > 15.0 or not _free(pts, i, *p):
            continue
        nb = next(iter(adj[leaf]))
        hd = G.bearing(p[0] - nodes[nb][0], p[1] - nodes[nb][1])
        if _docks(*p, hd, ways) and _clear(buildings, *p, hd) and (best is None or math.dist(p, (st["x"], st["y"])) < best[0]):
            best = (math.dist(p, (st["x"], st["y"])), p, hd)
    if best is None:
        return False
    _, p, hd = best
    st["x"], st["y"], st["heading_deg"] = round(p[0], 1), round(p[1], 1), round(hd, 1)
    pts[i] = (st["x"], st["y"])
    return True


def _component(adj, start):
    seen, todo = {start}, [start]
    while todo:
        i = todo.pop()
        for j in adj.get(i, ()):
            if j not in seen:
                seen.add(j)
                todo.append(j)
    return seen


def _drop_duplicates(A, ways, nodes, adj):
    """Lead-in copies of a gate that now docks, and a second stand on the same point."""
    served = set()
    for s in A["stands"]:
        n = _node_at(nodes, s["x"], s["y"]) if s.get("jetbridge") else None
        if n and _docks(s["x"], s["y"], s["heading_deg"], ways):
            served |= _component(adj, n)
    kept, seen = [], []
    dropped = 0
    for s in A["stands"]:
        n = _node_at(nodes, s["x"], s["y"])
        twin = s.get("jetbridge") and s.get("src") == "osm" and not _docks(s["x"], s["y"], s["heading_deg"], ways)
        copy = twin and n in served
        same = twin and any(r == s.get("ref") and math.dist((x, y), (s["x"], s["y"])) < 2.0 for r, x, y in seen)
        if copy or same:
            dropped += 1
            continue
        kept.append(s)
        if s.get("jetbridge"):
            seen.append((s.get("ref"), s["x"], s["y"]))
    A["stands"] = kept
    return dropped


def _turn(st, ways, buildings):
    cab = min((c for _, c in ways), key=lambda c: math.dist(c, (st["x"], st["y"])))
    for h in _turns(_face(st["x"], st["y"], cab)):
        if _docks(st["x"], st["y"], h, ways) and _clear(buildings, st["x"], st["y"], h):
            st["heading_deg"] = round(h % 360.0, 1)
            return True
    return False


def aim(ops, log=print):
    """Rewrite OSM jetbridge stands in `ops` that the bridges cannot dock to. Returns nothing."""
    for icao, A in ops.items():
        ways = _ways(A)
        if not ways:
            continue
        rings = JF.polys_of(icao, A.get("jetbridges", []))
        buildings = unary_union(rings) if rings else None
        nodes, adj = _graph(A)
        pts = [(s["x"], s["y"]) for s in A["stands"]]
        gates = [s for s in A["stands"] if s.get("jetbridge")]
        before = sum(_docks(s["x"], s["y"], s["heading_deg"], ways) for s in gates)
        moved = turned = 0
        for i, s in enumerate(A["stands"]):
            if not s.get("jetbridge") or s.get("src") != "osm":
                continue
            if _docks(s["x"], s["y"], s["heading_deg"], ways):
                continue
            if _slide(s, i, pts, nodes, adj, ways, buildings):
                moved += 1
            elif _turn(s, ways, buildings):
                turned += 1
        dropped = _drop_duplicates(A, ways, nodes, adj)
        gates = [s for s in A["stands"] if s.get("jetbridge")]
        after = sum(_docks(s["x"], s["y"], s["heading_deg"], ways) for s in gates)
        if moved or turned or dropped:
            log(f"  {icao}: aimed {moved + turned} stands ({moved} moved along the lead-in, {turned} turned), "
                f"dropped {dropped} duplicate lead-ins; {after} of {len(gates)} jetbridge gates dock (was {before})")


if __name__ == "__main__":
    import common as c
    path = c.OUT / "airport_ops.json"
    ops = json.loads(path.read_text())
    aim(ops)
    path.write_text(json.dumps(ops))
