"""OSM roads, tracks and waterway lines for the terrain road / river masks (used by 20_roads_rivers.py).

04_osm_extract.py keeps only major roads for the buildings / land-class steps; the terrain masks also
need residential streets, service roads, tracks, and river / stream / canal centrelines. One pass over
both Geofabrik extracts (osm_regions.iter_osm de-duplicates them) writes the compact cache
  data/processed/osm/ways.npz   pts float32 (N, 2) world metres, off int64 (W+1), kind uint8 (W), bridge uint8 (W)
kind codes are WAY_KINDS indices. Tunnels, culverts and underground ways are dropped; bridges are kept
(flag) so roads can cross water. Cached: reused unless --refresh-osm.
"""
import time

import numpy as np
import osmium

import common as c
import osm_regions as R

CACHE = c.OUT / "osm" / "ways.npz"
# (OSM value, kind name); index = kind code. Roads first, then waterways.
WAY_KINDS = ["motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential",
             "service", "track", "river", "canal", "stream", "drain"]
HIGHWAY = {"motorway": 0, "motorway_link": 0, "trunk": 1, "trunk_link": 1, "primary": 2, "primary_link": 2,
           "secondary": 3, "secondary_link": 3, "tertiary": 4, "tertiary_link": 4, "unclassified": 5,
           "residential": 6, "living_street": 6, "service": 7, "track": 8}
WATERWAY = {"river": 9, "canal": 10, "stream": 11, "drain": 12}
N_ROAD_KINDS = 9


def _kind(tags):
    hw = tags.get("highway")
    if hw is not None:
        return HIGHWAY.get(hw, -1)
    return WATERWAY.get(tags.get("waterway"), -1)


def _underground(tags):
    return (tags.get("tunnel") not in (None, "no") or tags.get("covered") == "yes"
            or tags.get("location") == "underground" or tags.get("layer", "0").startswith("-")
            and tags.get("bridge") is None)


def extract():
    fwd = c.transformer()
    pts, off, kind, bridge = [], [0], [], []
    t0 = time.time()

    def proc(path):
        return (osmium.FileProcessor(str(path), osmium.osm.NODE | osmium.osm.WAY).with_locations()
                .with_filter(osmium.filter.KeyFilter("highway", "waterway")))

    for obj in R.iter_osm(proc, R.region_filter()):
        if not obj.is_way():
            continue
        k = _kind(obj.tags)
        if k < 0 or _underground(obj.tags) or len(obj.nodes) < 2:
            continue
        p = []
        for n in obj.nodes:
            if not n.location.valid():
                p = None
                break
            p.append(fwd(n.location.lon, n.location.lat))
        if not p:
            continue
        pts.extend(p)
        off.append(len(pts))
        kind.append(k)
        bridge.append(1 if obj.tags.get("bridge", "no") != "no" else 0)
    np.savez(CACHE, pts=np.asarray(pts, np.float32), off=np.asarray(off, np.int64),
             kind=np.asarray(kind, np.uint8), bridge=np.asarray(bridge, np.uint8))
    print(f"ways extracted: {len(kind)} ways, {len(pts)} points [{time.time() - t0:.0f} s]")


def load(refresh=False):
    """-> dict of arrays (pts, off, kind, bridge); extracts first when the cache is missing."""
    if refresh or not CACHE.exists():
        extract()
    with np.load(CACHE) as z:
        return {k: z[k] for k in z.files}
