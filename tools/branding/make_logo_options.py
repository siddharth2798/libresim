"""Restrained logo options for libresim, written to logo-options/ at the repo root.

Eight concepts, each in logo-options/NN-slug/: mark.svg, logo.svg (lockup, transparent), logo_light.png,
logo_dark.png (lockup on solid light/dark), mark.png (512). Text is outlined with fontTools, so the SVGs need
no fonts. PNGs are rasterised by Godot's SVG loader (game/branding/rasterize.gd), like make_logo.py.
Also writes README.md and contact_sheet*.png.

    tools/.venv/bin/python tools/branding/make_logo_options.py [N ...]     # optional: only these options
"""
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from logo_options_lockup import lockup  # noqa: E402
from logo_options_registry import OPTIONS  # noqa: E402
from logo_options_shapes import svg_doc  # noqa: E402
from logo_options_sheet import contact_sheets, write_readme  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "logo-options"
GODOT = Path.home() / ".local/bin/godot"


def render(svg_path, png_path, scale=1.0):
    r = subprocess.run([str(GODOT), "--headless", "--path", str(ROOT / "game"), "-s", "res://branding/rasterize.gd", "--",
                        str(svg_path), str(png_path), str(scale)], capture_output=True, text=True, timeout=120)
    if not Path(png_path).exists():
        sys.exit(f"render failed: {svg_path}\n{r.stdout}\n{r.stderr}")


def build(opt, tmp):
    d = OUT / f"{opt.num:02d}-{opt.slug}"
    d.mkdir(parents=True, exist_ok=True)
    tp = opt.themes[opt.primary]
    (d / "mark.svg").write_text(svg_doc(512, 512, opt.mark(tp)))
    w, h, body = lockup(opt, tp)
    (d / "logo.svg").write_text(svg_doc(w, h, body))
    # mark.png: containers stay transparent; glyph-only marks get the theme background so they are visible
    mark_svg = Path(tmp) / f"{opt.num}_mark.svg"
    mark_svg.write_text(svg_doc(512, 512, opt.mark(tp), tp["bg"] if opt.mark_bg else None))
    render(mark_svg, d / "mark.png", 1.0)
    for name, t in opt.themes.items():
        w, h, body = lockup(opt, t)
        s = Path(tmp) / f"{opt.num}_{name}.svg"
        s.write_text(svg_doc(w, h, body, t["bg"]))
        render(s, d / f"logo_{name}.png", 2.0)
    print("built", d.name)


def main():
    only = {int(a) for a in sys.argv[1:]}
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for opt in OPTIONS:
            if not only or opt.num in only:
                build(opt, tmp)
    contact_sheets(OPTIONS, OUT)
    write_readme(OPTIONS, OUT)


if __name__ == "__main__":
    main()
