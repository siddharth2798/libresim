"""OSM airport ground infrastructure -> data/processed/airport_ops.json (phase A).

Per airport (nearest OurAirports airport within 6 km):
  stands:      [{ref, x, y, heading_deg, kind: "gate"|"remote", jetbridge: bool}]
               from aeroway=parking_position (ways give the stand line & heading; nodes are
               headed toward the nearest terminal), jetbridge = a jet_bridge way within 45 m
  gates:       [{ref, x, y}] aeroway=gate nodes (terminal-side gate numbers)
  jetbridges:  [{pts: [[x, y], ...]}] aeroway=jet_bridge ways
  holds:       [{x, y}] aeroway=holding_position nodes
  windsocks, towers: [{x, y}]
  taxi:        {nodes: {id: [x, y]}, edges: [[id_a, id_b, ref, width_m, kind]]}
               graph from aeroway=taxiway/taxilane/runway ways (shared OSM nodes = junctions)
World metres (x east, y north). Run after 05_airports_navaids.py.
"""
import json
import math
from collections import defaultdict

import osmium

import common as c

KEYS = ("aeroway",)
LINK_KINDS = {"taxiway", "taxilane", "runway", "parking_position"}


def synth_ga_stands(out, nearest_airport, heading):
    """Airports without mapped stands (e.g. Juhu): GA tie-down spots on the aprons,
    spaced 18 m, nose toward the nearest taxiway node."""
    from matplotlib.path import Path
    aero = json.loads((c.OUT / "osm" / "aeroways.json").read_text())
    for ap in aero["areas"]:
        if ap["kind"] != "apron":
            continue
        pts = ap["pts"]
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        apt = nearest_airport(cx, cy)
        if apt is None or out[apt]["stands"] and not out[apt].get("synthetic"):
            continue
        out[apt]["synthetic"] = True
        nodes = list(out[apt]["taxi"]["nodes"].values())
        path = Path(pts)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        k = len(out[apt]["stands"])
        y = min(ys) + 12
        while y < max(ys) - 12:
            x = min(xs) + 12
            while x < max(xs) - 12:
                if path.contains_point((x, y)) and len(out[apt]["stands"]) < k + 30:
                    hd = 0.0
                    if nodes:
                        nx, ny = min(nodes, key=lambda n: math.hypot(n[0] - x, n[1] - y))
                        hd = heading(nx - x, ny - y)
                    out[apt]["stands"].append({"ref": f"GA{len(out[apt]['stands']) + 1}", "x": round(x, 1),
                                               "y": round(y, 1), "heading_deg": round(hd, 1),
                                               "kind": "remote", "jetbridge": False})
                x += 18
            y += 18


def main():
    fwd = c.transformer()
    lon0, lat0, lon1, lat1 = c.BBOX
    airports = json.loads((c.OUT / "airports.json").read_text())

    def inside(loc):
        return lon0 <= loc.lon <= lon1 and lat0 <= loc.lat <= lat1

    nodes_pt, ways, terminals = [], [], []
    fp = osmium.FileProcessor(str(c.RAW / "osm" / "western-zone-latest.osm.pbf")).with_locations() \
        .with_filter(osmium.filter.KeyFilter(*KEYS))
    for o in fp:
        aw = o.tags.get("aeroway")
        if o.is_node():
            if inside(o.location):
                x, y = fwd(o.location.lon, o.location.lat)
                nodes_pt.append({"kind": aw, "ref": o.tags.get("ref", o.tags.get("name", "")), "x": x, "y": y})
        elif o.is_way():
            ns = o.nodes
            if len(ns) < 2 or not ns[0].location.valid() or not inside(ns[0].location):
                continue
            pts = [(n.ref, *fwd(n.location.lon, n.location.lat)) for n in ns if n.location.valid()]
            rec = {"kind": aw, "ref": o.tags.get("ref", ""), "width": o.tags.get("width", ""), "pts": pts}
            if aw == "terminal":
                terminals.append(rec)
            else:
                ways.append(rec)

    def nearest_airport(x, y):
        a = min(airports, key=lambda a: math.hypot(a["x"] - x, a["y"] - y))
        return (a["icao"] or a["ident"]) if math.hypot(a["x"] - x, a["y"] - y) < 6000 else None

    out = defaultdict(lambda: {"stands": [], "gates": [], "jetbridges": [], "holds": [], "windsocks": [],
                               "towers": [], "taxi": {"nodes": {}, "edges": []}})
    term_c = [(sum(p[1] for p in t["pts"]) / len(t["pts"]), sum(p[2] for p in t["pts"]) / len(t["pts"])) for t in terminals]
    bridges = [w for w in ways if w["kind"] == "jet_bridge"]

    def has_bridge(x, y):
        for b in bridges:
            for _, bx, by in b["pts"]:
                if math.hypot(bx - x, by - y) < 45.0:
                    return True
        return False

    def heading(dx, dy):
        return math.degrees(math.atan2(dx, dy)) % 360.0

    for w in ways:
        x0, y0 = w["pts"][0][1], w["pts"][0][2]
        apt = nearest_airport(x0, y0)
        if apt is None:
            continue
        A = out[apt]
        if w["kind"] == "jet_bridge":
            A["jetbridges"].append({"pts": [[round(p[1], 1), round(p[2], 1)] for p in w["pts"]]})
        elif w["kind"] == "parking_position":
            # stand line: aircraft stops at the end, nose pointing along the last segment
            (_, ax, ay), (_, bx, by) = w["pts"][-2], w["pts"][-1]
            jb = has_bridge(bx, by)
            A["stands"].append({"ref": w["ref"], "x": round(bx, 1), "y": round(by, 1),
                                "heading_deg": round(heading(bx - ax, by - ay), 1),
                                "kind": "gate" if jb else "remote", "jetbridge": jb})
        if w["kind"] in LINK_KINDS:
            G = A["taxi"]
            for nid, x, y in w["pts"]:
                G["nodes"][str(nid)] = [round(x, 1), round(y, 1)]
            for (na, *_), (nb, *_) in zip(w["pts"], w["pts"][1:]):
                G["edges"].append([str(na), str(nb), w["ref"], w["width"], w["kind"]])
    for p in nodes_pt:
        apt = nearest_airport(p["x"], p["y"])
        if apt is None:
            continue
        A = out[apt]
        xy = {"x": round(p["x"], 1), "y": round(p["y"], 1)}
        if p["kind"] == "parking_position":
            # node stands: nose toward the nearest terminal (nose-in), else north
            hd = 0.0
            if term_c:
                tx, ty = min(term_c, key=lambda t: math.hypot(t[0] - p["x"], t[1] - p["y"]))
                hd = heading(tx - p["x"], ty - p["y"])
            jb = has_bridge(p["x"], p["y"])
            A["stands"].append({"ref": p["ref"], **xy, "heading_deg": round(hd, 1),
                                "kind": "gate" if jb else "remote", "jetbridge": jb})
        elif p["kind"] == "gate":
            A["gates"].append({"ref": p["ref"], **xy})
        elif p["kind"] == "holding_position":
            A["holds"].append(xy)
        elif p["kind"] == "windsock":
            A["windsocks"].append(xy)
        elif p["kind"] == "tower":
            A["towers"].append(xy)
    for w in ways:
        if w["kind"] == "tower":
            apt = nearest_airport(w["pts"][0][1], w["pts"][0][2])
            if apt:
                xs = [p[1] for p in w["pts"]]
                ys = [p[2] for p in w["pts"]]
                out[apt]["towers"].append({"x": round(sum(xs) / len(xs), 1), "y": round(sum(ys) / len(ys), 1)})
    synth_ga_stands(out, nearest_airport, heading)
    (c.OUT / "airport_ops.json").write_text(json.dumps(out))
    for apt, A in sorted(out.items(), key=lambda kv: -len(kv[1]["stands"])):
        print(f"{apt}: stands {len(A['stands'])} ({sum(s['jetbridge'] for s in A['stands'])} with jetbridge), "
              f"gates {len(A['gates'])}, holds {len(A['holds'])}, taxi nodes {len(A['taxi']['nodes'])}, "
              f"edges {len(A['taxi']['edges'])}, windsocks {len(A['windsocks'])}, towers {len(A['towers'])}")


if __name__ == "__main__":
    main()
