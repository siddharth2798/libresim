"""libresim logo: SVGs (mark, lockup, splash) + PNG renders, written to game/branding/.

The mark is a circular badge: a Konkan sunrise (indigo -> magenta -> saffron -> gold sky), the
Western Ghats as layered ridges, and a Cessna-style high-wing aircraft climbing out with a
contrail. The wordmark is "libresim" set in Open Sans ExtraBold (Apache-2.0), converted to
outlines so the SVGs need no fonts. PNGs are rendered by Godot's own SVG loader
(game/branding/rasterize.gd), so no extra tools are required.

    tools/.venv/bin/python tools/branding/make_logo.py
"""
import subprocess
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "game" / "branding"
FONTS = Path("/usr/share/fonts/truetype/open-sans")
BOLD = TTFont(FONTS / "OpenSans-ExtraBold.ttf")
REG = TTFont(FONTS / "OpenSans-Regular.ttf")
GODOT = Path.home() / ".local/bin/godot"

CREAM = "#fff6e6"


def text_paths(font, text, size, x, y, fills, anchor="start", track=0.0):
    """Outline paths for `text`. fills: one colour or a list per character. Returns (svg, width)."""
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    s = size / upm
    adv = [font["hmtx"][cmap[ord(c)]][0] * s + track for c in text]
    width = sum(adv) - track
    cx = x - (width / 2 if anchor == "middle" else (width if anchor == "end" else 0))
    parts = []
    for i, c in enumerate(text):
        if c != " ":
            pen = SVGPathPen(gs)
            gs[cmap[ord(c)]].draw(pen)
            fill = fills[i] if isinstance(fills, list) else fills
            parts.append(f'<path transform="translate({cx:.2f} {y:.2f}) scale({s:.5f} {-s:.5f})" d="{pen.getCommands()}" fill="{fill}"/>')
        cx += adv[i]
    return "\n".join(parts), width


MARK_DEFS = """
<defs>
  <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1b1464"/><stop offset="0.34" stop-color="#5b2a96"/>
    <stop offset="0.56" stop-color="#c8327f"/><stop offset="0.76" stop-color="#ff6a3d"/>
    <stop offset="0.9" stop-color="#ffa21f"/><stop offset="1" stop-color="#ffd54a"/>
  </linearGradient>
  <radialGradient id="sun" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#fffbe0"/><stop offset="0.55" stop-color="#ffd23f"/>
    <stop offset="1" stop-color="#ff9a2e" stop-opacity="0.0"/>
  </radialGradient>
  <linearGradient id="far" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#5a3aa8"/><stop offset="1" stop-color="#2b2380"/></linearGradient>
  <linearGradient id="mid" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#20c4b0"/><stop offset="1" stop-color="#0f6a8a"/></linearGradient>
  <linearGradient id="near" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0f5a63"/><stop offset="1" stop-color="#082a48"/></linearGradient>
  <linearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#ffd54a"/><stop offset="0.5" stop-color="#ff4f87"/><stop offset="1" stop-color="#6a5cff"/>
  </linearGradient>
  <linearGradient id="trail" x1="0" y1="1" x2="1" y2="0">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0"/><stop offset="1" stop-color="#ffffff" stop-opacity="0.95"/>
  </linearGradient>
  <linearGradient id="plane" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#dfe9ff"/></linearGradient>
  <clipPath id="disc"><circle cx="256" cy="256" r="238"/></clipPath>
</defs>"""


def mark_body() -> str:
    stars = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#fff" opacity="{o}"/>' for x, y, r, o in
                    [(120, 70, 2.2, .9), (190, 42, 1.6, .7), (330, 58, 2.0, .8), (392, 96, 1.5, .7), (88, 128, 1.4, .6), (430, 150, 1.8, .6), (250, 90, 1.3, .5)])
    far = "M0 338 L52 304 L100 330 L160 282 L222 326 L286 296 L346 330 L410 290 L470 326 L512 306 L512 512 L0 512 Z"
    mid = "M0 384 L64 346 L134 380 L212 332 L282 382 L352 350 L432 388 L512 356 L512 512 L0 512 Z"
    near = "M0 432 L84 398 L168 432 L258 392 L350 436 L440 404 L512 430 L512 512 L0 512 Z"
    # a high-wing four-seat aircraft, nose to the right, climbing out
    plane = f"""
<g transform="translate(318 214) rotate(-17) scale(1.28)">
  <path d="M-84 -6 L-96 -40 L-72 -40 L-50 -12 Z" fill="url(#plane)"/>
  <ellipse cx="-80" cy="-3" rx="24" ry="4.6" fill="url(#plane)"/>
  <path d="M-86 -6 L-52 -13 L30 -17 C54 -17 72 -9 76 0 C72 9 54 15 30 15 L-52 7 L-86 -2 Z" fill="url(#plane)"/>
  <path d="M-60 2 L62 4 C68 5 72 3 74 1 L72 6 C56 13 30 13 20 13 L-52 6 Z" fill="#36c8ff"/>
  <path d="M-14 -17 L34 -17 L60 -48 L10 -48 Z" fill="#ffffff"/>
  <path d="M-14 -17 L34 -17 L60 -48 L56 -48 L30 -19 Z" fill="#cfe0ff"/>
  <rect x="14" y="-12" width="22" height="9" rx="3" fill="#2a2f7a"/>
  <path d="M8 8 L30 -16" stroke="#e8f0ff" stroke-width="3" stroke-linecap="round" fill="none"/>
  <ellipse cx="78" cy="0" rx="3" ry="27" fill="#ffffff" opacity="0.45"/>
  <circle cx="76" cy="0" r="4" fill="#ff4f87"/>
</g>"""
    return f"""
<circle cx="256" cy="256" r="244" fill="#0c0f2b"/>
<g clip-path="url(#disc)">
  <rect width="512" height="512" fill="url(#sky)"/>
  {stars}
  <circle cx="250" cy="334" r="150" fill="url(#sun)" opacity="0.55"/>
  <circle cx="250" cy="338" r="84" fill="url(#sun)"/>
  <path d="{far}" fill="url(#far)"/>
  <path d="M0 338 L52 304 L100 330 L160 282 L222 326 L286 296 L346 330 L410 290 L470 326 L512 306" fill="none" stroke="#ffc46a" stroke-width="2.5" opacity="0.7"/>
  <path d="{mid}" fill="url(#mid)"/>
  <path d="{near}" fill="url(#near)"/>
  <path d="M20 286 C110 292 190 262 262 232 C300 216 330 208 352 198" fill="none" stroke="url(#trail)" stroke-width="9" stroke-linecap="round"/>
  {plane}
</g>
<circle cx="256" cy="256" r="238" fill="none" stroke="#ffffff" stroke-width="5" opacity="0.92"/>
<circle cx="256" cy="256" r="249" fill="none" stroke="url(#ring)" stroke-width="9"/>"""


def svg(w, h, body, defs=MARK_DEFS, extra_defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
            f'{defs.replace("</defs>", extra_defs + "</defs>")}{body}</svg>\n')


WORD_DEFS = """
<linearGradient id="sim" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#ffc93c"/><stop offset="0.5" stop-color="#ff5a6e"/><stop offset="1" stop-color="#9a5cff"/>
</linearGradient>"""


def wordmark(x, y, size, anchor="start"):
    fills = [CREAM] * 5 + ["#ffb92e", "#ff6a63", "#b65cff"]  # "sim": saffron -> coral -> violet
    return text_paths(BOLD, "libresim", size, x, y, fills, anchor, track=size * 0.01)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    # 1. the mark
    (OUT / "mark.svg").write_text(svg(512, 512, mark_body()))
    # 2. lockup: mark + wordmark
    size = 176
    word, ww = wordmark(0, 0, size)
    lw = 404 + ww + 40
    word, ww = wordmark(404, 262, size)
    tag, _ = text_paths(REG, "an open-source flight simulator", 33, 410, 318, "#c9cff2", track=1.5)
    body = f'<g transform="translate(18 18) scale(0.74)">{mark_body()}</g>{word}{tag}'
    (OUT / "logo.svg").write_text(svg(round(lw), 400, body, extra_defs=WORD_DEFS))
    # 3. boot splash 1280x720
    word, ww = wordmark(640, 575, 150, "middle")
    tag, _ = text_paths(REG, "an open-source flight simulator  ·  Mumbai – Kochi", 28, 640, 632, "#aab2dd", "middle", track=1.2)
    stars = "".join(f'<circle cx="{(i * 397) % 1280}" cy="{(i * 211) % 520}" r="{1 + (i % 3) * 0.5}" fill="#fff" opacity="{0.15 + (i % 5) * 0.08:.2f}"/>' for i in range(70))
    bg = ('<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#060818"/><stop offset="0.6" stop-color="#101437"/>'
          '<stop offset="1" stop-color="#2a1646"/></linearGradient><radialGradient id="glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#ff7a45" stop-opacity="0.35"/>'
          '<stop offset="1" stop-color="#ff7a45" stop-opacity="0"/></radialGradient></defs>')
    body = (f'<rect width="1280" height="720" fill="url(#bg)"/>{stars}<circle cx="640" cy="270" r="330" fill="url(#glow)"/>'
            f'<g transform="translate(468 52) scale(0.67)">{mark_body()}</g>{word}{tag}')
    (OUT / "splash.svg").write_text(svg(1280, 720, body, extra_defs=bg.replace("<defs>", "").replace("</defs>", "") + WORD_DEFS))


def render(svg_name, png_name, scale=1.0):
    r = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT / "game"), "-s", "res://branding/rasterize.gd", "--",
                        str(OUT / svg_name), str(OUT / png_name), str(scale)], capture_output=True, text=True, timeout=120)
    if not (OUT / png_name).exists():
        sys.exit(f"render failed: {svg_name}\n{r.stdout}\n{r.stderr}")
    print("wrote", OUT / png_name)


if __name__ == "__main__":
    build()
    render("mark.svg", "logo_mark.png", 1.0)          # 512
    render("mark.svg", "icon.png", 0.5)               # 256 window / app icon
    render("logo.svg", "logo_wide.png", 1.0)
    render("splash.svg", "splash.png", 1.0)           # boot splash
    render("mark.svg", "logo.png", 0.25)              # 128: start-screen corner logo
