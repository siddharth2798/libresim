"""Shared constants for the offline pipeline.

World frame = local Transverse Mercator centred on the world origin, so projected
metres are the game's ENU metres (x = east, y = north). Godot maps ENU to
Vector3(x, up, -y).
"""
from pathlib import Path

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
