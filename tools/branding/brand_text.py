"""Text helpers for the libresim logo: font loading, glyph layout and text converted to SVG outlines.

The wordmark and the runway designator use Fira Sans (SIL OFL 1.1; the OTFs in
/usr/share/fonts/opentype/fira are used), converted to outlines, so the SVGs need no fonts and none is shipped.
"""
from functools import lru_cache

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FIRA = "/usr/share/fonts/opentype/fira/FiraSans-{}.otf"

FAMILIES = {"fira": FIRA}


@lru_cache(maxsize=None)
def load(family: str, weight: str) -> TTFont:
    return TTFont(FAMILIES[family].format(weight))


def _num(v: float) -> str:
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def layout(font: TTFont, text: str, size: float, track: float = 0.0):
    """Per-character pen offsets. Returns ([(char, x_offset, advance)], total_width). Tracking in px."""
    cmap, upm = font.getBestCmap(), font["head"].unitsPerEm
    s = size / upm
    out, x = [], 0.0
    for c in text:
        adv = font["hmtx"][cmap[ord(c)]][0] * s
        out.append((c, x, adv))
        x += adv + track
    return out, x - track


def width(font: TTFont, text: str, size: float, track: float = 0.0) -> float:
    return layout(font, text, size, track)[1]


def glyph_bounds(font: TTFont, ch: str, size: float):
    """(xmin, ymin, xmax, ymax) of a glyph in px, y up, relative to its origin."""
    gs, cmap = font.getGlyphSet(), font.getBestCmap()
    bp = BoundsPen(gs)
    gs[cmap[ord(ch)]].draw(bp)
    s = size / font["head"].unitsPerEm
    return tuple(v * s for v in bp.bounds)


def ascender_px(font: TTFont, size: float) -> float:
    """Height of the letter 'l' above the baseline."""
    return glyph_bounds(font, "l", size)[3]


def xheight_px(font: TTFont, size: float) -> float:
    return glyph_bounds(font, "x", size)[3]


def glyph_path(font: TTFont, ch: str, size: float, x: float, y: float) -> str:
    """Path data for one glyph with its origin at (x, y) (baseline, y down)."""
    gs, cmap = font.getGlyphSet(), font.getBestCmap()
    s = size / font["head"].unitsPerEm
    pen = SVGPathPen(gs, ntos=_num)
    gs[cmap[ord(ch)]].draw(TransformPen(pen, (s, 0, 0, -s, x, y)))
    return pen.getCommands()


def text_path(font: TTFont, text: str, size: float, x: float, y: float, fill: str,
              anchor: str = "start", track: float = 0.0, skip=(), extra: str = ""):
    """One <path> for the whole string (baseline at y). Character indices in `skip` are laid out but not drawn.
    Returns (svg, width)."""
    items, w = layout(font, text, size, track)
    x0 = x - (w / 2 if anchor == "middle" else (w if anchor == "end" else 0))
    d = " ".join(glyph_path(font, c, size, x0 + ox, y) for i, (c, ox, _) in enumerate(items) if c != " " and i not in skip)
    return f'<path d="{d}" fill="{fill}"{extra}/>', w
