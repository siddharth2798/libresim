"""Contact sheets (Pillow) and README for the logo options."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

LABEL_B = "/usr/share/fonts/truetype/open-sans/OpenSans-Bold.ttf"
LABEL_R = "/usr/share/fonts/truetype/open-sans/OpenSans-Regular.ttf"
PAGE = "#dfe3e8"


def _hex(c):
    return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))


def _fit(img, box_w, box_h):
    k = min(box_w / img.width, box_h / img.height)
    return img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)


def _paste_center(cell, img, x0, y0, w, h):
    cell.paste(img, (x0 + (w - img.width) // 2, y0 + (h - img.height) // 2))


def _label(d, xy, num, name, color):
    f1, f2 = ImageFont.truetype(LABEL_B, 30), ImageFont.truetype(LABEL_R, 24)
    d.text(xy, f"{num:02d}", font=f1, fill=color)
    d.text((xy[0] + 52, xy[1] + 4), name, font=f2, fill=color)


def _opt_dir(out, o):
    return out / f"{o.num:02d}-{o.slug}"


def _primary_sheet(options, out):
    cw, ch, m = 920, 380, 28
    cols, rows = 2, (len(options) + 1) // 2
    sheet = Image.new("RGB", (cols * cw + (cols + 1) * m, rows * ch + (rows + 1) * m), PAGE)
    for i, o in enumerate(options):
        t = o.themes[o.primary]
        d = _opt_dir(out, o)
        x0, y0 = m + (i % cols) * (cw + m), m + (i // cols) * (ch + m)
        cell = Image.new("RGB", (cw, ch), _hex(t["bg"]))
        lock = _fit(Image.open(d / f"logo_{o.primary}.png").convert("RGB"), cw - 150, ch - 130)
        _paste_center(cell, lock, 0, 54, cw, ch - 74)
        dr = ImageDraw.Draw(cell)
        _label(dr, (24, 16), o.num, o.name, _hex(t["muted"]))
        mark = Image.open(d / "mark.png").convert("RGBA")
        x = cw - 24
        for px in (32, 64):
            small = mark.resize((px, px), Image.LANCZOS)
            x -= px
            cell.paste(small, (x, 18), small)
            x -= 14
        sheet.paste(cell, (x0, y0))
    sheet.save(out / "contact_sheet.png")


def _variant_sheet(options, out):
    cw, ch, m = 920, 640, 28
    cols, rows = 2, (len(options) + 1) // 2
    sheet = Image.new("RGB", (cols * cw + (cols + 1) * m, rows * ch + (rows + 1) * m), PAGE)
    for i, o in enumerate(options):
        x0, y0 = m + (i % cols) * (cw + m), m + (i // cols) * (ch + m)
        cell = Image.new("RGB", (cw, ch), "#ffffff")
        for j, name in enumerate(("light", "dark")):
            t = o.themes[name]
            half = Image.new("RGB", (cw, ch // 2), _hex(t["bg"]))
            lock = _fit(Image.open(_opt_dir(out, o) / f"logo_{name}.png").convert("RGB"), cw - 150, ch // 2 - 90)
            _paste_center(half, lock, 0, 48, cw, ch // 2 - 60)
            if j == 0:
                _label(ImageDraw.Draw(half), (24, 14), o.num, o.name, _hex(t["muted"]))
            cell.paste(half, (0, j * ch // 2))
        sheet.paste(cell, (x0, y0))
    sheet.save(out / "contact_sheet_variants.png")


def contact_sheets(options, out):
    out = Path(out)
    if all((_opt_dir(out, o) / f"logo_{o.primary}.png").exists() for o in options):
        _primary_sheet(options, out)
        _variant_sheet(options, out)
        print("wrote contact sheets")


def write_readme(options, out):
    lines = [
        "# libresim logo options",
        "",
        "Eight restrained alternatives to the current rainbow logo (flat colours, one or two hues plus neutrals).",
        "Each folder has `mark.svg`, `logo.svg` (horizontal lockup with the tagline), `logo_light.png`, `logo_dark.png`",
        "and `mark.png` (512). `contact_sheet.png` compares all eight; `contact_sheet_variants.png` shows light and dark.",
        "Regenerate with `tools/.venv/bin/python tools/branding/make_logo_options.py` (SVG text is outlined, no fonts needed).",
        "",
        "| # | Name | Concept | Colours | Font (licence) |",
        "|---|------|---------|---------|----------------|",
    ]
    for o in options:
        lines.append(f"| {o.num:02d} | {o.name} (`{o.num:02d}-{o.slug}`) | {o.concept} | {o.colours} | {o.font} |")
    lines += ["", "Notes: `mark.png` is transparent for badge/tile marks and sits on a solid background for open glyph marks",
              "(02, 03, 08). Option 07's lockup is the wordmark alone (plane for the dot of the i); its mark is the i with the plane.",
              "", "The tagline in every lockup is set in Open Sans Regular (Apache-2.0) or Fira Sans Regular (SIL OFL 1.1),",
              "matching the wordmark family.", ""]
    (Path(out) / "README.md").write_text("\n".join(lines))
    print("wrote README.md")
