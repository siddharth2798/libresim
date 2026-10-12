"""Runway marks for logo option 05: the start of a runway as seen from the approach end (512 x 512 box).

Real markings: white edge lines, threshold "piano keys" in two groups split by the centreline, the runway
designator, and centreline dashes. A: the designator row reads "09/27" (chart style). B: both ends of the
runway, "09" upright at the bottom threshold and "27" turned round at the top one, as a pilot sees each end.
"""
from logo_options_marks_b import THEMES_5
from logo_options_text import glyph_bounds, load, text_path, width

TILE_R = 104
CLIP = f'<clipPath id="rwy"><rect width="512" height="512" rx="{TILE_R}"/></clipPath>'


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


def _label(t, text, top, size, max_w=None, flip=False):
    """Amber designator with the top of its digits at y=top; flip turns it 180 degrees about its own centre."""
    f = load("fira", "SemiBold")
    if max_w:
        size = min(size, size * max_w / width(f, text, size, size * 0.03))
    h = glyph_bounds(f, "0", size)[3]
    svg, _ = text_path(f, text, size, 256, top + h, t["accent"], "middle", track=size * 0.03)
    if flip:
        svg = f'<g transform="rotate(180 256 {top + h / 2:.1f})">{svg}</g>'
    return svg


def _tile(t, body):
    return (f'<defs>{CLIP}</defs><g clip-path="url(#rwy)"><rect width="512" height="512" fill="{t["tile"]}"/>'
            f'{_edges(t)}{body}</g>')


def mark_5a(t):
    """Threshold at the bottom, "09/27" across the runway, centreline dashes running away."""
    body = (_dash(t, 40) + _dash(t, 136) + _label(t, "09/27", 254, 120, max_w=292) + _keys(t, 388, 68))
    return _tile(t, body)


def mark_5b(t):
    """Both ends: 27 (turned round) with its threshold at the top, 09 with its threshold at the bottom."""
    body = (_keys(t, 56, 56) + _label(t, "27", 136, 112, flip=True) + _dash(t, 231, 50)
            + _label(t, "09", 299, 112) + _keys(t, 400, 56))
    return _tile(t, body)


__all__ = ["THEMES_5", "mark_5a", "mark_5b"]
