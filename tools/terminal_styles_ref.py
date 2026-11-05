"""Landmark recipes driven by the terminal reference data (terminal_ref.py, tools/ref/terminals_reference.json):
heights, glazing and colours come from the researched entry (or its "model" estimates), the plan from OSM.

  VOKN     Kannur 2018: near-square block with a raised, curved central hall. The city-side canopy is 8
           parallel gabled bays (OSM roof parts, roof:shape=gabled) with glazed gable ends over the
           departures kerb, on white columns, with a laterite-red beam and piers along the frontage;
           blue-grey glass and cladding, white metal roofs. OSM tags the whole footprint height=30
           (the ATC tower), which drew a 30 m box.
  generic  any airport whose reference terminal has model.recipe = "generic" (today VOGO): each linked
           OSM footprint as a glazed block (glass to glass_share x eaves, cladding above) under a roof
           of the reference form (model.roof: flat | curved | pitched), in the reference colours.
"""
import numpy as np
from shapely.ops import unary_union

import terminal_geom as tg
import terminal_ref as ref
import terminal_styles as ts

WHITE = (0.92, 0.92, 0.9)


def gable_roof(g, mat, centre, axis, length, width, z, rise, color, end_color, mullion=1.5):
    """Pitched roof along axis (ridge on the long axis) with vertical glazed triangular gable ends."""
    ax = np.asarray(axis, float)
    pe = np.array([-ax[1], ax[0]])
    c = np.asarray(centre, float)
    hl, hw = length / 2, width / 2
    P = lambda u, v, h: (*(c + ax * u + pe * v), h)  # noqa: E731
    e = [P(-hl, -hw, z), P(hl, -hw, z), P(hl, hw, z), P(-hl, hw, z)]
    r0, r1 = P(-hl, 0, z + rise), P(hl, 0, z + rise)
    tg._tri_face(g, mat, [e[0], e[1], r1, r0], color)
    tg._tri_face(g, mat, [e[2], e[3], r0, r1], color)
    for tri in ([e[3], e[0], r0], [e[1], e[2], r1]):
        tg._tri_face(g, f"glass@{mullion}", tri, end_color)
        tg._tri_face(g, f"glass@{mullion}", tri[::-1], end_color)  # seen from inside the canopy too


def hall_rect(body, band, d):
    """Central hall: the canopy band's width, from the band's inner edge to 60 % of the way across the body."""
    c, ax, L, W = tg.mrr(band)
    along = ax if abs(np.dot(ax, d)) < 0.5 else np.array([-ax[1], ax[0]])
    span = L if along is ax else W
    proj = [np.dot(np.asarray(p) - c, d) for p in body.exterior.coords]
    inner = min(proj)
    band_in = min(np.dot(np.asarray(p) - c, d) for p in band.exterior.coords)
    depth = (band_in - inner) * 0.6
    mid = c + d * (band_in - depth / 2)
    return tg.rect_poly(mid, along, span * 0.92, depth).intersection(body), along, span * 0.92, depth, mid


def vokn(g, ctx):
    osm = "way/392012106"
    t = ref.terminal("VOKN", osm)
    body = ctx["by_osm"][osm]
    eaves, top = ref.ref_heights(t, 14.0, 26.0)
    glass = ref.rgb(t, "glass_hex", ts.GLASS_GREY)
    facade = ref.rgb(t, "facade_colour_hex", (0.37, 0.45, 0.53))
    roof = ref.rgb(t, "roof_colour_hex", ts.ROOF_GREY)
    laterite = ref.rgb(t, "accent_colour_hex", (0.6, 0.24, 0.17))
    soffit = ref.rgb(t, "soffit_colour_hex", (0.29, 0.31, 0.33))
    share = ref.value(t, "glass_share", 0.6)
    gables = [ctx["poly"](p) for p in ctx["parts"] if p["tags"].get("roof:shape") == "gabled"]
    d = ts.landside_dir(body, ctx)
    # main body: glazing to share x eaves, blue-grey cladding above, flat white roof with a small overhang
    ts.glazed_block(g, body, round(eaves * share, 1), eaves, eaves + 1.0, glass, facade, roof, 1.5, 1.8)
    signs = []
    if gables:
        band = unary_union([p.buffer(0.3, join_style=2) for p in gables]).buffer(-0.3, join_style=2)
        hall, along, span, depth, mid = hall_rect(body, band, d)
        hall_eaves = eaves + 2.0  # the hall rises above the wings, its roof curves up toward the city side
        tg.walls(g, "panel", hall, eaves + 1.0, hall_eaves, facade)
        tg.vault(g, "roof_metal", mid, along, span, depth, hall_eaves, (top - hall_eaves) * 0.6, roof)
        z_gable = top - 8.0  # gable rise ~8 m over 19 m bays: ~40 deg, as in photos
        for p in gables:
            c, ax, L, W = tg.mrr(p)
            gable_roof(g, "roof_metal", c, ax, L, W, z_gable, top - z_gable, roof, glass)
        z_soffit = eaves + 1.0
        tg.walls(g, "panel", band, z_soffit, z_gable, soffit)  # deep dark fascia under the gables
        tg.cap(g, "soffit", band, z_soffit, False, soffit)
        kerb = band.difference(body.buffer(1.0))
        ts.columns_along(g, "column", kerb, 19.3, 0.0, z_soffit, 0.7, 0.7, WHITE, 3.0)
        # laterite-red beam and piers along the city-side frontage
        c, ax, L, W = tg.mrr(body)
        proj = max(np.dot(np.asarray(q) - c, d) for q in body.exterior.coords)
        face = c + d * (proj + 0.6)
        per = np.array([-d[1], d[0]])
        tg.box(g, "panel", face, per, span * 0.95, 1.2, eaves - 3.0, eaves - 0.5, laterite)
        for k in range(-4, 5):
            tg.box(g, "panel", face + per * k * span / 9.0, per, 2.4, 1.6, 0.0, eaves - 3.0, laterite)
        signs.append(ts.facing_sign(band, d, "KANNUR INTERNATIONAL AIRPORT", z_soffit + 1.6, 2.4))
    ts.elevated_roads(g, ctx, body, 300.0)
    return [body], signs


def roof_pieces(p, piece=50.0):
    """Oriented rectangles (centre, axis, length, width) covering footprint p: its minimum rectangle
    when p fills 85 % of it, else ~piece-long slices along the long axis, as wide as the footprint there."""
    c, ax, L, W = tg.mrr(p)
    if p.area >= 0.85 * L * W:
        return [(c, ax, L, W)]
    pe = np.array([-ax[1], ax[0]])
    out = []
    for q in ts.strips(p, piece):
        pts = np.asarray(q.exterior.coords) - c
        u, v = pts @ ax, pts @ pe
        out.append((c + ax * (u.max() + u.min()) / 2 + pe * (v.max() + v.min()) / 2, ax,
                    float(np.ptp(u)), float(np.ptp(v))))
    return out


def generic(icao):
    """Data-only recipe: every reference terminal of icao with model.recipe == "generic"."""
    def recipe(g, ctx):
        out = []
        for t in ref.terminals(icao):
            m = t.get("model", {})
            if m.get("recipe") != "generic":
                continue
            eaves, top = ref.ref_heights(t, 10.0, None)
            glass = ref.rgb(t, "glass_hex", ts.GLASS_GREY)
            facade = ref.rgb(t, "facade_colour_hex", ts.WHITE)
            roof = ref.rgb(t, "roof_colour_hex", ts.ROOF_GREY)
            over = float(m.get("overhang_m", 3.0))
            for osm in t.get("osm", []):
                p = ctx["by_osm"].get(osm)
                if p is None:
                    continue
                share = ref.value(t, "glass_share", 0.5)
                ts.glazed_block(g, p, round(eaves * share, 1), eaves, eaves + 0.8, glass, facade, roof, over, 1.8)
                rise = (top or eaves) - eaves - 0.8
                for c, ax, L, W in roof_pieces(p) if rise > 0.5 else []:
                    if m.get("roof") == "curved":
                        tg.vault(g, "roof_metal", c, ax, L + 2 * over, W + 2 * over, eaves + 0.8, rise, roof)
                    elif m.get("roof") == "pitched":
                        tg.hip_roof(g, "roof_tile", c, ax, L + 2 * over, W + 2 * over, eaves + 0.8, rise, roof)
                out.append(p)
        if out:
            ts.elevated_roads(g, ctx, unary_union(out), 300.0)
        return out, []
    return recipe


RECIPES = {"VOKN": vokn}
RECIPES.update({i: generic(i) for i in ref.load() if i not in RECIPES
                and any(t.get("model", {}).get("recipe") == "generic" for t in ref.terminals(i))})
