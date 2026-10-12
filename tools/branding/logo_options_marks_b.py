"""Logo options 5-8: mark geometry (512 x 512 box) and palettes. Each mark(t) takes a theme dict."""
from logo_options_shapes import g, plane_swept, swept_bbox
from logo_options_text import ascender_px, glyph_bounds, load, text_path, width

# ---- 05 runway 09: threshold piano keys + designator (asphalt black, white, one amber accent) ----
AMBER = "#ffb81c"
THEMES_5 = {
    "light": dict(bg="#ffffff", ink="#16191d", muted="#6b7280", tile="#16191d", mark="#ffffff", accent=AMBER),
    "dark": dict(bg="#0d0f12", ink="#ffffff", muted="#8b93a0", tile="#262c33", mark="#ffffff", accent=AMBER),
}


def mark_5(t):
    f = load("fira", "SemiBold")
    num, _ = text_path(f, "09", 224, 256, 262, t["accent"], "middle", track=8)
    keys, x = [], 96
    for i in range(8):
        keys.append(f'<rect x="{x}" y="318" width="26" height="86" rx="3" fill="{t["mark"]}"/>')
        x += 26 + 12 + (40 if i == 3 else 0)
    return f'<rect width="512" height="512" rx="104" fill="{t["tile"]}"/>{num}{"".join(keys)}'


# ---- 06 monogram "ls" sliced by a horizon (teal + white) -------------------------------------
TEAL = "#0f6b6f"
THEMES_6 = {
    "light": dict(bg="#ffffff", ink=TEAL, muted="#6b7f82", tile=TEAL, mark="#ffffff"),
    "dark": dict(bg="#071a1c", ink="#ffffff", muted="#86a3a6", tile=TEAL, mark="#ffffff"),
}


def mark_6(t):
    f = load("opensans", "ExtraBold")
    size = 400
    w = width(f, "ls", size, -6)
    asc = ascender_px(f, size)
    x0, base = 256 - w / 2, 256 + asc / 2
    word, _ = text_path(f, "ls", size, x0, base, t["mark"], track=-6)
    lx = glyph_bounds(f, "l", size)
    top = base - asc - 2
    bevel = f'M{x0 + lx[0] - 2:.1f} {top:.1f} L{x0 + lx[2] + 2:.1f} {top:.1f} L{x0 + lx[0] - 2:.1f} {top + 52:.1f} Z'
    return f'<rect width="512" height="512" rx="104" fill="{t["tile"]}"/>{word}<path d="{bevel}" fill="{t["tile"]}"/>'


# ---- 07 wordmark with a plane for the dot of the i (ink + one red accent) --------------------
RED = "#e8452c"
THEMES_7 = {
    "light": dict(bg="#ffffff", ink="#1c1c20", muted="#6b6b75", tile="#1c1c20", mark="#ffffff", accent=RED),
    "dark": dict(bg="#121215", ink="#f4f4f6", muted="#8b8b97", tile="#2a2a30", mark="#ffffff", accent=RED),
}


def mark_7(t):
    f = load("fira", "Medium")
    size = 400
    xmin, _, xmax, xh = glyph_bounds(f, "ı", size)
    top = 256 - (xh + 0.12 * size + 100) / 2     # block: stem + gap + plane
    base = top + 100 + 0.12 * size + xh
    stem, _ = text_path(f, "ı", size, 256 - (xmin + xmax) / 2, base, t["mark"])
    plane = g(plane_swept(t["accent"], 134), 256, top + 50, 1.0, 40)
    return f'<rect width="512" height="512" rx="104" fill="{t["tile"]}"/>{stem}{plane}'


# ---- 08 paper plane + dotted flight path (indigo) ---------------------------------------------
INDIGO = "#3a3fa6"
THEMES_8 = {
    "light": dict(bg="#ffffff", ink="#262a6b", muted="#6c6f93", f1=INDIGO, f2="#2b2f84", f3="#1d2063", path="#9ea2dd"),
    "dark": dict(bg="#101226", ink="#f1f2ff", muted="#8c8fb5", f1="#aab0ff", f2="#7f86ee", f3="#5a61cc", path="#4a4f9c"),
}


def mark_8(t):
    plane = (f'<path d="M110 0 L-70 -62 L-34 6 Z" fill="{t["f1"]}"/>'
             f'<path d="M110 0 L-34 6 L-70 62 Z" fill="{t["f2"]}"/>'
             f'<path d="M-34 6 L-70 62 L4 26 Z" fill="{t["f3"]}"/>')
    path = "M54 456 C 150 476 232 430 238 366 C 244 312 296 304 330 262"
    return (f'<path d="{path}" fill="none" stroke="{t["path"]}" stroke-width="15" stroke-linecap="round" '
            f'stroke-dasharray="0 31"/>' + g(plane, 366, 196, 1.45, -44))


def lockup_7(opt, t):
    """Wordmark-only lockup: the dot of the i is a small aircraft, tagline justified underneath."""
    from logo_options_lockup import WORD, tagline
    from logo_options_text import glyph_path, layout
    f, S = load(*opt.word), opt.word_size
    tr = opt.track * S
    items, ww = layout(f, WORD, S, tr)
    asc = ascender_px(f, S)
    pad = 56.0
    gap_t = S * 0.30
    t_asc = 0.72 * S * 0.2
    base = pad + asc
    h = base + gap_t + t_asc + pad
    x0 = pad - glyph_bounds(f, "l", S)[0]
    word, _ = text_path(f, WORD, S, x0, base, t["ink"], track=tr, skip=(1,))
    ox = next(o for c, o, _ in items if c == "i")
    xmin, _, xmax, xh = glyph_bounds(f, "ı", S)
    stem = f'<path d="{glyph_path(f, chr(0x131), S, x0 + ox, base)}" fill="{t["ink"]}"/>'
    plen = 0.30 * S
    cx = x0 + ox + (xmin + xmax) / 2
    bx0, by0, bx1, by1 = swept_bbox(plen, 40)
    plane = g(plane_swept(t["accent"], plen), cx - (bx0 + bx1) / 2, base - xh - 0.075 * S - by1, 1.0, 40)
    tag, _, _ = tagline(opt, t, pad, base + gap_t + t_asc, ww, S * 0.2)
    return round(pad * 2 + ww), round(h), f"{word}{stem}{plane}{tag}"
