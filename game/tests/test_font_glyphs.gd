extends Node
## Glyph coverage of the menu fonts. Fira Sans has letters, digits, arrows and the usual punctuation but no triangles,
## circles, stars, check marks or cog; those come from the explicit fallback MenuTheme.symbols() (a 12 KB subset of
## DejaVu Sans, tools/make_symbols_font.py), not from whatever font the operating system offers. This test reads the
## source of every start-screen / pause / credits / training script, takes each non-ASCII character in it and requires
## that Fira Sans or the symbols fallback has it, so a new "tofu" symbol fails here instead of on another system.

const WEIGHTS := ["regular", "medium", "semibold", "bold"]
const DIRS := ["res://ui/menu", "res://training"]
const FILES := ["res://ui/credits_screen.gd", "res://ui/controls_overlay.gd", "res://ui/pause_menu.gd", "res://ui/pause_layout.gd",
	"res://ui/fly_confirm.gd", "res://ui/notifications.gd", "res://ui/crash_screen.gd"]


func _sources() -> Array[String]:
	var out: Array[String] = []
	out.append_array(FILES)
	for d in DIRS:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out.append(d.path_join(f))
	return out


## char -> first file that uses it, for every non-ASCII character in the menu scripts (comments included: a
## symbol named in a doc comment is cheap to keep covered, and it keeps the scan free of a GDScript parser).
func _used() -> Dictionary:
	var used := {}
	for path in _sources():
		if not FileAccess.file_exists(path):
			continue
		for ch in FileAccess.get_file_as_string(path):
			if ch.unicode_at(0) > 127 and not used.has(ch):
				used[ch] = path
	return used


## Does this font file itself have the glyph? (Font.has_char also asks the font's fallbacks, which is not what we mean.)
func _own(f: FontFile, c: int) -> bool:
	return TextServerManager.get_primary_interface().font_has_char(f.get_rids()[0], c)


func test_symbols_fallback_loads_and_is_small() -> String:
	var f := MenuTheme.symbols()
	if f == null or not f is FontFile:
		return "the symbols fallback did not load"
	if (f as FontFile).get_font_name() != "libresim Symbols":
		return "the fallback is named %s; the Bitstream Vera licence needs the renamed font" % (f as FontFile).get_font_name()
	var bytes := FileAccess.get_file_as_bytes(MenuTheme.SYMBOLS_PATH).size()
	if bytes > 40000:
		return "the symbols font is %d bytes: it should stay a small subset" % bytes
	return ""


func test_every_weight_falls_back_to_the_symbols() -> String:
	for w in WEIGHTS:
		var f := MenuTheme.font(w) as FontFile
		if not f.fallbacks.has(MenuTheme.symbols()):
			return "Fira %s does not list the symbols fallback" % w
	return ""


func test_every_menu_symbol_is_covered() -> String:
	var fira := MenuTheme.font("regular") as FontFile
	var sym := MenuTheme.symbols() as FontFile
	var used := _used()
	if used.size() < 20:
		return "found only %d non-ASCII characters in the menu scripts; the scan is broken" % used.size()
	var missing := []
	for ch in used:
		var c: int = ch.unicode_at(0)
		if not _own(fira, c) and not _own(sym, c):
			missing.append("%s U+%04X (%s)" % [ch, c, str(used[ch]).get_file()])
	if not missing.is_empty():
		return "no glyph in Fira Sans or the symbols fallback: " + ", ".join(missing)
	return ""


func test_fallback_glyphs_are_not_in_fira_so_the_fallback_is_needed() -> String:
	# The symbols the menus draw as text; if Fira ever gains one, this tells us the fallback can shrink.
	var fira := MenuTheme.font("regular") as FontFile
	var sym := MenuTheme.symbols() as FontFile
	var from_fallback := 0
	for ch in _used():
		var c: int = ch.unicode_at(0)
		if not _own(fira, c) and _own(sym, c):
			from_fallback += 1
	if from_fallback < 8:
		return "only %d menu symbols come from the fallback; expected the triangles, circles, stars, check marks and cog" % from_fallback
	return ""


func test_weights_agree_on_coverage() -> String:
	var ref := MenuTheme.font("regular") as FontFile
	for w in WEIGHTS:
		var f := MenuTheme.font(w) as FontFile
		for ch in _used():
			var c: int = ch.unicode_at(0)
			if _own(f, c) != _own(ref, c):
				return "Fira %s and Regular disagree on U+%04X" % [w, c]
	return ""
