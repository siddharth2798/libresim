"""Logo options 1-4: mark geometry (512 x 512 box) and palettes. Each mark(t) takes a theme dict."""
from logo_options_shapes import c172_side, g

# ---- 01 badge: C172 in a circle (navy + white, one orange accent) -------------------------------
NAVY, ORANGE = "#12355f", "#f26b1d"
THEMES_1 = {
    "light": dict(bg="#ffffff", ink=NAVY, muted="#6b7a90", disc=NAVY, disc2="#1b4577", plane="#ffffff", accent=ORANGE),
    "dark": dict(bg="#0a1a2e", ink="#ffffff", muted="#8fa1b8", disc="#f4f7fb", disc2="#dbe4ee", plane=NAVY, accent=ORANGE),
}


def mark_1(t):
    clip = '<clipPath id="d1"><circle cx="256" cy="256" r="244"/></clipPath>'
    return (f'<defs>{clip}</defs><circle cx="256" cy="256" r="244" fill="{t["disc"]}"/>'
            f'<g clip-path="url(#d1)"><rect x="0" y="352" width="512" height="160" fill="{t["disc2"]}"/></g>'
            f'<circle cx="256" cy="256" r="224" fill="none" stroke="{t["plane"]}" stroke-width="5" opacity="0.9"/>'
            + g(c172_side(t["plane"], hole=True, accent=t["accent"]), 262, 244, 1.66, -9))


# ---- 02 wing-l: top-view aircraft whose fuselage is the letter l (sky blue + navy) --------------
SKY = "#2a8fe6"
THEMES_2 = {
    "light": dict(bg="#ffffff", ink="#0f2744", muted="#64748b", stem="#0f2744", wing=SKY),
    "dark": dict(bg="#0a1626", ink="#f2f6fb", muted="#8da0b6", stem="#f2f6fb", wing="#4aa8ff"),
}


def mark_2(t):
    fus = "M232 80 A24 24 0 0 1 280 80 L280 384 Q280 410 272 458 L240 458 Q232 410 232 384 Z"
    right = ["M296 214 L468 312 L468 352 L296 300 Z", "M296 392 L378 438 L378 458 L296 438 Z"]
    st = f'fill="{t["wing"]}" stroke="{t["wing"]}" stroke-width="8" stroke-linejoin="round"'
    wings = "".join(f'<path d="{d}" {st}/><path d="{d}" {st} transform="translate(512 0) scale(-1 1)"/>' for d in right)
    return f'<path d="{fus}" fill="{t["stem"]}"/>{wings}'


# ---- 03 climb-out: two horizon lines and an aircraft rotating away (charcoal + orange) ----------------------
CHAR = "#1e242c"
THEMES_3 = {
    "light": dict(bg="#ffffff", ink=CHAR, muted="#6b7280", line=CHAR, plane=ORANGE),
    "dark": dict(bg="#12161b", ink="#f4f4f0", muted="#8b93a0", line="#f4f4f0", plane=ORANGE),
}


def mark_3(t):
    bars = (f'<rect x="36" y="352" width="440" height="24" rx="12" fill="{t["line"]}"/>'
            f'<rect x="190" y="396" width="286" height="24" rx="12" fill="{t["line"]}"/>')
    return bars + g(c172_side(t["plane"], hole=True), 262, 214, 1.5, -14)


# ---- 04 Western Ghats ridge + aircraft (deep green + cream) -------------------------------------
GREEN, CREAM = "#1d5b46", "#f6f0de"
THEMES_4 = {
    "light": dict(bg="#fbf8ef", ink=GREEN, muted="#6f8a7d", disc=GREEN, back="#3f8b70", front="#f6f0de", plane=CREAM),
    "dark": dict(bg="#0c211a", ink=CREAM, muted="#8fb0a2", disc=GREEN, back="#3f8b70", front="#f6f0de", plane=CREAM),
}


def mark_4(t):
    back = "M-10 380 L50 380 L100 300 L170 300 L232 380 L262 380 L320 280 L410 280 L470 360 L522 360 L522 520 L-10 520 Z"
    front = "M-10 450 L60 450 L120 392 L206 392 L256 450 L330 450 L376 400 L452 400 L522 462 L522 520 L-10 520 Z"
    clip = '<clipPath id="d4"><circle cx="256" cy="256" r="222"/></clipPath>'
    return (f'<defs>{clip}</defs><circle cx="256" cy="256" r="244" fill="{t["disc"]}"/>'
            f'<g clip-path="url(#d4)"><path d="{back}" fill="{t["back"]}"/><path d="{front}" fill="{t["front"]}"/></g>'
            f'<circle cx="256" cy="256" r="224" fill="none" stroke="{t["plane"]}" stroke-width="5" opacity="0.9"/>'
            + g(c172_side(t["plane"], hole=True), 268, 172, 1.3, -10))
