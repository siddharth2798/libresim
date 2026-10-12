"""The libresim mark: the start of a runway as a pilot sees it on final (512 x 512 box).

White edge lines, threshold "piano keys" in two groups split by the centreline, the amber designator
"09/27" (runway 09 one way, 27 the other, as on charts) and centreline dashes running away, on an
asphalt tile with rounded corners. Two themes: "light" (asphalt tile, for light backgrounds and icons)
and "dark" (lighter tile, for dark backgrounds).
"""
from brand_text import glyph_bounds, load, text_path, width

AMBER = "#ffb81c"
THEMES = {
    "light": dict(bg="#ffffff", ink="#16191d", muted="#6b7280", tile="#16191d", mark="#ffffff", accent=AMBER),
    "dark": dict(bg="#0d0f12", ink="#ffffff", muted="#8b93a0", tile="#262c33", mark="#ffffff", accent=AMBER),
}
TILE_R = 104
CLIP = f'<clipPath id="rwy"><rect width="512" height="512" rx="{TILE_R}"/></clipPath>'


def svg_doc(w, h, body, bg=None):
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{rect}{body}</svg>\n'


def place(body, x=0.0, y=0.0, scale=1.0):
    return f'<g transform="translate({x:.2f} {y:.2f}) scale({scale:.4f})">{body}</g>'


def _keys(t, y, h):
    """Threshold stripes: 8 bars in two groups of 4, gap in the middle for the centreline."""
    out, x = [], 91.0
    for i in range(8):
        out.append(f'<rect x="{x:.1f}" y="{y}" width="24" height="{h}" rx="3" fill="{t["mark"]}"/>')
        x += 24 + 14 + (40 if i == 3 else 0)
    return "".join(out)


def _edges(t):
    return "".join(f'<rect x="{x}" y="0" width="8" height="512" fill="{t["mark"]}" opacity="0.9"/>' for x in (66, 438))


def _dash(t, y, h=56):
    return f'<rect x="247" y="{y}" width="18" height="{h}" rx="2" fill="{t["mark"]}"/>'


def _label(t, text, top, size, max_w):
    """Amber designator with the top of its digits at y=top, fitted to max_w."""
    f = load("fira", "SemiBold")
    size = min(size, size * max_w / width(f, text, size, size * 0.03))
    h = glyph_bounds(f, "0", size)[3]
    return text_path(f, text, size, 256, top + h, t["accent"], "middle", track=size * 0.03)[0]


def mark(t):
    """SVG fragment in a 512 x 512 box. Threshold at the bottom, "09/27" across, dashes running away."""
    body = _dash(t, 40) + _dash(t, 136) + _label(t, "09/27", 254, 120, 292) + _keys(t, 388, 68)
    return (f'<defs>{CLIP}</defs><g clip-path="url(#rwy)"><rect width="512" height="512" fill="{t["tile"]}"/>'
            f'{_edges(t)}{body}</g>')
