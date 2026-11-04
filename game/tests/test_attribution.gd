extends Node
## The map data attribution line (ui/credits_screen.gd) is required by the data licences
## (Sentinel-2 CC BY-NC-SA, Copernicus DEM, OpenStreetMap ODbL), so it must always be on screen.
## It once sat at x = -925 because its parent Control had zero size.
## Built inside SubViewports of real window sizes (the headless root viewport is tiny).

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 600)]


func _open(size: Vector2i) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = size
	add_child(sv)
	var c := Control.new()
	c.set_script(load("res://ui/credits_screen.gd"))
	sv.add_child(c)
	return sv


func _label(sv: SubViewport) -> Label:
	for ch in sv.get_child(0).get_children():
		if ch is Label:
			return ch
	return null


func test_credits_control_covers_the_screen() -> String:
	for size in SIZES:
		var sv := _open(size)
		var got: Vector2 = (sv.get_child(0) as Control).size
		sv.free()
		if not got.is_equal_approx(Vector2(size)):
			return "Credits control is %s at %s" % [got, size]
	return ""


func test_attribution_label_is_inside_the_window() -> String:
	for size in SIZES:
		var sv := _open(size)
		var lbl := _label(sv)
		if lbl == null:
			sv.free()
			return "no attribution label"
		var r := lbl.get_global_rect()
		var txt: String = lbl.text
		sv.free()
		if not Rect2(Vector2.ZERO, Vector2(size)).grow(1.0).encloses(r):
			return "attribution line at %s is outside the %s window" % [r, size]
		for needle in ["Sentinel-2", "Copernicus", "WorldCover", "OpenStreetMap", "F12 credits"]:
			if not txt.contains(needle):
				return "attribution text lacks '%s'" % needle
	return ""


## Fira Sans (SIL OFL 1.1) ships inside the game as the UI font: the files, the licence text and the
## credit must all be there.
func test_fira_sans_font_files_and_licence_are_shipped() -> String:
	for f in ["FiraSans-Regular.ttf", "FiraSans-Medium.ttf", "FiraSans-SemiBold.ttf", "FiraSans-Bold.ttf", "OFL.txt", "FONT-NOTICE.txt"]:
		if not FileAccess.file_exists("res://ui/fonts/" + f):
			return "game/ui/fonts/%s is missing" % f
	var ofl := FileAccess.get_file_as_string("res://ui/fonts/OFL.txt")
	if not ofl.contains("SIL OPEN FONT LICENSE Version 1.1") or not ofl.contains("Mozilla Foundation"):
		return "game/ui/fonts/OFL.txt is not the Fira Sans OFL 1.1 text"
	var notice := FileAccess.get_file_as_string("res://ui/fonts/FONT-NOTICE.txt")
	if not notice.contains("Reserved Font Name") or not notice.contains("github.com/mozilla/Fira"):
		return "FONT-NOTICE.txt lacks the reserved name or the upstream URL"
	return ""


func test_credits_screen_credits_fira_sans() -> String:
	var credit: String = load("res://ui/credits_screen.gd").FONT_CREDIT
	for needle in ["Fira Sans", "Mozilla Foundation", "Telefonica", "SIL Open Font License 1.1", "unmodified"]:
		if not credit.contains(needle):
			return "credits screen font line lacks '%s'" % needle
	return ""


## The repo-level files (not inside res://, so skipped when the game runs outside the repo).
func test_repo_documents_the_shipped_font() -> String:
	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	if not FileAccess.file_exists(root.path_join("CREDITS.md")):
		return ""
	var credits := FileAccess.get_file_as_string(root.path_join("CREDITS.md"))
	if not credits.contains("Fira Sans") or not credits.contains("Open Font License") or credits.contains("Fira Sans itself is not shipped"):
		return "CREDITS.md does not credit the shipped Fira Sans under the OFL"
	for f in ["packaging/licenses/fira-sans-OFL.txt", "third_party/fira-sans/OFL.txt", "third_party/fira-sans/README.md"]:
		if not FileAccess.file_exists(root.path_join(f)):
			return "%s is missing (the OFL text must travel with the release)" % f
	var a := FileAccess.get_file_as_string(root.path_join("packaging/licenses/fira-sans-OFL.txt"))
	if a != FileAccess.get_file_as_string("res://ui/fonts/OFL.txt"):
		return "packaging/licenses/fira-sans-OFL.txt differs from game/ui/fonts/OFL.txt"
	return ""
