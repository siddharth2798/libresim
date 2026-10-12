"""Airliner stands for airports whose OSM terminal has jet bridges that no aeroway=parking_position
serves (Kochi, Kannur), derived from what is mapped. Used by 13_airport_ops.py.

  1. gates: one stand per jet-bridge cluster (bridges sharing a node, or with rotundas and cabs close
     together, are the two doors of one gate). The cab tip is the L1 door: nose-gear point = cab tip +
     DOOR_STANDOFF toward the aircraft. Heading: the cab-to-cab line of a two-door gate, else the main
     tunnel (square to the terminal), else square to the cab tunnel; the cab is on the aircraft's left.
     An A320-class outline must clear terminals, hangars and the other gates' bridges, else the
     heading turns in 5 degree steps (stand_geom.py has the outline, stand_remote.py the site).
  2. walk-out gates: a gate node with no bridge and no stand beside it takes its neighbour's pose.
  3. remote bays (stand_remote.py): nose-in rows beside the apron's long taxi lanes.
  4. every stand gets a lead-in edge (kind parking_position, stand_links.py) into the taxi graph and
     must reach a runway end over the non-runway edges, else it is dropped.
Stands carry "src": "osm" (all existing ones, untouched) | "bridge" | "gate" | "remote".
"""
import math

from shapely.geometry import Point
from shapely.ops import unary_union

import stand_geom as G
import stand_links as L
import stand_remote as R

BRIDGE_SERVED_M = 60.0   # an OSM stand this close to a bridge already serves it (13 flags 45 m)
SHARE_ROTUNDA_M = 22.0   # bridges with rotundas this close (and cabs within TWO_DOOR_M) serve one gate
TWO_DOOR_M = 30.0        # L1 to L2 of an A321
TWO_CAB_MIN_M = 9.0      # cabs this far apart are two doors of one aircraft
TURN_STEPS = [0, 5, -5, 10, -10, 15, -15, 20, -20, 25, -25, 30, -30, 40, -40]


def _unit(dx, dy):
    n = math.hypot(dx, dy)
    return (dx / n, dy / n) if n > 1e-6 else (0.0, 0.0)


class Bridge:
    """A jet bridge way oriented rotunda (terminal end) -> cab tip."""

    def __init__(self, pts, rotunda_end):
        pts = list(pts) if rotunda_end == 0 else list(reversed(pts))
        self.ids = {p[0] for p in pts}
        self.xy = [(p[1], p[2]) for p in pts]
        self.rotunda = self.xy[0]
        self.cab = self.xy[-1]
        k = len(self.xy) - 2   # tunnel direction: the last stretch at least 6 m long
        while k > 0 and math.dist(self.xy[k], self.cab) < 6.0:
            k -= 1
        self.d = _unit(self.cab[0] - self.xy[k][0], self.cab[1] - self.xy[k][1])


def orient_bridges(ways, terminals, gates):
    """Bridges from jet_bridge ways; the rotunda is the end next to a terminal (else a gate node)."""
    tu = unary_union(terminals) if terminals else None
    out = []
    for w in ways:
        pts = w["pts"]
        if len(pts) < 2:
            continue
        ends = [Point(pts[0][1], pts[0][2]), Point(pts[-1][1], pts[-1][2])]
        score = []
        for e in ends:
            d = tu.distance(e) if tu is not None else 1e9
            g = min((math.dist((e.x, e.y), (q["x"], q["y"])) for q in gates), default=1e9)
            score.append(min(d, g * 2.0))
        out.append(Bridge(pts, 0 if score[0] <= score[1] else 1))
    return out


def cluster_bridges(bridges):
    """Union-find: bridges sharing an OSM node, or with close rotundas and cabs (two doors of one aircraft)."""
    parent = list(range(len(bridges)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i, a in enumerate(bridges):
        for j in range(i + 1, len(bridges)):
            b = bridges[j]
            if a.ids & b.ids or (math.dist(a.rotunda, b.rotunda) < SHARE_ROTUNDA_M and math.dist(a.cab, b.cab) < TWO_DOOR_M):
                parent[find(j)] = find(i)
    groups = {}
    for i, b in enumerate(bridges):
        groups.setdefault(find(i), []).append(b)
    return sorted(groups.values(), key=lambda g: (g[0].rotunda[0], g[0].rotunda[1]))


def _normal(group):
    """Terminal normal from a bridge's main tunnel: the first stretch (rotunda to the first bend,
    12 m or more) when the cab end turns away from it; None for straight 2-point bridges."""
    for b in group:
        if len(b.xy) >= 3 and math.dist(b.xy[0], b.xy[1]) >= 12.0:
            h = G.bearing(b.rotunda[0] - b.xy[1][0], b.rotunda[1] - b.xy[1][1])
            if abs(G.angle_diff(h, G.bearing(-b.d[0], -b.d[1]))) > 20.0:
                return h
    return None


def _axis(group):
    """Fuselage heading. The cab docks on the aircraft's left (port) side, so the aircraft lies on the
    far side of the cab tunnel and the tunnel's direction d (rotunda -> cab) points to the right of
    the heading. Two far-apart cabs (two doors) give the axis directly; otherwise the main tunnel's
    direction (the aircraft stands square to the terminal); otherwise square to the cab tunnel."""
    cabs = [b.cab for b in group]
    far = max(((a, b) for a in cabs for b in cabs), key=lambda ab: math.dist(*ab))
    two = math.dist(*far) >= TWO_CAB_MIN_M
    d = _unit(sum(b.d[0] for b in group), sum(b.d[1] for b in group))
    u = _unit(far[1][0] - far[0][0], far[1][1] - far[0][1]) if two else (-d[1], d[0])
    if u[1] * d[0] - u[0] * d[1] < 0:     # d must point to the right of u
        u = (-u[0], -u[1])
    h = G.bearing(*u)
    n = _normal(group)
    if n is not None and (not two or abs(G.angle_diff(h, n)) > 50.0):
        return n
    return h


def _nose_gear(group, h):
    """L1 door = the cab tip nearest the nose; the centre line is DOOR_STANDOFF to its right."""
    f = G.fwd(h)
    cab = max((b.cab for b in group), key=lambda c: c[0] * f[0] + c[1] * f[1])
    return G.place(cab, h, 0.0, G.DOOR_STANDOFF)


def gate_poses(groups, obstacles):
    """[(group, p, heading)]: heading turned (5 deg steps) until the aircraft clears the obstacles
    and the other gates' bridges. Gates that cannot be placed cleanly keep their first pose."""
    poses = []
    own = [unary_union([G.line(b.xy) for b in g]) for g in groups]
    for k, g in enumerate(groups):
        body = unary_union([G.line(b.xy).difference(Point(b.cab).buffer(4.5)) for b in g])
        others = unary_union([own[j] for j in range(len(groups)) if j != k]) if len(groups) > 1 else None
        h0 = _axis(g)
        pick = None
        for turn in TURN_STEPS:
            h = (h0 + turn) % 360.0
            p = _nose_gear(g, h)
            ac = G.aircraft(p, h)
            hit = obstacles is not None and ac.buffer(2.0).intersects(obstacles)
            hit = hit or (others is not None and ac.buffer(1.0).intersects(others)) or ac.intersects(body)
            if not hit:
                pick = (g, p, h, turn)
                break
        poses.append(pick or (g, _nose_gear(g, h0), h0, None))
    return poses


def served(group, real_stands):
    """Does an OSM stand already stand at this gate's bridges?"""
    pts = [q for b in group for q in b.xy]
    return any(math.dist(q, (s["x"], s["y"])) < BRIDGE_SERVED_M for s in real_stands for q in pts)


def _ref(group, gates, used, counter):
    """Gate number from a gate node at the bridge's rotunda, else B<n> (n counts the unnamed gates)."""
    r = group[0].rotunda
    near = [g for g in gates if g["ref"] and math.dist(r, (g["x"], g["y"])) < 12.0]
    if near:
        ref = str(near[0]["ref"])
    else:
        counter[0] += 1
        ref = f"B{counter[0]}"
    while ref in used:
        ref += "x"
    used.add(ref)
    return ref


def gate_stands(icao, A, ws, site_obstacles, terminals, log):
    """New gate stand records for the bridges nothing serves yet. Each carries a temporary "_outline"
    (aircraft polygon) and "_rotunda" that add_stands removes."""
    bridges = orient_bridges([w for w in ws if w["kind"] == "jet_bridge"], terminals, A["gates"])
    groups = [g for g in cluster_bridges(bridges) if not served(g, A["stands"])]
    if not groups:
        return []
    real_ac = [G.aircraft((s["x"], s["y"]), s["heading_deg"]) for s in A["stands"]]
    obst = unary_union(([site_obstacles] if site_obstacles is not None else []) + real_ac)
    used = {str(s["ref"]) for s in A["stands"]}
    out, counter = [], [0]
    for g, p, h, turn in gate_poses(groups, obst):
        if turn is None:
            log(f"  {icao}: gate at ({p[0]:.0f}, {p[1]:.0f}) overlaps a building at every heading; kept at {h:.0f}")
        out.append({"ref": _ref(g, A["gates"], used, counter), "x": round(p[0], 1), "y": round(p[1], 1),
                    "heading_deg": round(h, 1), "kind": "gate", "jetbridge": True, "src": "bridge"})
        out[-1]["_outline"] = G.aircraft(p, h)
        out[-1]["_rotunda"] = g[0].rotunda
    return out


def walkout_stands(A, new, obstacles):
    """A gate node with no bridge and no stand beside it (Kochi gate 1) gets the pose of the nearest
    bridge gate, shifted to the node, when the outline then stays clear of buildings and the others."""
    out = []
    if not new:
        return out
    taken = [s["_outline"] for s in new]
    for g in A["gates"]:
        pt = (g["x"], g["y"])
        if any(math.dist(pt, (s["x"], s["y"])) < 60.0 for s in A["stands"] + new + out):
            continue
        sib = min(new, key=lambda s: math.dist(pt, s["_rotunda"]))
        if math.dist(pt, sib["_rotunda"]) > 100.0:
            continue
        dx, dy = sib["x"] - sib["_rotunda"][0], sib["y"] - sib["_rotunda"][1]
        p = (pt[0] + dx, pt[1] + dy)
        ac = G.aircraft(p, sib["heading_deg"])
        if (obstacles is not None and ac.buffer(2.0).intersects(obstacles)) or any(ac.buffer(2.0).intersects(t) for t in taken):
            continue
        used = {str(s["ref"]) for s in A["stands"] + new + out}
        ref = str(g["ref"]) if g["ref"] and str(g["ref"]) not in used else f"W{len(out) + 1}"
        out.append({"ref": ref, "x": round(p[0], 1), "y": round(p[1], 1), "heading_deg": sib["heading_deg"],
                    "kind": "remote", "jetbridge": False, "src": "gate", "_outline": ac, "_rotunda": pt})
        taken.append(ac)
    return out


def add_stands(out, ways, aprons_of, nearest_airport, ends_of, log=print):
    """Derive gate stands, walk-out gates and remote bays where bridges are not served by an OSM stand;
    link them into the taxi graph. Returns {icao: Site} (used afterwards to place GA tie-downs).
    ways: OSM aeroway ways incl. terminals; aprons_of(icao) -> [shapely Polygon];
    ends_of(icao) -> [(x, y)] runway ends (a stand must reach one over the non-runway taxi graph)."""
    by = {}
    for w in ways:
        apt = nearest_airport(w["pts"][0][1], w["pts"][0][2])
        if apt in out:
            by.setdefault(apt, []).append(w)
    sites = {}
    for icao, A in out.items():
        for s in A["stands"]:
            s["src"] = "osm"
        ws = by.get(icao, [])
        sites[icao], terms, buildings = R.build_site(A, ws, aprons_of(icao))
        if any(w["kind"] == "jet_bridge" for w in ws):
            kept = _airport(icao, A, ws, sites[icao], terms, buildings, ends_of(icao), log)
            A["stands"][:0] = kept
    return sites


def _airport(icao, A, ws, site, terms, buildings, goals, log):
    """The new stands of one airport: gates, walk-out gates, remote bays (all linked to the graph)."""
    new = gate_stands(icao, A, ws, buildings, terms, log)
    new += walkout_stands(A, new, buildings)
    kept = []
    for s in new:
        others = [o["_outline"] for o in new if o is not s]
        avoid = unary_union(([buildings] if buildings is not None else []) + others)
        _connect(A, icao, s, avoid, kept, goals, log, site)
    if kept:
        anchor = (sum(s["x"] for s in kept) / len(kept), sum(s["y"] for s in kept) / len(kept))
        used = {str(s["ref"]) for s in A["stands"] + kept}
        for p, h in R.remote_bays(site, anchor, R.MAX_REMOTE):
            k = 1
            while f"R{k}" in used:
                k += 1
            used.add(f"R{k}")
            rec = {"ref": f"R{k}", "x": round(p[0], 1), "y": round(p[1], 1), "heading_deg": round(h, 1),
                   "kind": "remote", "jetbridge": False, "src": "remote"}
            _connect(A, icao, rec, buildings, kept, goals, log)
    for s in kept:
        s.pop("_outline", None)
        s.pop("_rotunda", None)
    n = {k: sum(s["src"] == k for s in kept) for k in ("bridge", "gate", "remote")}
    log(f"  {icao}: {n['bridge']} bridge gates, {n['gate']} walk-out gates, {n['remote']} remote bays")
    return kept


def _connect(A, icao, s, avoid, kept, goals, log, site=None):
    """Join stand s to the taxi graph; keep it (append to kept) only when a clear lead-in exists and
    the graph reaches a runway end. With a site, its bay and lead-in strip are reserved there."""
    node = f"S{icao}{len(A['taxi']['nodes'])}"
    nodes, edges = dict(A["taxi"]["nodes"]), list(A["taxi"]["edges"])
    if L.add_link(A["taxi"], node, (s["x"], s["y"]), s["heading_deg"], avoid) is None:
        log(f"  {icao}: stand {s['ref']} has no lead-in route; dropped")
        return False
    if goals and not L.graph_ok(A["taxi"], node, goals):
        A["taxi"]["nodes"], A["taxi"]["edges"] = nodes, edges   # undo the link
        log(f"  {icao}: stand {s['ref']} is not connected to the runway; dropped")
        return False
    kept.append(s)
    if site is not None:
        a, b = A["taxi"]["edges"][-1][:2]
        site.add(G.bay((s["x"], s["y"]), s["heading_deg"]))
        site.add(G.line([A["taxi"]["nodes"][a], A["taxi"]["nodes"][b]]).buffer(R.TAXI_CLEAR_M))
    return True
