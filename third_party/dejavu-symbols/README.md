# libresim Symbols: the symbol fallback of the UI font (Bitstream Vera licence, DejaVu changes public domain)

Fira Sans has no triangles, circles, stars, check marks or cog, and the menus use them as text (`>` arrows on
buttons, `★★☆` lesson stars, `✓` on finished steps, `⚙ Tune`, status marks). Instead of leaving them to whatever
font the operating system offers (it differs between macOS, Linux and Windows, and a minimal Linux install can
show empty boxes), `game/ui/fonts/LibresimSymbols.ttf` is the explicit fallback of all four Fira Sans weights
(`MenuTheme.font()` in `game/ui/menu/menu_theme.gd`).

- **What it is:** 12 glyphs (U+25B2 U+25B6 U+25BC U+25C0 U+25CB U+25CF U+2605 U+2606 U+2699 U+2713 U+2715 U+2717)
  cut out of **DejaVu Sans** (https://dejavu-fonts.github.io/, the copy that ships with matplotlib), unhinted,
  and **renamed "libresim Symbols"**, as the licence asks for a modified font. About 12 KB.
- **Licence:** `LICENSE` here (Bitstream Vera Fonts Copyright 2003 Bitstream, Inc.; Arev Fonts Copyright 2006
  Tavmjong Bah; DejaVu changes are in the public domain). It permits redistribution and modification, requires the
  notice to travel with the font and a new name for the modified font, and forbids selling the font by itself. The text also
  goes into the `licenses/` folder of every release (`packaging/licenses/dejavu-symbols-LICENSE.txt`).
- **Rebuild:** `tools/.venv/bin/python tools/make_symbols_font.py [DejaVuSans.ttf]` (needs fontTools). To cover another
  symbol, add it to `SYMBOLS` there; `game/tests/test_font_glyphs.gd` fails when a menu script uses a character that
  neither Fira Sans nor this font has.
- **Not covered:** the in-flight instruments draw a few characters with the engine's default font (the radio stack's
  U+21C4 and the attitude gauge's U+2229); they are not menu text.
