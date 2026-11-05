#!/usr/bin/env python3
"""Builds game/ui/fonts/LibresimSymbols.ttf: the few menu symbols Fira Sans lacks (triangles,
circles, stars, check marks, a cog), cut out of DejaVu Sans and renamed "libresim Symbols" (the
Bitstream Vera licence requires a new name for a modified font). It is the explicit fallback of the
Fira Sans fonts (ui/menu/menu_theme.gd), so symbols look the same on every system.

    tools/.venv/bin/python tools/make_symbols_font.py [path/to/DejaVuSans.ttf]

DejaVuSans.ttf defaults to the copy shipped with matplotlib in tools/.venv. The licence text goes to
third_party/dejavu-symbols/LICENSE (copied from the same folder when it is there).
"""
import shutil
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SYMBOLS = "▲▶▼◀○●★☆⚙✓✕✗"  # ▲▶▼◀○●★☆⚙✓✕✗
OUT = ROOT / "game/ui/fonts/LibresimSymbols.ttf"
NAME = "libresim Symbols"


def main() -> None:
    mpl = ROOT / "tools/.venv/lib/python3.14/site-packages/matplotlib/mpl-data/fonts/ttf"
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else mpl / "DejaVuSans.ttf"
    opts = subset.Options()
    opts.layout_features = []
    opts.name_IDs = [1, 2, 3, 4, 5, 6, 0, 13, 14]
    opts.notdef_outline = True
    opts.hinting = False
    font = TTFont(src)
    sub = subset.Subsetter(opts)
    sub.populate(text=SYMBOLS)
    sub.subset(font)
    for rec in font["name"].names:
        if rec.nameID in (1, 4, 16):
            rec.string = NAME
        elif rec.nameID == 6:
            rec.string = "libresimSymbols"
        elif rec.nameID == 3:
            rec.string = "libresim Symbols (subset of DejaVu Sans)"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    lic = src.parent / "LICENSE_DEJAVU"
    if lic.exists():
        dst = ROOT / "third_party/dejavu-symbols/LICENSE"
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(lic, dst)
    cmap = TTFont(OUT).getBestCmap()
    missing = [hex(ord(c)) for c in SYMBOLS if ord(c) not in cmap]
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes), missing: {missing or 'none'}")


if __name__ == "__main__":
    main()
