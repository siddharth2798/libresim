"""libresim branding: mark, lockup and boot splash (SVG) plus all the PNG renders, written to game/branding/.

The mark is the start of a runway ("09/27") on an asphalt tile, see brand_mark.py. The wordmark
"libresim" and the designator are set in Fira Sans (SIL OFL 1.1), converted to outlines so the SVGs need
no fonts. PNGs are rendered by Godot's own SVG loader (game/branding/rasterize.gd), no extra tools needed.

    tools/.venv/bin/python tools/branding/make_logo.py

Files written (game/branding/): mark.svg, logo.svg, splash.svg, logo_mark.png (512), icon.png (256, window
and app icon), logo.png (128, on-screen logo for dark UI), logo_wide.png / logo_wide_dark.png (README),
splash.png (1280 x 720 boot splash); plus packaging/linux/libresim.png (512, Linux package icon).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from brand_mark import THEMES, mark, place, svg_doc  # noqa: E402
from brand_text import ascender_px, glyph_bounds, load, text_path, width  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "game" / "branding"
GODOT = Path.home() / ".local/bin/godot"

WORD, TAGLINE = "libresim", "an open-source flight simulator"
WORD_FONT, TAG_FONT = ("fira", "Medium"), ("fira", "Regular")


def tagline(t, x, base_y, target_w, max_size):
    """Tagline in the muted colour, tracked to be as wide as the wordmark. Returns (svg, size)."""
    tf = load(*TAG_FONT)
    n = len(TAGLINE) - 1
    size = min(max_size, target_w / (width(tf, TAGLINE, 1.0) + 0.05 * n))
    lsb = glyph_bounds(tf, TAGLINE[0], size)[0]
    return text_path(tf, TAGLINE, size, x - lsb, base_y, t["muted"], track=0.05 * size)[0], size


def lockup(t, mark_size=208.0, word_size=116.0):
    """Horizontal lockup: mark, wordmark and tagline. Returns (w, h, body)."""
    pad, gap = 40.0, 46.0
    h = mark_size + 2 * pad
    wf = load(*WORD_FONT)
    tr = 0.03 * word_size
    ww = width(wf, WORD, word_size, tr)
    asc = ascender_px(wf, word_size)
    t_asc, gap_t = 0.72 * word_size * 0.2, word_size * 0.27
    base = h / 2 - (asc + gap_t + t_asc) / 2 + asc
    x = pad + mark_size + gap
    word = text_path(wf, WORD, word_size, x - glyph_bounds(wf, "l", word_size)[0], base, t["ink"], track=tr)[0]
    tag, _ = tagline(t, x, base + gap_t + t_asc, ww, word_size * 0.2)
    return round(x + ww + pad), round(h), place(mark(t), pad, h / 2 - mark_size / 2, mark_size / 512) + word + tag


def splash(t):
    """Boot splash 1280 x 720: mark, wordmark and tagline centred on the dark background."""
    wf, tf = load(*WORD_FONT), load(*TAG_FONT)
    size = 300
    word = text_path(wf, WORD, 140, 640, 560, t["ink"], "middle", track=4.2)[0]
    tag = text_path(tf, f"{TAGLINE}  ·  Mumbai – Kochi", 30, 640, 622, t["muted"], "middle", track=1.5)[0]
    return svg_doc(1280, 720, place(mark(t), 640 - size / 2, 92, size / 512) + word + tag, t["bg"])


def render(svg_path, png_path, scale=1.0):
    r = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT / "game"), "-s", "res://branding/rasterize.gd", "--",
                        str(svg_path), str(png_path), str(scale)], capture_output=True, text=True, timeout=120)
    if not Path(png_path).exists():
        sys.exit(f"render failed: {svg_path}\n{r.stdout}\n{r.stderr}")
    print("wrote", png_path)


def main():
    light, dark = THEMES["light"], THEMES["dark"]
    OUT.mkdir(parents=True, exist_ok=True)
    w, h, body = lockup(light)
    (OUT / "mark.svg").write_text(svg_doc(512, 512, mark(light)))
    (OUT / "logo.svg").write_text(svg_doc(w, h, body))
    (OUT / "splash.svg").write_text(splash(dark))
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "mark_dark.svg").write_text(svg_doc(512, 512, mark(dark)))
        (tmp / "wide_light.svg").write_text(svg_doc(w, h, body, light["bg"]))
        wd, hd, bd = lockup(dark)
        (tmp / "wide_dark.svg").write_text(svg_doc(wd, hd, bd, dark["bg"]))
        render(OUT / "mark.svg", OUT / "logo_mark.png", 1.0)
        render(OUT / "mark.svg", OUT / "icon.png", 0.5)
        render(tmp / "mark_dark.svg", OUT / "logo.png", 0.25)
        render(tmp / "wide_light.svg", OUT / "logo_wide.png", 1.0)
        render(tmp / "wide_dark.svg", OUT / "logo_wide_dark.png", 1.0)
        render(OUT / "splash.svg", OUT / "splash.png", 1.0)
    shutil.copy(OUT / "logo_mark.png", ROOT / "packaging" / "linux" / "libresim.png")


if __name__ == "__main__":
    main()
