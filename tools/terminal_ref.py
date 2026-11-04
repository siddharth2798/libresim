"""The researched terminal reference data set (tools/ref/terminals_reference.json, docs/TERMINALS.md §6).

One entry per ICAO: what the field really is, and per passenger terminal the published facts (heights,
storeys, plan, roof form, colours, glazing, jet bridges, status), each with a confidence and sources.
Research values stay null when unknown; "model" holds the values the pipeline builds with when the
research leaves a gap (marked as estimates, with their basis).

Used by
  16_terminal_models.py / terminal_styles*.py  heights and colours of the landmark recipes (ref_heights, rgb)
  10_buildings.py                              terminal_overrides(): height, roof colour and facade look
                                               (cladding colour, glazing share, glass tone) of the generic
                                               extruded footprint of every researched terminal that is not a
                                               landmark (instead of an OSM height tag or the synthetic rule)
"""
import json
from functools import lru_cache
from pathlib import Path

import numpy as np

import common as c

REF = Path(__file__).resolve().parent / "ref" / "terminals_reference.json"
STOREY_M = 4.5  # typical terminal storey (Kochi T3: floors 5 m apart, VOKN / VABB T1 photos)


@lru_cache(maxsize=1)
def load():
    return {a["icao"]: a for a in json.loads(REF.read_text())["airports"]} if REF.exists() else {}


def airport(icao):
    return load().get(icao, {})


def terminals(icao):
    return airport(icao).get("terminals", [])


def terminal(icao, osm):
    """The reference terminal whose "osm" list holds this OSM id ("way/123"), or {}."""
    return next((t for t in terminals(icao) if osm in t.get("osm", [])), {})


def value(t, key, default=None):
    """Researched value, else the pipeline's modelling estimate (t["model"]), else default."""
    v = t.get(key)
    if v is None:
        v = t.get("model", {}).get(key)
    return default if v is None else v


def rgb(t, key, default):
    """'#rrggbb' (researched or model) -> (r, g, b) floats 0..1 in sRGB, else default."""
    h = value(t, key)
    if not h:
        return default
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def ref_heights(t, eaves=None, top=None):
    """(eaves, roof top) in metres above the apron: researched, model, storeys x STOREY_M, or the defaults."""
    st = value(t, "storeys")
    e = value(t, "eaves_m", st * STOREY_M + 1.0 if st else eaves)
    r = value(t, "roof_top_m", top if top is not None else e)
    return e, max(r, e) if r is not None and e is not None else r


def box_height(t):
    """Height of a plain extruded box standing in for the terminal (10_buildings): the eaves when the roof
    rises above them (curved / pitched / folded), else the roof top; None if nothing is known."""
    e, r = ref_heights(t)
    if e is None and r is None:
        return None
    return e if e is not None else r


FACADE_DEFAULT = (0.83, 0.84, 0.84)  # light grey cladding when the research has no facade colour
GLASS_SHARE_DEFAULT = 0.5  # glazed share of the facade (airside fronts are mostly glass)
GLASS_DEFAULT = (0.42, 0.53, 0.58)  # blue-grey glazing (the mean of the researched glass_hex values)


def facade_look(t):
    """(cladding rgb 0..255, glazing share 0..1, glass luminance 0..1) of a terminal's generic facade
    (10_buildings: building.gdshader draws curtain-wall glazing instead of storey windows)."""
    clad = rgb(t, "facade_colour_hex", FACADE_DEFAULT)
    share = float(value(t, "glass_share", GLASS_SHARE_DEFAULT))
    g = rgb(t, "glass_hex", GLASS_DEFAULT)
    return (np.array([round(v * 255) for v in clad]), share, 0.299 * g[0] + 0.587 * g[1] + 0.114 * g[2])


def terminal_overrides():
    """[(matplotlib Path of the OSM footprint, box height m, roof rgb 0..255 or None, facade_look)] for every
    researched terminal with an OSM id found in terminals/<ICAO>.json (15_terminals.py)."""
    from matplotlib.path import Path as MPath
    out = []
    for icao, a in load().items():
        f = c.OUT / "terminals" / f"{icao}.json"
        if not f.exists() or not a.get("terminals"):
            continue
        feats = {t["osm"]: t for t in json.loads(f.read_text()).get("terminals", [])}
        for t in a["terminals"]:
            h = box_height(t)
            col = rgb(t, "roof_colour_hex", None)
            for osm in t.get("osm", []):
                if osm in feats and h is not None:
                    for ring in feats[osm]["outers"]:
                        out.append((MPath(np.asarray(ring)), float(h),
                                    None if col is None else np.array([round(v * 255) for v in col]),
                                    facade_look(t)))
    return out
