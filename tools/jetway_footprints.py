"""Building footprints near an airport's jet bridges, for jetway_net.py: the OSM buildings of
04_osm_extract.py (data/processed/osm/buildings/<tx>_<ty>.bin, the same footprints 10_buildings.py
extrudes) plus the landmark terminal footprints (terminals/landmarks.json, 16_terminal_models.py)."""
import json
import math
import struct

from shapely.geometry import Polygon

import common as c

SRC = c.OUT / "osm" / "buildings"
LANDMARKS = c.OUT / "terminals" / "landmarks.json"
_tiles = {}


def _tile(tx, ty):
    if (tx, ty) not in _tiles:
        out = []
        p = SRC / f"{tx}_{ty}.bin"
        if p.exists():
            b = p.read_bytes()
            i = 0
            while i < len(b):
                n, _h = struct.unpack_from("<Hf", b, i)
                i += 6
                pts = struct.unpack_from("<%df" % (2 * n), b, i)
                i += 8 * n
                if n >= 3:
                    out.append([(pts[2 * k], pts[2 * k + 1]) for k in range(n)])
        _tiles[(tx, ty)] = out
    return _tiles[(tx, ty)]


def polys_of(icao, ways):
    """Footprint polygons within 300 m of the ways' bounding box."""
    if not ways:
        return []
    xs = [p[0] for w in ways for p in w["pts"]]
    ys = [p[1] for w in ways for p in w["pts"]]
    lo, hi = (min(xs) - 300, min(ys) - 300), (max(xs) + 300, max(ys) + 300)
    rings = []
    for tx in range(math.floor(lo[0] / c.TILE_SIZE), math.floor(hi[0] / c.TILE_SIZE) + 1):
        for ty in range(math.floor(lo[1] / c.TILE_SIZE), math.floor(hi[1] / c.TILE_SIZE) + 1):
            rings += _tile(tx, ty)
    if LANDMARKS.exists():
        rings += json.loads(LANDMARKS.read_text()).get(icao, [])
    out = []
    for r in rings:
        if any(lo[0] <= x <= hi[0] and lo[1] <= y <= hi[1] for x, y in r):
            pg = Polygon(r).buffer(0)
            if not pg.is_empty and pg.area > 20.0:
                out.append(pg)
    return out
