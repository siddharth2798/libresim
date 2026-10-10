"""OSM pbf -> data/processed/osm/
  aeroways.json   runways/taxiways (lines + width) and aprons/runway areas (polygons)
  roads.json      major roads as polylines with class
  water.json      water/riverbank polygons (outer rings)
  buildings/<tx>_<ty>.bin   footprints grouped by level-0 terrain tile:
      repeated [u16 n][f32 height_m][n * (f32 x, f32 y)]  little-endian, world metres
Covers the Mumbai-Pune BBOX plus the Konkan-Kerala corridor, reading both Geofabrik extracts
(western + southern zone, de-duplicated by OSM id). Corridor buildings follow the density
policy in building_density.py (run 05 first: airport zones); thinning is off by default
(the full corridor is ~1.8 M buildings, ~0.3 GB of meshes). Usage: 04_osm_extract.py [--thin]
"""
import json
import math
import struct
import sys
import time
from collections import defaultdict

import osmium

import building_density
import common as c
import osm_regions as R

OUTD = c.OUT / "osm"
ROAD_CLASSES = {"motorway", "trunk", "primary", "secondary", "tertiary",
                "motorway_link", "trunk_link", "primary_link"}
LEVEL_H = 3.2
DEFAULT_H = 9.0


def r2(v):
    return round(v, 1)


def building_height(tags):
    for k in ("height", "building:height"):
        try:
            return float(tags.get(k, "").replace("m", "").strip())
        except ValueError:
            pass
    try:
        return float(tags.get("building:levels")) * LEVEL_H + 1.0
    except (TypeError, ValueError):
        return DEFAULT_H


def main():
    fwd = c.transformer()
    policy = building_density.Policy(fwd, thin="--thin" in sys.argv)
    tiles_ok = R.grid_tiles() | R.corridor_tiles()

    def line_xy(nodes):
        pts = []
        for n in nodes:
            if not n.location.valid():
                return None
            pts.append(fwd(n.location.lon, n.location.lat))
        return pts

    aero_lines, aero_areas, roads, water = [], [], [], []
    buildings = defaultdict(list)
    n_bld = 0
    t0 = time.time()
    def proc(path):
        return (osmium.FileProcessor(str(path)).with_locations().with_areas()
                .with_filter(osmium.filter.KeyFilter("aeroway", "building", "natural",
                                                     "water", "waterway", "highway")))
    for obj in R.iter_osm(proc, R.region_filter()):
        tags = obj.tags
        if obj.is_way():
            nodes = obj.nodes
            aw, hw = tags.get("aeroway"), tags.get("highway")
            if aw in ("runway", "taxiway") and not obj.is_closed():
                pts = line_xy(nodes)
                if pts:
                    aero_lines.append({"kind": aw, "ref": tags.get("ref", ""),
                                       "width": tags.get("width", ""),
                                       "surface": tags.get("surface", ""),
                                       "pts": [[r2(x), r2(y)] for x, y in pts]})
            elif hw in ROAD_CLASSES:
                pts = line_xy(nodes)
                if pts:
                    roads.append({"cls": hw, "pts": [[r2(x), r2(y)] for x, y in pts]})
        elif obj.is_area():
            rings = list(obj.outer_rings())
            aw = tags.get("aeroway")
            if aw in ("runway", "apron", "taxiway"):
                for ring in rings:
                    pts = line_xy(ring)
                    if pts:
                        aero_areas.append({"kind": aw, "ref": tags.get("ref", ""),
                                           "pts": [[r2(x), r2(y)] for x, y in pts]})
            elif tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
                for ring in rings:
                    pts = line_xy(ring)
                    if pts and len(pts) >= 4:
                        water.append([[r2(x), r2(y)] for x, y in pts])
            elif "building" in tags:
                pts = line_xy(rings[0])
                if not pts or len(pts) < 4 or len(pts) > 2000:
                    continue
                cx = sum(p[0] for p in pts) / len(pts)
                cy = sum(p[1] for p in pts) / len(pts)
                key = (math.floor(cx / c.TILE_SIZE), math.floor(cy / c.TILE_SIZE))
                if key not in tiles_ok:
                    continue
                a = 0.5 * abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:])))
                if not policy.keep(key, obj.id, cx, cy, a):
                    continue
                buildings[key].append((building_height(tags), pts[:-1]))
                n_bld += 1

    OUTD.mkdir(parents=True, exist_ok=True)
    (OUTD / "aeroways.json").write_text(json.dumps({"lines": aero_lines, "areas": aero_areas}))
    (OUTD / "roads.json").write_text(json.dumps(roads))
    (OUTD / "water.json").write_text(json.dumps(water))
    bdir = OUTD / "buildings"
    bdir.mkdir(exist_ok=True)
    for old in bdir.glob("*.bin"):
        old.unlink()
    for (tx, ty), items in buildings.items():
        with open(bdir / f"{tx}_{ty}.bin", "wb") as f:
            for h, pts in items:
                f.write(struct.pack("<Hf", len(pts), h))
                f.write(struct.pack(f"<{2 * len(pts)}f", *(v for p in pts for v in p)))
    print(f"{time.time() - t0:.0f}s  aero lines {len(aero_lines)}, aero areas {len(aero_areas)}, "
          f"roads {len(roads)}, water {len(water)}, buildings {n_bld} in {len(buildings)} tiles")
    policy.report()


if __name__ == "__main__":
    main()
