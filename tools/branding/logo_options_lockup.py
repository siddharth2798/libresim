"""Option record and the standard horizontal lockup (mark + "libresim" + tagline) for the logo options."""
from dataclasses import dataclass, field
from typing import Callable, Optional

from logo_options_shapes import g
from logo_options_text import ascender_px, glyph_bounds, load, text_path, width

TAGLINE = "an open-source flight simulator"
WORD = "libresim"


@dataclass
class Option:
    num: int
    slug: str
    name: str
    concept: str
    colours: str
    font: str                      # human-readable font + licence, for the README
    themes: dict
    primary: str                   # theme used for logo.svg / mark.svg ("light" or "dark")
    mark: Callable                 # mark(theme) -> SVG fragment in a 512 x 512 box
    word: tuple = ("opensans", "SemiBold")
    tag: tuple = ("opensans", "Regular")
    word_size: float = 108.0
    track: float = 0.0             # wordmark tracking in em
    mark_size: float = 208.0       # mark height inside the lockup, px
    mark_bg: bool = False          # glyph-only mark: render mark.png on the theme background
    custom: Optional[Callable] = None   # custom(option, theme) -> (w, h, body) replaces the standard lockup
    extra: dict = field(default_factory=dict)


def tagline(opt, t, x, base_y, target_w, max_size):
    """Tagline set in the muted colour, tracked so that it is as wide as the wordmark. Returns (svg, size, asc)."""
    tf = load(*opt.tag)
    n = len(TAGLINE) - 1
    size = min(max_size, target_w / (width(tf, TAGLINE, 1.0) + 0.05 * n))
    lsb = glyph_bounds(tf, TAGLINE[0], size)[0]
    svg, _ = text_path(tf, TAGLINE, size, x - lsb, base_y, t["muted"], track=0.05 * size)
    return svg, size, ascender_px(tf, size)


def horizontal(opt, t):
    pad, gap = 40.0, 46.0
    h = opt.mark_size + 2 * pad
    wf, S = load(*opt.word), opt.word_size
    tr = opt.track * S
    ww = width(wf, WORD, S, tr)
    asc = ascender_px(wf, S)
    t_asc = 0.72 * S * 0.2
    gap_t = S * 0.27
    base = h / 2 - (asc + gap_t + t_asc) / 2 + asc
    x = pad + opt.mark_size + gap
    lsb = glyph_bounds(wf, "l", S)[0]
    word, _ = text_path(wf, WORD, S, x - lsb, base, t["ink"], track=tr)
    tag, _, _ = tagline(opt, t, x, base + gap_t + t_asc, ww, S * 0.2)
    mark = g(opt.mark(t), pad, h / 2 - opt.mark_size / 2, opt.mark_size / 512)
    return round(x + ww + pad), round(h), f"{mark}{word}{tag}"


def lockup(opt, t):
    return (opt.custom or (lambda o, th: horizontal(o, th)))(opt, t)
