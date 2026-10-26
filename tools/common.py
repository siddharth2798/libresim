"""Shared constants for the offline pipeline.

World frame = local Transverse Mercator centred on the world origin, so projected
metres are the game's ENU metres (x = east, y = north). Godot maps ENU to
Vector3(x, up, -y).
"""
import os
import ssl
from pathlib import Path

# python.org builds on macOS ship without CA certificates, so urllib fails with
# CERTIFICATE_VERIFY_FAILED. Fall back to the system bundle (stdlib-only; no certifi needed).
if not os.environ.get("SSL_CERT_FILE") and not os.path.exists(ssl.get_default_verify_paths().cafile or ""):
    for _ca in ("/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt"):
        if os.path.exists(_ca):
            os.environ["SSL_CERT_FILE"] = _ca
            break

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
OUT = ROOT / "data" / "processed"

ORIGIN_LAT = 18.75
ORIGIN_LON = 73.40
BBOX = (72.75, 18.30, 74.10, 19.30)  # lon_min, lat_min, lon_max, lat_max

WORLD_PROJ = (f"+proj=tmerc +lat_0={ORIGIN_LAT} +lon_0={ORIGIN_LON} +k=1 "
              "+x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs")

# Terrain tiling: level-0 tile = TILE_N samples at DEM_RES m (+1 overlap sample).
DEM_RES = 30.0
TILE_N = 256
TILE_SIZE = DEM_RES * TILE_N  # 7680 m
# World extent in tile units, symmetric-ish around the origin (covers BBOX).
X_MIN, X_MAX = -9 * TILE_SIZE, 10 * TILE_SIZE   # -69.12 .. 76.80 km
Y_MIN, Y_MAX = -7 * TILE_SIZE, 8 * TILE_SIZE    # -53.76 .. 61.44 km
LEVELS = 5  # level k tile covers TILE_SIZE * 2^k

# Heights stored as uint16: h = v * H_SCALE + H_OFFSET
H_SCALE = 0.1
H_OFFSET = -100.0

IMG_RES = 10.0
IMG_N = 768  # pixels per imagery tile edge (all levels)


def transformer():
    """lon/lat (EPSG:4326, x=lon) -> world metres."""
    from osgeo import osr
    osr.UseExceptions()
    src = osr.SpatialReference()
    src.ImportFromEPSG(4326)
    src.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    dst = osr.SpatialReference()
    dst.ImportFromProj4(WORLD_PROJ)
    ct = osr.CoordinateTransformation(src, dst)

    def fwd(lon, lat):
        x, y, _ = ct.TransformPoint(lon, lat)
        return x, y
    return fwd


def in_bbox(lon, lat, pad=0.0):
    return (BBOX[0] - pad <= lon <= BBOX[2] + pad and
            BBOX[1] - pad <= lat <= BBOX[3] + pad)

# Outer ring (coarse real data, levels >= OUTER_MIN_LEVEL): 8 x 8 level-3 tiles around the origin.
OUTER_MIN_LEVEL = 3
OUTER = (-4 * TILE_SIZE * 8, -4 * TILE_SIZE * 8, 4 * TILE_SIZE * 8, 4 * TILE_SIZE * 8)  # +/-245.76 km
LEVELS_TOTAL = 7  # levels 0..6; level 6 tiles are 491.52 km

# ---------------------------------------------------------------- Phase R: regions
# The world frame stays the single TM above (Kochi is only ~3 deg of longitude from the
# central meridian: scale error ~0.13 %). Regions only add data:
#   "mumbai_pune"   the original grid X/Y_MIN..MAX, 10 m imagery at level 0.
#   "konkan_kerala" a coastal corridor 18.4 N -> 9.8 N (Mumbai -> Kochi), from ~0.3 deg out to
#                   sea to ~1.05 deg inland (Western Ghats crest, Kolhapur, Belagavi). 30 m DEM at
#                   level 0, imagery at 20 m (level 1, 768 px per 15.36 km); level-0 tiles borrow
#                   their parent's imagery at runtime (terrain_tile_cache imagery fallback).
# Coastline anchor points (lon, lat), north -> south.
COAST = [(72.82, 18.40), (72.95, 17.95), (73.10, 17.50), (73.28, 17.00), (73.33, 16.55),
         (73.47, 16.06), (73.66, 15.75), (73.80, 15.45), (73.95, 15.10), (74.12, 14.80),
         (74.35, 14.40), (74.55, 13.97), (74.70, 13.35), (74.82, 12.87), (74.98, 12.50),
         (75.20, 12.10), (75.36, 11.87), (75.62, 11.50), (75.77, 11.25), (75.88, 10.90),
         (76.02, 10.55), (76.17, 10.20), (76.24, 9.80)]
CORRIDOR_SEA_DEG = 0.30
CORRIDOR_LAND_DEG = 1.05
CORRIDOR_IMG_RES = 20.0
CORRIDOR_IMG_LEVEL = 1
# Outer ring (levels >= OUTER_MIN_LEVEL) now spans level-6 tiles tx -1..0, ty -2..0 so Kochi
# (~ +330 km E, -955 km N) is inside; real 90 m DEM / 80 m imagery over OUTER plus OUTER_SOUTH.
OUTER_TOTAL = (-491520.0, -983040.0, 491520.0, 491520.0)
OUTER_SOUTH = (-245760.0, -983040.0, 491520.0, -245760.0)


def corridor_lonlat():
    """Corridor polygon in lon/lat (shapely Polygon)."""
    from shapely.geometry import Polygon
    west = [(lon - CORRIDOR_SEA_DEG, lat) for lon, lat in COAST]
    east = [(lon + CORRIDOR_LAND_DEG, lat) for lon, lat in COAST]
    return Polygon(west + east[::-1])


def corridor_world(step_deg=0.05):
    """Corridor polygon in world metres (edges densified before projecting)."""
    from shapely.geometry import Polygon
    fwd = transformer()
    ring = list(corridor_lonlat().exterior.coords)
    pts = []
    for (a, b), (cc, d) in zip(ring, ring[1:]):
        n = max(int(max(abs(cc - a), abs(d - b)) / step_deg), 1)
        pts += [fwd(a + (cc - a) * i / n, b + (d - b) * i / n) for i in range(n)]
    return Polygon(pts)


def region_tiles(region, level=0):
    """(tx, ty) tiles of a region at a level: grid tiles for mumbai_pune, tiles touching the
    corridor for konkan_kerala (minus those already in mumbai_pune)."""
    import math
    size = TILE_SIZE * 2 ** level
    grid = {(tx, ty) for tx in range(math.floor(X_MIN / size), math.ceil(X_MAX / size))
            for ty in range(math.floor(Y_MIN / size), math.ceil(Y_MAX / size))}
    if region == "mumbai_pune":
        return sorted(grid)
    from shapely.geometry import box
    poly = corridor_world()
    x0, y0, x1, y1 = poly.bounds
    out = []
    for tx in range(math.floor(x0 / size), math.ceil(x1 / size)):
        for ty in range(math.floor(y0 / size), math.ceil(y1 / size)):
            if (tx, ty) not in grid and poly.intersects(box(tx * size, ty * size, (tx + 1) * size, (ty + 1) * size)):
                out.append((tx, ty))
    return out


REGIONS = ("mumbai_pune", "konkan_kerala")
