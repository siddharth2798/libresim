"""Phase R helpers shared by the terrain scripts (02, 03, 11, 12, 07).

Per-region terrain metadata:
  mumbai_pune    terrain/meta.json (base file: levels 0-2 + outer ring 3-6 from 12_outer.py)
  konkan_kerala  terrain/meta_konkan_kerala.json, levels 0-2 only
Tile entries are "tx_ty": [min_h, max_h, flags]; flags bit 0 = img tile written, bit 1 = lc
tile written. A missing third element means 3 (both). The runtime borrows imagery / land class
from the nearest ancestor tile whose bit is set.
"""
import argparse
import json
import re

import common as c

T = c.OUT / "terrain"
F_IMG, F_LC = 1, 2
IMG_DIR = c.RAW / "imagery"
CORRIDOR_VRT = IMG_DIR / "corridor" / "s2_corridor.vrt"
OUTER_IMG = [IMG_DIR / "s2_outer.tif", IMG_DIR / "s2_outer_south.tif"]  # 80 m, world frame


def parse_args(doc, default_workers=8):
    p = argparse.ArgumentParser(description=doc)
    p.add_argument("--region", choices=(*c.REGIONS, "all"), default="all",
                   help="region to build (default: all)")
    p.add_argument("--workers", type=int, default=default_workers)
    a = p.parse_args()
    a.regions = list(c.REGIONS) if a.region == "all" else [a.region]
    return a


def meta_path(region):
    return T / ("meta.json" if region == "mumbai_pune" else f"meta_{region}.json")


def load_meta(region):
    return json.loads(meta_path(region).read_text())


def save_meta(region, meta):
    meta_path(region).write_text(json.dumps(meta))


def set_flag(meta, bit, exists):
    """Set/clear `bit` on every tile of a corridor meta; exists(level, tx, ty) -> bool."""
    for L in meta["levels"]:
        for key, v in L["tiles"].items():
            tx, ty = map(int, key.split("_"))
            f = v[2] if len(v) > 2 else 0
            f = (f | bit) if exists(L["level"], tx, ty) else (f & ~bit)
            L["tiles"][key] = [v[0], v[1], f]


def inverse_transformer():
    """world metres -> (lon, lat)."""
    from osgeo import osr
    osr.UseExceptions()
    src = osr.SpatialReference()
    src.ImportFromProj4(c.WORLD_PROJ)
    dst = osr.SpatialReference()
    dst.ImportFromEPSG(4326)
    dst.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    ct = osr.CoordinateTransformation(src, dst)

    def inv(x, y):
        lon, lat, _ = ct.TransformPoint(x, y)
        return lon, lat
    return inv


_TILE_RE = re.compile(r"_([NS])(\d+)_00_([EW])(\d+)_00_")


def dem_sources(bounds=None, pad_deg=0.05):
    """Copernicus GLO-90 then GLO-30 file paths (30 m wins where both exist), optionally only
    the 1-degree tiles touching a world-metre box (x0, y0, x1, y1)."""
    files = sorted((c.RAW / "dem90").glob("*.tif")) + sorted((c.RAW / "dem").glob("*.tif"))
    if bounds is None:
        return [str(p) for p in files]
    inv = inverse_transformer()
    x0, y0, x1, y1 = bounds
    ll = [inv(x, y) for x in (x0, (x0 + x1) / 2, x1) for y in (y0, (y0 + y1) / 2, y1)]
    lo0, lo1 = min(p[0] for p in ll) - pad_deg, max(p[0] for p in ll) + pad_deg
    la0, la1 = min(p[1] for p in ll) - pad_deg, max(p[1] for p in ll) + pad_deg
    out = []
    for p in files:
        m = _TILE_RE.search(p.name)
        if not m:
            continue
        lat = int(m[2]) * (1 if m[1] == "N" else -1)
        lon = int(m[4]) * (1 if m[3] == "E" else -1)
        if lon < lo1 and lon + 1 > lo0 and lat < la1 and lat + 1 > la0:
            out.append(str(p))
    return out


def corridor_img_sources():
    """80 m underlay first, 20 m corridor mosaic on top (warp with srcNodata=0)."""
    return [str(p) for p in (*OUTER_IMG, CORRIDOR_VRT) if p.exists()]
