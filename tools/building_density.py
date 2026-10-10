"""Building density policy for the Konkan-Kerala corridor (04_osm_extract.py).

Kerala's OSM building coverage is very dense (millions of small houses), so corridor tiles
keep every building inside a "zone" -- within ZONE_AIRPORT_M of an airport, ZONE_CITY_M of a
place=city node or ZONE_TOWN_M of a place=town node -- and every building of at least
SMALL_M2 elsewhere; small buildings outside the zones are thinned deterministically by OSM id
(keep 1 in THIN_EVERY). Mumbai-Pune grid tiles are never thinned. Thinning is opt-in
(04_osm_extract.py --thin): measured Oct 2026, the corridor has 1.80 M buildings (0.84 M in
zones, 0.79 M >= 60 m2, 0.17 M small elsewhere), ~0.3 GB of meshes, under the ~600 MB budget.
"""
import json

import osmium
import shapely
from shapely.geometry import Point
from shapely.ops import unary_union

import common as c
import osm_regions as R

ZONE_AIRPORT_M = 8000.0
ZONE_CITY_M = 6000.0
ZONE_TOWN_M = 3000.0
SMALL_M2 = 60.0
THIN_EVERY = 4


def place_nodes(fwd):
    """[(x, y, place)] for place=city/town nodes inside the corridor (both extracts)."""
    def proc(path):
        return osmium.FileProcessor(str(path), osmium.osm.NODE).with_filter(osmium.filter.KeyFilter("place"))

    def inside(o):
        if o.tags.get("place") not in ("city", "town") or not o.location.valid():
            return None
        ll = (o.location.lon, o.location.lat)
        return ll if R.in_corridor(*ll, pad=0.1) else None
    return [(*fwd(o.location.lon, o.location.lat), o.tags["place"]) for o in R.iter_osm(proc, inside)]


class Policy:
    def __init__(self, fwd, thin=False):
        self.thin = thin
        self.grid = R.grid_tiles()
        self.stats = {"corridor": 0, "zone": 0, "large": 0, "small_kept": 0, "small_dropped": 0}
        if not thin:
            return
        circles = []
        apts = c.OUT / "airports.json"
        if apts.exists():
            for a in json.loads(apts.read_text()):
                if a.get("region") == "konkan_kerala" and a["type"] in ("small_airport", "medium_airport", "large_airport"):
                    circles.append(Point(a["x"], a["y"]).buffer(ZONE_AIRPORT_M, 16))
        else:
            print("WARNING: airports.json missing (run 05 first); no airport zones")
        places = place_nodes(fwd)
        for x, y, kind in places:
            circles.append(Point(x, y).buffer(ZONE_CITY_M if kind == "city" else ZONE_TOWN_M, 16))
        self.zones = unary_union(circles)
        shapely.prepare(self.zones)
        print(f"density zones: {len(circles)} circles ({sum(p[2] == 'city' for p in places)} cities, "
              f"{sum(p[2] == 'town' for p in places)} towns), {self.zones.area / 1e6:.0f} km2")

    def keep(self, tile, osm_id, cx, cy, area_m2):
        if tile in self.grid:
            return True
        s = self.stats
        s["corridor"] += 1
        if not self.thin:
            return True
        if shapely.contains_xy(self.zones, cx, cy):
            s["zone"] += 1
            return True
        if area_m2 >= SMALL_M2:
            s["large"] += 1
            return True
        if ((osm_id * 2654435761) % 2 ** 32 >> 16) % THIN_EVERY == 0:
            s["small_kept"] += 1
            return True
        s["small_dropped"] += 1
        return False

    def report(self):
        s = self.stats
        if not self.thin:
            print(f"corridor buildings: {s['corridor']} (no thinning)")
            return
        kept = s["zone"] + s["large"] + s["small_kept"]
        print(f"corridor buildings: {s['corridor']} found, {kept} kept (zones {s['zone']}, "
              f">= {SMALL_M2:.0f} m2 {s['large']}, thinned small {s['small_kept']}), dropped {s['small_dropped']}")
