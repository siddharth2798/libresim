"""Passenger terminal complexes -> data/processed/terminals/<ICAO>.json

Per airport: terminal buildings and the landside/airside bits that define their look.
  terminals:      aeroway=terminal / building=terminal areas, or buildings named "Terminal ..."
  parts:          buildings with centroid in a terminal; building:part / roof canopies <= 30 m
  jet_bridges:    aeroway=jet_bridge ways within 150 m of a terminal
  car_parks:      multi-storey car parks (parking=multi-storey or building=parking) within 300 m
  elevated_roads: highways with bridge=* or layer>=1 within 300 m of a terminal
Each feature: osm ("way/123" | "relation/45"), tags (relevant subset), outers/inners (areas) or
line (roads/bridges) as [[east, north], ...] world metres, area_m2 / length_m, centroid [e, n],
lonlat centroid, obb [length, width, heading_deg of the long axis].
Airports: AIRPORTS (VABB VAPO VOCI) or any ICAO in data/processed/airports.json (05), read from the
Geofabrik extracts that can hold it (osm_regions.PBFS: western north of 14.8 N, southern south of 18.6 N).
VOCI is fetched once from Overpass into data/raw/osm/overpass_VOCI.json (delete to refetch).
Usage: 15_terminals.py [ICAO ...]  (default: VABB VAPO VOCI + every airport with a passenger
terminal in tools/ref/terminals_reference.json)
"""
import json
import sys
import urllib.parse
import urllib.request

import numpy as np

import common as c
import osm_regions as R
import terminal_ref
from osm_geom import ring_ac, inside, poly_dist, obb

OUTD = c.OUT / "terminals"
AIRPORTS = {"VABB": (19.089, 72.868), "VAPO": (18.582, 73.920), "VOCI": (10.152, 76.392)}
OVERPASS = {"VOCI"}
HALF_DEG = 0.03  # ~3.3 km search box half-size
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
UA = "free-sim/0.1 (offline flight-sim data pipeline; one-off fetch)"
KEEP = ("name", "name:en", "ref", "building", "building:part", "aeroway", "amenity", "parking",
        "highway", "height", "min_height", "building:levels", "building:min_level", "roof:shape",
        "roof:colour", "roof:material", "roof:height", "building:colour", "building:material",
        "layer", "bridge", "operator")
JB_DIST, NEAR_DIST, PART_DIST = 150.0, 300.0, 30.0  # m
MIN_TERM = 500.0  # m2; drops kiosks tagged aeroway=terminal
GROUPS = ("terminals", "parts", "jet_bridges", "car_parks", "elevated_roads")
WALKWAYS = {"footway", "path", "steps", "corridor", "cycleway", "pedestrian"}


def elevated(tags):
    layer = tags.get("layer", "0")
    return tags.get("bridge", "no") != "no" or (layer.isdigit() and int(layer) >= 1)


def add_airports(icaos):
    """Reference points of ICAOs not in AIRPORTS, from airports.json (05_airports_navaids.py)."""
    for a in json.loads((c.OUT / "airports.json").read_text()):
        if a.get("icao") in icaos and a["icao"] not in AIRPORTS:
            AIRPORTS[a["icao"]] = (a["lat"], a["lon"])


def which_airport(lon, lat, icaos):
    return next((i for i in icaos if abs(lon - AIRPORTS[i][1]) <= HALF_DEG
                 and abs(lat - AIRPORTS[i][0]) <= HALF_DEG), None)


def raw(osm, tags, kind, outers, inners=()):
    return {"osm": osm, "tags": dict(tags), "kind": kind, "outers": outers, "inners": list(inners)}


def read_pbf(icaos):
    import osmium
    feats, seen = {i: [] for i in icaos}, set()
    lats = [AIRPORTS[i][0] for i in icaos]
    paths = [p for p, k in zip(R.PBFS, (max(lats) > 14.8, min(lats) < R.DEDUP_LAT)) if k and p.exists()]
    ll = lambda ns: [(n.location.lon, n.location.lat) for n in ns if n.location.valid()]  # noqa: E731
    for o in (o for p in paths for o in osmium.FileProcessor(str(p)).with_locations().with_areas()
              .with_filter(osmium.filter.KeyFilter("aeroway", "building", "building:part", "amenity", "highway"))):
        tags = {t.k: t.v for t in o.tags}
        if o.is_way():
            if not (("highway" in tags and elevated(tags)) or tags.get("aeroway") == "jet_bridge"):
                continue
            pts = ll(o.nodes)
            if pts and (apt := which_airport(*pts[0], icaos)) and f"way/{o.id}" not in seen:
                seen.add(f"way/{o.id}")
                feats[apt].append(raw(f"way/{o.id}", tags, "line", [pts]))
        elif o.is_area():
            if "highway" in tags or tags.get("aeroway") == "jet_bridge":
                continue
            outers, inners = [], []
            for ring in o.outer_rings():
                outers.append(ll(ring))
                inners += [ll(r) for r in o.inner_rings(ring)]
            if outers and outers[0] and (apt := which_airport(*outers[0][0], icaos)):
                osm = f"{'way' if o.from_way() else 'relation'}/{o.orig_id()}"
                if osm not in seen:
                    seen.add(osm)
                    feats[apt].append(raw(osm, tags, "area", outers, inners))
    return feats


def fetch_overpass(icao):
    cache = c.RAW / "osm" / f"overpass_{icao}.json"
    if not cache.exists():
        la, lo = AIRPORTS[icao]
        bb = f"{la - HALF_DEG},{lo - HALF_DEG},{la + HALF_DEG},{lo + HALF_DEG}"
        q = (f"[out:json][timeout:120];("
             f'nwr["aeroway"]({bb});way["building"]({bb});relation["building"]({bb});'
             f'way["building:part"]({bb});relation["building:part"]({bb});'
             f'nwr["amenity"="parking"]({bb});way["highway"]["bridge"]({bb});'
             f'way["highway"]["layer"]({bb}););out geom;')
        req = urllib.request.Request(OVERPASS_URL, data=urllib.parse.urlencode({"data": q}).encode(),
                                     headers={"User-Agent": UA})
        print(f"{icao}: fetching from Overpass ...")
        try:
            data = json.loads(body := urllib.request.urlopen(req, timeout=180).read())
        except Exception as e:  # noqa: BLE001 - report any network/parse failure clearly
            sys.exit(f"{icao}: Overpass fetch failed ({e}). Retry later or place a response at {cache}.")
        if "elements" not in data:
            sys.exit(f"{icao}: unexpected Overpass response: {str(data)[:200]}")
        cache.write_bytes(body)
        print(f"{icao}: cached {len(data['elements'])} elements -> {cache}")
    return json.loads(cache.read_text())


def stitch(segs):
    """Join open way segments (lists of (lon, lat)) into closed rings."""
    segs, rings = [list(s) for s in segs if len(s) >= 2], []
    while segs:
        ring = segs.pop(0)
        while ring[0] != ring[-1]:
            i = next((i for i, s in enumerate(segs) if ring[-1] in (s[0], s[-1])), None)
            if i is None:
                break
            s = segs.pop(i)
            ring += (s if s[0] == ring[-1] else s[::-1])[1:]
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring)
    return rings


def read_overpass(icao):
    feats = []
    for el in fetch_overpass(icao)["elements"]:
        tags = el.get("tags", {})
        if el["type"] == "way" and "geometry" in el:
            pts = [(g["lon"], g["lat"]) for g in el["geometry"] if g]
            if ("highway" in tags and elevated(tags)) or tags.get("aeroway") == "jet_bridge":
                feats.append(raw(f"way/{el['id']}", tags, "line", [pts]))
            elif "highway" not in tags and len(pts) >= 4 and pts[0] == pts[-1]:
                feats.append(raw(f"way/{el['id']}", tags, "area", [pts]))
        elif el["type"] == "relation" and tags.get("type") in ("multipolygon", "building"):
            segs = {"outer": [], "inner": []}
            for m in el.get("members", []):
                if m["type"] == "way" and "geometry" in m and m.get("role", "outer") in ("outer", "inner", ""):
                    segs["inner" if m["role"] == "inner" else "outer"].append(
                        [(g["lon"], g["lat"]) for g in m["geometry"] if g])
            outers = stitch(segs["outer"])
            if outers:
                feats.append(raw(f"relation/{el['id']}", tags, "area", outers, stitch(segs["inner"])))
    return feats


def finish(f, fwd):
    """Project to world metres and add derived geometry."""
    f["xy"] = [np.array([fwd(lo, la) for lo, la in r]) for r in f["outers"] if len(r) >= 2]
    f["ixy"] = [np.array([fwd(lo, la) for lo, la in r]) for r in f["inners"] if len(r) >= 4]
    if not f["xy"]:
        return False
    allp = np.vstack(f["xy"])
    if f["kind"] == "area":
        ac = [ring_ac(r) for r in f["xy"]]
        tot = max(sum(a for a, _ in ac), 1e-9)
        f["area"] = tot - sum(ring_ac(r)[0] for r in f["ixy"])
        f["cen"] = sum(cn * a for a, cn in ac) / tot
    else:
        f["len"] = sum(float(np.hypot(*np.diff(r, axis=0).T).sum()) for r in f["xy"])
        f["cen"] = allp.mean(axis=0)
    f["obb"] = obb(allp) if len(allp) >= 3 else None
    return True


def emit(f):
    r1 = lambda r: [[round(float(x), 1), round(float(y), 1)] for x, y in r]  # noqa: E731
    ll = np.array([p for r in f["outers"] for p in r]).mean(axis=0)
    o = {"osm": f["osm"], "tags": {k: f["tags"][k] for k in KEEP if k in f["tags"]},
         "centroid": [round(float(f["cen"][0]), 1), round(float(f["cen"][1]), 1)],
         "lonlat": [round(float(ll[0]), 6), round(float(ll[1]), 6)], "obb": f["obb"]}
    if f["kind"] == "area":
        o.update(outers=[r1(r) for r in f["xy"]], inners=[r1(r) for r in f["ixy"]],
                 area_m2=round(f["area"], 0))
    else:
        o.update(line=r1(f["xy"][0]), length_m=round(f["len"], 1))
    return o


def is_terminal(t):
    """Passenger terminals only (cargo terminals are skipped)."""
    name = (t.get("name", "") + " " + t.get("name:en", "")).lower()
    return "cargo" not in name and (t.get("aeroway") == "terminal" or t.get("building") == "terminal"
            or ("terminal" in name and "building" in t))


def classify(icao, feats, fwd):
    feats = [f for f in feats if finish(f, fwd)]
    areas = [f for f in feats if f["kind"] == "area"]
    ref = np.array(fwd(AIRPORTS[icao][1], AIRPORTS[icao][0]))
    aero = [f for f in areas if f["tags"].get("aeroway") == "aerodrome"
            and any(inside(ref, r) for r in f["xy"])]
    aero = max(aero, key=lambda f: f["area"]) if aero else None
    print(f"{icao}: aerodrome boundary {aero['osm'] + ' %.1f km2' % (aero['area'] / 1e6) if aero else 'none (bbox)'}")
    terms = [f for f in areas if is_terminal(f["tags"]) and f["tags"].get("aeroway") != "aerodrome"
             and f["area"] >= MIN_TERM and (aero is None or poly_dist(f, aero) < NEAR_DIST)]
    tids = {id(t) for t in terms}
    near = lambda f, d: any(poly_dist(f, t) <= d for t in terms)  # noqa: E731
    parts = [f for f in areas if id(f) not in tids and f["tags"].get("building") != "parking" and (
        ("building" in f["tags"] or "building:part" in f["tags"])
        and any(inside(f["cen"], r) for t in terms for r in t["xy"])
        or ("building:part" in f["tags"] or f["tags"].get("building") == "roof") and near(f, PART_DIST))]
    jbs = [f for f in feats if f["tags"].get("aeroway") == "jet_bridge" and near(f, JB_DIST)]
    parks = [f for f in areas if (f["tags"].get("parking") in ("multi-storey", "multistorey")
                                  or f["tags"].get("building") == "parking") and near(f, NEAR_DIST)]
    roads = [f for f in feats if f["kind"] == "line" and f["tags"].get("highway", "footway") not in WALKWAYS
             and near(f, NEAR_DIST)]
    terms.sort(key=lambda f: -f["area"])
    return {"icao": icao, "aerodrome": aero and aero["osm"],
            **{k: [emit(f) for f in g] for k, g in zip(GROUPS, (terms, parts, jbs, parks, roads))}}


def main():
    icaos = [a.upper() for a in sys.argv[1:]] or list(dict.fromkeys(
        list(AIRPORTS) + [i for i, a in terminal_ref.load().items() if a.get("has_passenger_terminal")]))
    fwd = c.transformer()
    add_airports(icaos)
    local = [i for i in icaos if i not in OVERPASS]
    feats = read_pbf(local) if local else {}
    feats.update({i: read_overpass(i) for i in icaos if i in OVERPASS})
    OUTD.mkdir(parents=True, exist_ok=True)
    for i in icaos:
        out = classify(i, feats[i], fwd)
        (OUTD / f"{i}.json").write_text(json.dumps(out))
        print(f"{i}: {len(feats[i])} candidates -> " + ", ".join(f"{k} {len(out[k])}" for k in GROUPS))
        for t in out["terminals"]:
            print(f"   {t['osm']:>18} {t['tags'].get('name', '-')[:40]:40} {t['area_m2']:>9.0f} m2  obb {t['obb']}")


if __name__ == "__main__":
    main()
