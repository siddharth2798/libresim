"""Phase R helpers shared by the vector/airport scripts (04, 05, 09, 10, 13, 14).

The vector data covers the union of the two regions: the original Mumbai-Pune BBOX and the
Konkan-Kerala corridor polygon (common.corridor_lonlat). OSM comes from two Geofabrik
extracts that overlap along the Goa/Karnataka and Maharashtra/Karnataka borders, so objects
are de-duplicated by OSM id across files.
"""
import math

import shapely
from shapely.prepared import prep

import common as c

PBFS = [c.RAW / "osm" / "western-zone-latest.osm.pbf",   # Maharashtra, Goa
        c.RAW / "osm" / "southern-zone-latest.osm.pbf"]  # Karnataka, Kerala
DEDUP_LAT = 18.6  # only objects south of this can be in both extracts (border overlap)

_CORR = c.corridor_lonlat()
shapely.prepare(_CORR)
_CB = _CORR.bounds


def in_corridor(lon, lat, pad=0.0):
    if pad:
        return bool(shapely.contains_xy(corridor_buffer(pad), lon, lat))
    return (_CB[0] <= lon <= _CB[2] and _CB[1] <= lat <= _CB[3]
            and bool(shapely.contains_xy(_CORR, lon, lat)))


_BUF = {}


def corridor_buffer(pad):
    if pad not in _BUF:
        g = _CORR.buffer(pad)
        shapely.prepare(g)
        _BUF[pad] = g
    return _BUF[pad]


def in_regions(lon, lat, pad=0.0):
    """True inside the Mumbai-Pune BBOX or the Konkan-Kerala corridor (both padded by pad deg)."""
    return c.in_bbox(lon, lat, pad) or in_corridor(lon, lat, pad)


def region_of(lon, lat):
    return "mumbai_pune" if c.in_bbox(lon, lat) else "konkan_kerala"


def pbf_paths():
    """Existing extracts, western first (its objects win on duplicates)."""
    out = [p for p in PBFS if p.exists()]
    for p in PBFS:
        if not p.exists():
            print(f"WARNING: {p.name} missing; corridor coverage will be incomplete")
    return out


def iter_osm(make_processor, inside_of):
    """Yield objects from every extract that pass inside_of(obj) (-> lon, lat or None),
    skipping objects already yielded from an earlier extract (same type + OSM id).
    make_processor(path) returns an osmium FileProcessor."""
    seen = set()
    paths = pbf_paths()
    for k, path in enumerate(paths):
        last = k == len(paths) - 1
        for obj in make_processor(path):
            ll = inside_of(obj)
            if ll is None:
                continue
            key = (obj.type_str(), obj.id)
            if k and key in seen:
                continue
            if not last and ll[1] < DEDUP_LAT:
                seen.add(key)
            yield obj


def first_location(obj):
    """(lon, lat) of a node, the first node of a way or the first outer-ring node of an area,
    or None when the location is missing."""
    if obj.is_node():
        loc = obj.location
    elif obj.is_way():
        if len(obj.nodes) < 2:
            return None
        loc = obj.nodes[0].location
    elif obj.is_area():
        rings = list(obj.outer_rings())
        if not rings:
            return None
        loc = rings[0][0].location
    else:
        return None
    return (loc.lon, loc.lat) if loc.valid() else None


def region_filter(pad=0.0):
    """inside_of() for iter_osm: first location inside the region union."""
    def f(obj):
        ll = first_location(obj)
        return ll if ll is not None and in_regions(ll[0], ll[1], pad) else None
    return f


def grid_tiles():
    return set(c.region_tiles("mumbai_pune", 0))


def corridor_tiles():
    return set(c.region_tiles("konkan_kerala", 0))


def tile_of(x, y):
    return math.floor(x / c.TILE_SIZE), math.floor(y / c.TILE_SIZE)
