"""Runway-09 logo variants (A: "09/27" row, B: both runway ends) next to the original option 05.

Writes logo-options/05a-runway-09-27/ and 05b-runway-both-ends/ (same files as the other options) and
logo-options/runway_variants.png, a comparison sheet (lockups on light and dark, plus the mark at small sizes).

    tools/.venv/bin/python tools/branding/make_runway_variants.py
"""
import dataclasses
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from logo_options_lockup import lockup  # noqa: E402
from logo_options_registry import OPTIONS  # noqa: E402
from logo_options_runway import mark_5a, mark_5b  # noqa: E402
from logo_options_shapes import g, svg_doc  # noqa: E402
from logo_options_text import load, text_path  # noqa: E402
from make_logo_options import OUT, render  # noqa: E402

BASE = OPTIONS[4]
VARIANTS = [
    (dataclasses.replace(BASE, mark=mark_5a), "05a-runway-09-27", "A  original look, runway-start markings, 09/27"),
    (dataclasses.replace(BASE, mark=mark_5b), "05b-runway-both-ends", "B  both ends of the runway: 09 and 27"),
]


def build_variant(opt, folder, tmp):
    d = OUT / folder
    d.mkdir(parents=True, exist_ok=True)
    tp = opt.themes["light"]
    (d / "mark.svg").write_text(svg_doc(512, 512, opt.mark(tp)))
    w, h, body = lockup(opt, tp)
    (d / "logo.svg").write_text(svg_doc(w, h, body))
    s = Path(tmp) / f"{folder}_mark.svg"
    s.write_text(svg_doc(512, 512, opt.mark(tp)))
    render(s, d / "mark.png", 1.0)
    for name, t in opt.themes.items():
        w, h, body = lockup(opt, t)
        s = Path(tmp) / f"{folder}_{name}.svg"
        s.write_text(svg_doc(w, h, body, t["bg"]))
        render(s, d / f"logo_{name}.png", 2.0)


def sheet(rows, tmp):
    """rows: [(label, option)]. One row per design: light lockup, dark lockup, marks at 96 / 48 / 32 px."""
    lf = load("opensans", "Semibold")
    cw, pad, label_h = 800, 28, 54
    y, parts = pad, []
    for label, opt in rows:
        lab, _ = text_path(lf, label, 26, pad, y + 34, "#475569")
        parts.append(lab)
        y += label_h
        row_h = 0
        x = pad
        for name in ("light", "dark"):
            t = opt.themes[name]
            w, h, body = lockup(opt, t)
            s = cw / w
            parts.append(f'<rect x="{x}" y="{y}" width="{cw}" height="{h * s:.0f}" fill="{t["bg"]}"/>{g(body, x, y, s)}')
            x += cw + pad
            row_h = h * s
        for size, bgname in ((96, "light"), (48, "light"), (32, "light")):
            t = opt.themes[bgname]
            parts.append(f'<rect x="{x}" y="{y}" width="{size + 24}" height="{row_h:.0f}" fill="{t["bg"]}"/>'
                         + g(opt.mark(t), x + 12, y + (row_h - size) / 2, size / 512))
            x += size + 24 + 10
        y += row_h + pad
    width_total = 2 * cw + 3 * pad + 96 + 48 + 32 + 3 * 24 + 30 + pad
    p = Path(tmp) / "runway_sheet.svg"
    p.write_text(svg_doc(int(width_total), int(y), "".join(parts), "#e2e5ea"))
    render(p, OUT / "runway_variants.png", 1.0)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        for opt, folder, _ in VARIANTS:
            build_variant(opt, folder, tmp)
        sheet([("05  original", BASE)] + [(label, opt) for opt, _, label in VARIANTS], tmp)
    print("wrote", OUT / "runway_variants.png")


if __name__ == "__main__":
    main()
