"""Per-airport recipes that turn OSM terminal footprints into landmark models that look
like the real buildings (research notes in docs/TERMINALS.md):

  VABB T2  SOM 2014: glazed headhouse under one long white-grey roof on ~30 m
           mushroom columns, 40 m cantilever over the departures kerb, lit coffered
           soffit; lower glazed piers with white jali bands.
  VABB T1  low 1B/1C blocks: glass + metal cladding, flat roofs, kerb canopies.
  VAPO     new integrated terminal + old terminal joined by the long "verandah"
           canopy with dark basalt columns; cream cladding, flat metal roofs.
  VOCI     Kerala temple style: terracotta hip roofs in sections with white gablets,
           cream walls, grey glazing bands, red fascia + pylons, "COCHIN INTERNATIONAL
           AIRPORT" lettering (T3); T1 / T2 in the same idiom, lower.

Heights are not tagged in OSM; they come from published level heights (Kochi T3:
floors at 0 / 5.5 / 10.5 / 15.5 m; Mumbai T2: ~36-42 m roof, 30 m columns).
"""
import math

import numpy as np
from shapely.geometry import Polygon, LineString, box as sbox
from shapely import affinity

import terminal_geom as tg

GLASS = (0.42, 0.52, 0.55)
GLASS_GREY = (0.33, 0.37, 0.4)
WHITE = (0.9, 0.9, 0.88)
SILVER = (0.72, 0.74, 0.76)
ROOF_GREY = (0.74, 0.75, 0.76)
CREAM = (0.9, 0.86, 0.75)
TERRACOTTA = (0.42, 0.16, 0.1)
RED = (0.62, 0.13, 0.1)
BASALT = (0.22, 0.21, 0.2)
CONCRETE = (0.6, 0.59, 0.56)


def split_core(poly, r):
    """Thick central mass (headhouse) vs. thin arms (piers), by morphological opening."""
    core = poly.buffer(-r).buffer(r).intersection(poly)
    arms = poly.difference(core.buffer(0.5))
    arms = [p for p in tg.polys(arms) if p.area > 400.0]
    return max(tg.polys(core), key=lambda p: p.area, default=None), arms


def landside_dir(poly, ctx):
    """Unit vector from the airside (jet bridges) toward the landside."""
    c = np.asarray(poly.centroid.coords[0])
    jb = [np.mean(j["line"], 0) for j in ctx["jet_bridges"]
          if np.linalg.norm(np.mean(j["line"], 0) - c) < 700.0]
    if not jb:
        return np.array([0.0, -1.0])
    d = c - np.mean(jb, 0)
    return d / (np.linalg.norm(d) or 1.0)


def kerb_band(core, d, depth):
    """The strip of a depth-wide buffer around the core that faces direction d."""
    c = np.asarray(core.centroid.coords[0])
    ring = core.buffer(depth, join_style=2).difference(core)
    proj = [np.dot(np.asarray(p) - c, d) for p in core.exterior.coords]
    k = max(proj) * 0.35
    big = 5000.0
    perp = np.array([-d[1], d[0]])
    half = Polygon([c + d * k + perp * big, c + d * k - perp * big, c + d * big - perp * big, c + d * big + perp * big])
    return ring.intersection(half)


def glazed_block(g, poly, z_glass, z_top, roof_z, glass=GLASS, panel=WHITE, roof=ROOF_GREY, overhang=3.0,
                 mullion=1.8, roof_mat="roof_metal"):
    tg.walls(g, f"glass@{mullion}", poly, 0.0, z_glass, glass)
    if z_top > z_glass:
        tg.walls(g, "panel", poly, z_glass, z_top, panel)
    tg.cap(g, "concrete", poly, z_top, True, CONCRETE)
    tg.slab(g, roof_mat, poly.buffer(overhang, join_style=2), z_top, roof_z, roof)


def columns_along(g, mat, geom, spacing, z0, z1, r0, r1, color, inset=4.0):
    for p in tg.polys(geom):
        ring = p.buffer(-inset).exterior if p.buffer(-inset).area > 0 else p.exterior
        n = max(int(ring.length / spacing), 1)
        for i in range(n):
            q = ring.interpolate(i * ring.length / n)
            tg.column(g, mat, q.x, q.y, z0, z1, r0, r1, color)


def strips(poly, n_target_len):
    """Cut a footprint across its long axis into pieces ~n_target_len long."""
    c, ax, L, W = tg.mrr(poly)
    n = max(int(round(L / n_target_len)), 1)
    out = []
    for i in range(n):
        u0 = -L / 2 + L * i / n
        cell = tg.rect_poly(c + ax * (u0 + L / n / 2), ax, L / n + 0.2, W + 10)
        out += [p for p in tg.polys(poly.intersection(cell)) if p.area > 300.0]
    return out


def kerala_roofs(g, poly, eave, piece_len, pitch_deg=28.0, overhang=4.0, max_rise=13.0):
    for p in strips(poly, piece_len):
        c, ax, L, W = tg.mrr(p)
        rise = min(math.tan(math.radians(pitch_deg)) * (W / 2 + overhang), max_rise)
        tg.hip_roof(g, "roof_tile", c, ax, L + 2 * overhang, W + 2 * overhang, eave, rise, TERRACOTTA, gablet=0.3)
        tg.cap(g, "soffit", tg.rect_poly(c, ax, L + 2 * overhang, W + 2 * overhang), eave, False, CREAM)


def elevated_roads(g, ctx, near, max_dist=500.0):
    for r in ctx["elevated_roads"]:
        line = LineString(r["line"])
        if line.distance(near) > max_dist:
            continue
        hw = {"motorway": 7.5, "trunk": 7.0, "primary": 6.5}.get(r["tags"].get("highway"), 4.5)
        z = min(6.5 * max(int(r["tags"].get("layer", "1") or 1), 1), 14.0)
        deck = line.buffer(hw, cap_style=2)
        tg.slab(g, "concrete", deck, z - 1.4, z, CONCRETE)
        tg.walls(g, "concrete", deck, z, z + 1.1, CONCRETE)  # parapets
        for i in range(int(line.length // 32.0) + 1):
            q = line.interpolate(i * 32.0)
            tg.column(g, "column", q.x, q.y, 0.0, z - 1.4, 1.1, 1.1, CONCRETE, seg=8)


def car_park(g, poly, decks):
    for i in range(decks):
        z = i * 3.2
        tg.slab(g, "concrete", poly, z, z + 0.5, CONCRETE)
        tg.walls(g, "concrete", poly, z + 0.5, z + 1.6, CONCRETE)
        tg.walls(g, "panel", poly.buffer(-2.0), z + 0.5, z + 3.2, (0.22, 0.23, 0.24))  # dark open deck
    tg.slab(g, "concrete", poly, decks * 3.2, decks * 3.2 + 0.5, CONCRETE)


def facing_sign(core, d, text, z, height, color=(1, 1, 1)):
    c, ax, L, W = tg.mrr(core)
    proj = max(np.dot(np.asarray(p) - c, d) for p in core.exterior.coords)
    pos = c + d * (proj + 0.8)
    return {"text": text, "pos": [float(pos[0]), float(pos[1]), z], "height": height,
            "heading_deg": float(math.degrees(math.atan2(d[0], d[1])) % 360.0), "color": list(color)}


# ---------------------------------------------------------------- airports

def vabb(g, ctx):
    t2, t1 = ctx["by_osm"]["way/315613914"], ctx["by_osm"]["way/61569813"]
    core, arms = split_core(t2, 70.0)
    d = landside_dir(core, ctx)
    for a in arms:  # piers: glazing, white jali band, flat roof
        glazed_block(g, a, 14.0, 20.0, 21.5, GLASS, WHITE, ROOF_GREY, 2.5, 2.4)
    glazed_block(g, core, 26.0, 30.0, 30.0, GLASS, WHITE, ROOF_GREY, 0.0, 3.0)
    canopy = core.buffer(6.0, join_style=2).union(kerb_band(core, d, 40.0))
    tg.cap(g, "roof_metal", canopy, 34.0, True, ROOF_GREY)
    tg.cap(g, "soffit", canopy, 31.0, False, WHITE)
    tg.walls(g, "panel", canopy, 31.0, 34.0, SILVER)
    columns_along(g, "column", kerb_band(core, d, 40.0), 34.0, 0.0, 31.0, 1.4, 3.8, WHITE, 8.0)
    c, ax, L, W = tg.mrr(core)  # skylight ribs across the roof
    for k in range(-3, 4):
        tg.box(g, "glass@1.5", c + np.array([-ax[1], ax[0]]) * k * 34.0, ax, L * 0.8, 4.0, 34.0, 35.2, GLASS)
    core1, arms1 = split_core(t1, 40.0)
    for a in arms1:
        glazed_block(g, a, 8.0, 12.0, 13.0, GLASS_GREY, SILVER, ROOF_GREY, 1.5, 1.8)
    if core1 is not None:
        glazed_block(g, core1, 10.0, 16.0, 17.5, GLASS_GREY, SILVER, ROOF_GREY, 2.0, 1.8)
    for p in ctx["parts"]:
        if p["osm"] in ("way/569614980", "way/569614982"):
            z = 8.5 if p["tags"].get("layer") == "1" else 13.5
            poly = ctx["poly"](p)
            tg.slab(g, "roof_metal", poly, z, z + 1.0, SILVER)
            columns_along(g, "column", poly, 12.0, 0.0, z, 0.4, 0.4, SILVER, 1.5)
    for cp in ctx["car_parks"]:
        car_park(g, ctx["poly"](cp), 5)
    elevated_roads(g, ctx, t2.union(t1))
    return [t2, t1] + [ctx["poly"](cp) for cp in ctx["car_parks"]], []


def vapo(g, ctx):
    new, old = ctx["by_osm"]["way/1154418126"], ctx["by_osm"]["way/69366490"]
    both = new.union(old)
    d = landside_dir(both, ctx)
    glazed_block(g, new, 9.0, 17.0, 18.5, GLASS_GREY, CREAM, ROOF_GREY, 4.0, 2.0)
    glazed_block(g, old, 6.0, 12.0, 13.0, GLASS_GREY, CREAM, ROOF_GREY, 2.0, 1.6)
    hull = both.buffer(30.0).buffer(-30.0)  # one verandah ties both buildings together
    verandah = kerb_band(hull, d, 16.0)
    tg.slab(g, "roof_metal", verandah, 12.0, 13.2, ROOF_GREY, edge_mat="panel")
    tg.walls(g, "panel", verandah, 13.2, 15.5, CREAM)  # deep fascia
    # Maratha-style pointed arcade in dark basalt along the outer edge (Shaniwar Wada motif)
    c = np.asarray(hull.centroid.coords[0])
    k = max(np.dot(np.asarray(p) - c, d) for p in hull.exterior.coords) * 0.35 + 10.0
    ring = hull.buffer(14.0, join_style=2).exterior
    pts = [np.asarray(ring.interpolate(s).coords[0]) for s in np.arange(0.0, ring.length, 9.0)]
    keep = [p for p in pts if np.dot(p - c, d) > k]
    for p in keep:
        tg.column(g, "column", p[0], p[1], 0.0, 12.0, 0.8, 0.8, BASALT, seg=8)
    for p, q in zip(keep, keep[1:]):
        if np.linalg.norm(q - p) < 12.0:
            tg.arch_panel(g, "panel", p, q, 6.5, 12.0, BASALT)
    for cp in ctx["car_parks"]:
        car_park(g, ctx["poly"](cp), 4)
    return [new, old] + [ctx["poly"](cp) for cp in ctx["car_parks"]], []


def voci(g, ctx):
    t3 = ctx["by_osm"]["way/452201953"]
    t1, t2 = ctx["by_osm"]["way/254109738"], ctx["by_osm"]["way/254109742"]
    core, arms = split_core(t3, 50.0)
    d = landside_dir(core, ctx)
    for a in arms:
        tg.walls(g, "glass@2.0", a, 0.0, 8.0, GLASS_GREY)
        tg.walls(g, "panel", a, 8.0, 11.0, CREAM)
        kerala_roofs(g, a, 11.0, 60.0, 26.0, 3.0, 8.0)
    tg.walls(g, "glass@2.2", core, 0.0, 5.5, GLASS_GREY)
    tg.walls(g, "panel", core, 5.5, 10.5, CREAM)
    tg.walls(g, "glass@2.2", core, 10.5, 15.5, GLASS_GREY)
    tg.walls(g, "panel", core, 15.5, 17.0, CREAM)
    kerala_roofs(g, core, 17.0, 75.0, 30.0, 6.0, 15.0)
    c, ax, L, W = tg.mrr(core)  # red fascia band and end pylons on the landside face
    perp = d
    proj = max(np.dot(np.asarray(p) - c, perp) for p in core.exterior.coords)
    along = np.array([-perp[1], perp[0]])
    face_c = c + perp * (proj + 2.0)
    tg.box(g, "panel", face_c, along, 120.0, 2.0, 11.0, 15.0, RED)
    for s in (-1, 1):
        tg.box(g, "panel", face_c + along * s * 140.0, along, 10.0, 6.0, 0.0, 20.0, TERRACOTTA)
    signs = [facing_sign(core, d, "COCHIN INTERNATIONAL AIRPORT", 13.0, 2.6)]
    for s in (-1, 1):
        p = face_c + along * s * 140.0 + perp * 3.1
        signs.append({"text": "TERMINAL 3", "pos": [float(p[0]), float(p[1]), 17.0], "height": 1.6,
                      "heading_deg": signs[0]["heading_deg"], "color": [1, 1, 1]})
    for t in (t1, t2):
        tg.walls(g, "glass@1.8", t, 0.0, 5.0, GLASS_GREY)
        tg.walls(g, "panel", t, 5.0, 9.0, CREAM)
        kerala_roofs(g, t, 9.0, 50.0, 28.0, 3.5, 9.0)
    elevated_roads(g, ctx, t3, 300.0)
    return [t3, t1, t2], signs


RECIPES = {"VABB": vabb, "VAPO": vapo, "VOCI": voci}
