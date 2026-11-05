"""Airport pavement masks for the terrain shader: aprons, stands and runway / taxiway shoulders.

There is no apron mesh: aprons are terrain coloured by the imagery. For every level-0 tile with
pavement this writes data/processed/terrain/pv/0/<tx>_<ty>.png (1920 x 1920 RGBA, 4 m texels, same
lattice as the road tiles; layout in pavement_raster.py) so the shader draws a clean paved surface
(concrete slabs or asphalt, tyre marks along stand lead-in lines, oil stains under aircraft).
Inputs: OSM aeroway=apron / runway / taxiway areas (osm/aeroways.json from 04, plus their surface
tag from one osmium pass over the extracts, cached in osm/aeroway_areas.json; --refresh-osm
re-reads), runways.json (09: centrelines; ribbons get asphalt shoulders), airport_ops.json (13 / 17:
stands, each also gets a paved pad).
Tiles are only re-written with --force. --only tx_ty,...
"""
import argparse
import json
import math
import time

import numpy as np
import shapely
from PIL import Image, ImageDraw
from scipy.ndimage import grey_dilation

import common as c
import pavement_raster as pr

OUT = c.OUT / "terrain" / "pv" / "0"
SURF_CACHE = c.OUT / "osm" / "aeroway_areas.json"
RWY_SHOULDER, TWY_SHOULDER = 7.5, 4.0  # m of paved shoulder beyond the ribbon's half-width
ASPHALT = {"asphalt", "paved", "bitumen", "tarmac"}
CONCRETE, ASPH = 1, 2
STAND_FWD, STAND_BACK, STAND_HW = 14.0, 62.0, 24.0  # m: paved pad around a stand stop point
CLOSE_M, FILL_ZONE_M = 38.0, 170.0  # apron fill: closing radius, reach from a stand


def osm_areas(refresh=False):
    """[{"pts", "surface"}] every OSM aeroway apron / taxiway / runway area (multipolygons too;
    osm/aeroways.json misses some), from one osmium pass over the extracts, cached."""
    if SURF_CACHE.exists() and not refresh:
        return json.loads(SURF_CACHE.read_text())
    import osmium
    import osm_regions as R
    fwd = c.transformer()
    out = []
    proc = lambda path: (osmium.FileProcessor(str(path)).with_locations().with_areas()
                         .with_filter(osmium.filter.TagFilter(("aeroway", "apron"), ("aeroway", "taxiway"),
                                                              ("aeroway", "runway"))))
    for o in R.iter_osm(proc, R.region_filter()):
        if not o.is_area():
            continue
        for ring in o.outer_rings():
            xy = [fwd(n.location.lon, n.location.lat) for n in ring if n.location.valid()]
            if len(xy) >= 4:
                out.append({"pts": [[round(x, 1), round(y, 1)] for x, y in xy], "surface": o.tags.get("surface", "")})
    SURF_CACHE.write_text(json.dumps(out))
    return out


def stand_pad(x, y, hd):
    """Paved footprint of a stand (OSM often maps the stands but not the apron around them)."""
    f, r = np.array([math.sin(hd), math.cos(hd)]), np.array([math.cos(hd), -math.sin(hd)])
    p = np.array([x, y])
    q = [p + f * STAND_FWD + r * STAND_HW, p + f * STAND_FWD - r * STAND_HW,
         p - f * STAND_BACK - r * STAND_HW, p - f * STAND_BACK + r * STAND_HW]
    return shapely.Polygon(q)


def features():
    """-> (polys [(Polygon, surface, angle, is_stand_pad)], lines [buffered ribbons], stands [(x, y, hd, slab angle)])."""
    aero = json.loads((c.OUT / "osm" / "aeroways.json").read_text())
    areas = [(a["pts"], "") for a in aero["areas"]] + [(a["pts"], a["surface"]) for a in osm_areas()]
    polys = []
    for pts, sf in areas:
        if len(pts) < 4:
            continue
        g = shapely.make_valid(shapely.Polygon(pts))
        if g.is_empty or g.area < 50.0:
            continue
        polys.append((g, ASPH if sf in ASPHALT else CONCRETE, pr.dominant_angle(pts), False))
    rw = json.loads((c.OUT / "runways.json").read_text())
    lines = []
    for r in rw["runways"]:
        a, b = r["ends"]
        lines.append(shapely.LineString([(a["x"], a["y"]), (b["x"], b["y"])]).buffer(
            float(r["width"]) / 2 + RWY_SHOULDER, cap_style="flat"))
    for t in rw["taxiways"]:
        if len(t["pts"]) >= 2:
            lines.append(shapely.LineString(t["pts"]).buffer(min(float(t["width"]), 23.0) / 2 + TWY_SHOULDER))
    # slab grid of the stand pads and the filled apron: along the airport's longest runway (one
    # grid per airport, so pads and fill never meet at an angle), else the mean stand heading
    rwy_ang = {}
    for r in sorted(rw["runways"], key=lambda r: float(r["length"])):
        a, b = r["ends"]
        rwy_ang[r["airport"]] = math.atan2(b["y"] - a["y"], b["x"] - a["x"]) % (math.pi / 2)
    stands = []
    for icao, ap in json.loads((c.OUT / "airport_ops.json").read_text()).items():
        hs = [math.radians(float(s["heading_deg"])) for s in ap.get("stands", [])]
        ang = rwy_ang.get(icao, (np.angle(np.sum(np.exp(4j * np.array(hs)))) / 4.0) % (math.pi / 2) if hs else 0.0)
        for s in ap.get("stands", []):
            hd = math.radians(float(s["heading_deg"]))
            # stop point of the nose wheel: jetbridge stands give the door, others the parking point
            back = 3.0 if s.get("jetbridge") else -6.0
            x, y = s["x"] - math.sin(hd) * back, s["y"] - math.cos(hd) * back
            stands.append((x, y, hd, ang))
            polys.append((stand_pad(x, y, hd), CONCRETE, ang, True))
    return polys, lines, stands


def apron_fill(box, polys, lines, stands):
    """Apron between the stands and the taxilanes (OSM often has no apron polygon there): a
    morphological closing of the paved shapes near stands, over a padded box so tiles agree."""
    big = box.buffer(CLOSE_M * 4, join_style="mitre")
    pts = [shapely.Point(x, y) for x, y, *_ in stands if big.contains(shapely.Point(x, y))]
    if not pts:
        return None
    zone = shapely.union_all([p.buffer(FILL_ZONE_M) for p in pts])
    near = [g for g, *_ in polys if g.intersects(zone)] + [g for g in lines if g.intersects(zone)]
    local = shapely.union_all(near).intersection(zone.buffer(CLOSE_M))
    closed = local.buffer(CLOSE_M, quad_segs=4).buffer(-CLOSE_M, quad_segs=4).intersection(zone).intersection(box)
    return None if closed.is_empty else closed


def fill_angle(box, stands):
    """Slab direction of the filled apron: that of the airport with the most stands around the tile."""
    big = box.buffer(CLOSE_M * 4)
    angs = [an for x, y, _, an in stands if big.contains(shapely.Point(x, y))]
    return max(set(angs), key=angs.count) if angs else 0.0


def make_tile(tx, ty, polys, lines, stands, force):
    dst = OUT / f"{tx}_{ty}.png"
    if dst.exists() and not force:
        return -1
    S = c.TILE_SIZE
    box = shapely.box(tx * S - 40, ty * S - 40, (tx + 1) * S + 40, (ty + 1) * S + 40)
    pp = [(g.intersection(box), k, an, pad) for g, k, an, pad in polys if g.intersects(box)]
    ll = [g.intersection(box) for g in lines if g.intersects(box)]
    pp = [p for p in pp if not p[0].is_empty]
    ll = [g for g in ll if not g.is_empty]
    if not pp and not ll:
        return 0
    fill = apron_fill(box, polys, lines, stands)
    if fill is not None:
        pp.append((fill, CONCRETE, fill_angle(box, stands), True))
    allg = shapely.union_all([p[0] for p in pp] + ll)
    shapely.prepare(allg)
    xs, ys = pr.centres(tx, ty, S)
    sd, inside = pr.edge_field(allg, xs, ys)
    # surface and slab direction: shoulders first (asphalt), stand pads, then OSM areas over them, smaller ones last
    surf_img = Image.new("L", (pr.RN, pr.RN), 0)
    ang_img = Image.new("L", (pr.RN, pr.RN), 0)
    ds, da = ImageDraw.Draw(surf_img), ImageDraw.Draw(ang_img)
    tp = lambda ring: [((x - tx * S) / pr.RES, (y - ty * S) / pr.RES) for x, y in ring.coords]

    def draw(g, kind, ab):
        for part in getattr(g, "geoms", [g]):
            if part.geom_type == "Polygon":
                ds.polygon(tp(part.exterior), fill=kind)
                da.polygon(tp(part.exterior), fill=ab)
                for hole in part.interiors:
                    ds.polygon(tp(hole), fill=0)
    for g in ll:
        draw(g, ASPH, 0)
    for g, kind, an, _ in sorted(pp, key=lambda p: (not p[3], -p[0].area)):
        draw(g, kind, int(an / (math.pi / 2) * 256) % 256)
    surf = np.asarray(surf_img)
    # texels just outside the edge take the neighbouring surface, so the filtered edge has a material to fade to
    surf = np.where((surf == 0) & (sd < 8.0), grey_dilation(surf, size=5), surf)
    near = [s for s in stands if box.buffer(80).contains(shapely.Point(s[0], s[1]))]
    d_lat, wear = pr.stand_fields(near, xs, ys)
    arr = pr.encode(sd, d_lat, np.asarray(ang_img), surf, wear)
    Image.fromarray(arr, "RGBA").save(dst, optimize=True)
    return dst.stat().st_size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--refresh-osm", action="store_true")
    ap.add_argument("--only", help="comma list of tx_ty tiles")
    args = ap.parse_args()
    t0 = time.time()
    if args.refresh_osm:
        osm_areas(True)
    polys, lines, stands = features()
    print(f"{len(polys)} paved areas ({sum(1 for p in polys if p[1] == ASPH)} asphalt), {len(lines)} ribbons, "
          f"{len(stands)} stands [{time.time() - t0:.0f} s]")
    S = c.TILE_SIZE
    tiles = set()
    for g in [p[0] for p in polys] + lines:
        x0, y0, x1, y1 = g.bounds
        for tx in range(math.floor((x0 - 40) / S), math.floor((x1 + 40) / S) + 1):
            for ty in range(math.floor((y0 - 40) / S), math.floor((y1 + 40) / S) + 1):
                tiles.add((tx, ty))
    if args.only:
        tiles &= {tuple(map(int, t.split("_"))) for t in args.only.split(",")}
    OUT.mkdir(parents=True, exist_ok=True)
    sizes = [make_tile(tx, ty, polys, lines, stands, args.force) for tx, ty in sorted(tiles)]
    print(f"pavement tiles: {sum(1 for s in sizes if s > 0)} written, {sum(1 for s in sizes if s < 0)} kept, "
          f"{sum(1 for s in sizes if s == 0)} empty [{time.time() - t0:.0f} s]")


if __name__ == "__main__":
    main()
