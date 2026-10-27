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
