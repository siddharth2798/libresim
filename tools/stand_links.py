"""Lead-in links between stands and the taxi graph (tools/airport_stands.py).

The taxi graph is {"nodes": {id: [x, y]}, "edges": [[a, b, ref, width, kind], ...]}; AirportOps.route
A*-searches it over every edge except runways, from the node nearest to the start to the node nearest
to the goal. A stand therefore needs a node of its own at the stop point, joined to the graph.
"""
import math

from shapely.geometry import LineString, Point

import stand_geom as G


def _edges(taxi, kinds=None):
    n = taxi["nodes"]
    return [(e, n[e[0]], n[e[1]]) for e in taxi["edges"] if kinds is None or e[4] in kinds]


def add_link(taxi, node_id, p, h, obstacles, max_len=260.0):
    """Lead-in edge from stand node (at p) to the taxi graph: first the straight line behind the
    stand, else the nearest edge point. Returns the link length or None when nothing clear exists."""
    back = G.fwd((h + 180.0) % 360.0)
    ray = LineString([p, (p[0] + back[0] * max_len, p[1] + back[1] * max_len)])
    best = None
    for e, a, b in _edges(taxi, {"taxiway", "taxilane"}):
        seg = LineString([a, b])
        x = ray.intersection(seg)
        if x.is_empty or x.geom_type != "Point":
            continue
        t = math.dist(p, (x.x, x.y))
        ang = abs(G.angle_diff(G.bearing(b[0] - a[0], b[1] - a[1]) % 180.0, h % 180.0))
        if t >= 12.0 and 30.0 < ang < 150.0 and (best is None or t < best[0]):
            best = (t, e, (x.x, x.y))
    if best is None:   # nearest point on any non-runway edge
        for e, a, b in _edges(taxi, {"taxiway", "taxilane"}):
            seg = LineString([a, b])
            q = seg.interpolate(seg.project(Point(p)))
            t = math.dist(p, (q.x, q.y))
            if t <= max_len and (best is None or t < best[0]):
                best = (t, e, (q.x, q.y))
    if best is None:
        return None
    t, e, q = best
    if obstacles is not None and LineString([p, q]).buffer(2.0).intersects(obstacles):
        return None
    hit = _split_edge(taxi, e, q)
    taxi["nodes"][node_id] = [round(p[0], 1), round(p[1], 1)]
    taxi["edges"].append([hit, node_id, "", "", "parking_position"])
    return t


def _split_edge(taxi, e, q):
    """Graph node at point q of edge e: an end node when within 8 m, else a new node splitting e."""
    n = taxi["nodes"]
    for end in (0, 1):
        if math.dist(n[e[end]], q) < 8.0:
            return e[end]
    nid = f"L{len(n)}"
    n[nid] = [round(q[0], 1), round(q[1], 1)]
    i = taxi["edges"].index(e)
    taxi["edges"][i:i + 1] = [[e[0], nid, *e[2:]], [nid, e[1], *e[2:]]]
    return nid


def graph_ok(taxi, node_id, goals):
    """Can node_id reach, over the non-runway edges, the graph node nearest to one of the goal points?
    (the same nearest-node rule as AirportOps.route)."""
    adj = {}
    for e in taxi["edges"]:
        if e[4] != "runway":
            adj.setdefault(e[0], []).append(e[1])
            adj.setdefault(e[1], []).append(e[0])
    if node_id not in adj:
        return False
    seen, todo = {node_id}, [node_id]
    while todo:
        for nb in adj[todo.pop()]:
            if nb not in seen:
                seen.add(nb)
                todo.append(nb)
    return any(min(adj, key=lambda i: math.dist(taxi["nodes"][i], g)) in seen for g in goals)
