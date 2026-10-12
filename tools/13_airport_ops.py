"""OSM airport ground infrastructure -> data/processed/airport_ops.json (phase A).

Per airport (nearest OurAirports airport within 6 km):
  stands:      [{ref, x, y, heading_deg, kind: "gate"|"remote", jetbridge: bool, src}]
               src "osm": aeroway=parking_position (ways give the stand line & heading, the stop
               point is the end that does not touch a taxiway; nodes are headed toward the nearest
               terminal), jetbridge = a jet_bridge way within 45 m.
               src "bridge" | "gate" | "remote": airliner stands derived at terminals whose jet bridges
               no OSM stand serves (airport_stands.py): gate = cab tip of each bridge, walk-out gate,
               remote bays along the apron lanes; each is linked into the taxi graph.
               src "synth": GA tie-downs on aprons where OSM maps no stands (clear of taxiways)
  gates:       [{ref, x, y}] aeroway=gate nodes (terminal-side gate numbers)
  jetbridges:  [{pts: [[x, y], ...]}] aeroway=jet_bridge ways
  holds:       [{x, y}] aeroway=holding_position nodes
  windsocks, towers: [{x, y}]
  taxi:        {nodes: {id: [x, y]}, edges: [[id_a, id_b, ref, width_m, kind]]}
               graph from aeroway=taxiway/taxilane/runway ways (shared OSM nodes = junctions); kind
               "parking_position" edges are stand lines and the lead-ins added for derived stands
World metres (x east, y north). Both regions (Mumbai-Pune BBOX + Konkan-Kerala corridor),
both Geofabrik extracts, de-duplicated by OSM id. Run after 04 and 05 (aprons come from osm/aeroways.json).
"""
import json
import math
from collections import defaultdict

import osmium
from shapely.geometry import Polygon

import airport_stands as ST
import common as c
import osm_regions as R

KEYS = ("aeroway",)
LINK_KINDS = {"taxiway", "taxilane", "runway", "parking_position"}
GA_PER_APRON = 30


def heading(dx, dy):
    return math.degrees(math.atan2(dx, dy)) % 360.0


def synth_ga_stands(out, sites, aprons, nearest_airport, had_osm):
    """Airports where OSM maps no stands (e.g. Juhu): GA tie-down spots on the aprons, spaced 18 m,
    nose toward the nearest taxiway node, only where they clear taxiways, runways, buildings and
    the airliner stands (Site.ga_ok)."""
    from matplotlib.path import Path
    for ap in aprons:
        pts = ap["pts"]
        apt = nearest_airport(sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        if apt is None or apt not in out or had_osm.get(apt):
            continue
        A, site = out[apt], sites[apt]
        nodes = list(A["taxi"]["nodes"].values())
        path = Path(pts)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        n = 0
        y = min(ys) + 12
        while y < max(ys) - 12 and n < GA_PER_APRON:
            x = min(xs) + 12
            while x < max(xs) - 12 and n < GA_PER_APRON:
                if path.contains_point((x, y)) and site.ga_ok(x, y):
                    hd = 0.0
                    if nodes:
                        nx, ny = min(nodes, key=lambda q: math.hypot(q[0] - x, q[1] - y))
                        hd = heading(nx - x, ny - y)
                    A["stands"].append({"ref": f"GA{len(A['stands']) + 1}", "x": round(x, 1), "y": round(y, 1),
                                        "heading_deg": round(hd, 1), "kind": "remote", "jetbridge": False,
                                        "src": "synth"})
                    n += 1
                x += 18
            y += 18


def collect():
    """OSM objects of both regions: aeroway nodes, other aeroway ways, terminal ways."""
    fwd = c.transformer()

    def proc(path):
        return osmium.FileProcessor(str(path)).with_locations().with_filter(osmium.filter.KeyFilter(*KEYS))

    nodes_pt, ways, terminals = [], [], []
    for o in R.iter_osm(proc, R.region_filter()):
        aw = o.tags.get("aeroway")
        if o.is_node():
            x, y = fwd(o.location.lon, o.location.lat)
            nodes_pt.append({"kind": aw, "ref": o.tags.get("ref", o.tags.get("name", "")), "x": x, "y": y})
        elif o.is_way():
            pts = [(n.ref, *fwd(n.location.lon, n.location.lat)) for n in o.nodes if n.location.valid()]
            rec = {"kind": aw, "ref": o.tags.get("ref", ""), "width": o.tags.get("width", ""), "pts": pts}
            (terminals if aw == "terminal" else ways).append(rec)
    return nodes_pt, ways, terminals


def build_ops(airports, nodes_pt, ways, terminals):
    """Per-airport ops dict from the OSM objects (OSM data only: derived stands are added after)."""
    def nearest_airport(x, y):
        a = min(airports, key=lambda a: math.hypot(a["x"] - x, a["y"] - y))
        return (a["icao"] or a["ident"]) if math.hypot(a["x"] - x, a["y"] - y) < 6000 else None

    out = defaultdict(lambda: {"stands": [], "gates": [], "jetbridges": [], "holds": [], "windsocks": [],
                               "towers": [], "taxi": {"nodes": {}, "edges": []}})
    term_c = [(sum(p[1] for p in t["pts"]) / len(t["pts"]), sum(p[2] for p in t["pts"]) / len(t["pts"])) for t in terminals]
    bridges = [w for w in ways if w["kind"] == "jet_bridge"]
    on_taxiway = {p[0] for w in ways if w["kind"] in ("taxiway", "taxilane") for p in w["pts"]}

    def has_bridge(x, y):
        for b in bridges:
            for _, bx, by in b["pts"]:
                if math.hypot(bx - x, by - y) < 45.0:
                    return True
        return False

    for w in ways:
        x0, y0 = w["pts"][0][1], w["pts"][0][2]
        apt = nearest_airport(x0, y0)
        if apt is None:
            continue
        A = out[apt]
        if w["kind"] == "jet_bridge":
            A["jetbridges"].append({"pts": [[round(p[1], 1), round(p[2], 1)] for p in w["pts"]]})
        elif w["kind"] == "parking_position":
            # stand line: the aircraft stops at one end, nose pointing along the last segment. OSM says
            # the last node, but some airports (Pune, Goa, Mangaluru) draw it from the stop point out to
            # the taxiway: then the end that touches a taxiway is the lead-in, so reverse a long line.
            pts = w["pts"]
            length = sum(math.hypot(a[1] - b[1], a[2] - b[2]) for a, b in zip(pts, pts[1:]))
            if pts[-1][0] in on_taxiway and pts[0][0] not in on_taxiway and length >= 60.0:
                pts = pts[::-1]   # 60 m+: shorter ones (Pune) are lead-in stubs, not stand lines
            (_, ax, ay), (_, bx, by) = pts[-2], pts[-1]
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
    return out, nearest_airport


def main():
    airports = json.loads((c.OUT / "airports.json").read_text())
    nodes_pt, ways, terminals = collect()
    out, nearest_airport = build_ops(airports, nodes_pt, ways, terminals)
    finish(out, airports, ways + terminals, nearest_airport)


def finish(out, airports, osm_ways, nearest_airport):
    """Derived airliner stands, GA tie-downs, summary, write."""
    aero = json.loads((c.OUT / "osm" / "aeroways.json").read_text())["areas"]
    aprons = [a for a in aero if a["kind"] == "apron"]

    def aprons_of(icao):
        polys = []
        for a in aprons:
            pts = a["pts"]
            if nearest_airport(sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)) == icao:
                polys.append(Polygon(pts).buffer(0))
        return polys

    def ends_of(icao):
        return [(e["x"], e["y"]) for a in airports if (a["icao"] or a["ident"]) == icao
                for r in a["runways"] for e in (r.get("le"), r.get("he")) if e]

    had_osm = {k: bool(v["stands"]) for k, v in out.items()}
    sites = ST.add_stands(out, osm_ways, aprons_of, nearest_airport, ends_of)
    synth_ga_stands(out, sites, aprons, nearest_airport, had_osm)
    (c.OUT / "airport_ops.json").write_text(json.dumps(out))
    for apt, A in sorted(out.items(), key=lambda kv: -len(kv[1]["stands"])):
        src = defaultdict(int)
        for s in A["stands"]:
            src[s.get("src", "?")] += 1
        print(f"{apt}: stands {len(A['stands'])} ({sum(s['jetbridge'] for s in A['stands'])} with jetbridge; "
              f"{', '.join(f'{k} {v}' for k, v in sorted(src.items()))}), "
              f"gates {len(A['gates'])}, holds {len(A['holds'])}, taxi nodes {len(A['taxi']['nodes'])}, "
              f"edges {len(A['taxi']['edges'])}, windsocks {len(A['windsocks'])}, towers {len(A['towers'])}")


if __name__ == "__main__":
    main()
