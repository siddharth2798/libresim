extends Node
## Livery step (L2) and sticker slots (L3): preset round trip, picture import, and where a picture lands.
## The turntable itself is a windowed preview (livery_preview.gd); headless does not load the model.

const PRESET := "libresim-test-preset"
var _extra: Array[String] = []


func teardown() -> void:
	LiveryStore.remove_preset("c172", PRESET)
	for path in _extra:
		DirAccess.remove_absolute(path)
	_extra.clear()


func test_livery_preset_round_trip_and_reset() -> String:
	var keep: Dictionary = Session.setup.duplicate(true)
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = "c172"
	var page: Control = load("res://ui/menu/page_frame.gd").make_page("res://ui/menu/livery_page.gd")
	add_child(page)
	page._sync()
	page.set_region("body", Color.html("#c8101a"))
	var err := ""
	if page.save_preset(PRESET) != "":
		err = "saving a named preset failed"
	elif Livery.entry(Session.setup.livery, "c172").get("colors", {}).get("body", "") != "#c8101a":
		err = "the colour was not stored: %s" % [Session.setup.livery]
	else:
		page.reset_livery()
		if Livery.entry(Session.setup.livery, "c172").has("colors"):
			err = "reset should return the factory colours: %s" % [Session.setup.livery]
		else:
			page.load_preset(PRESET)
			if Livery.entry(Session.setup.livery, "c172").get("colors", {}).get("body", "") != "#c8101a":
				err = "loading the preset did not restore the colour: %s" % [Session.setup.livery]
	page.queue_free()
	Session.setup = keep
	return err


func test_livery_import_scales_reencodes_and_refuses() -> String:
	var dir := LiveryStore.images_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var src := dir.path_join("libresim-test-src.png")
	var img := Image.create(800, 200, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(src)
	_extra.append(src)
	var got := LiveryStore.import_file(src)
	if not got.ok:
		return "a png should import: %s" % [got]
	_extra.append(dir.path_join(str(got.image)))
	var back := LiveryStore.load_image(str(got.image))
	if back == null or back.get_width() != 512 or back.get_height() != 128:
		return "long side should be 512, got %s" % [back.get_size() if back != null else "null"]
	var txt := dir.path_join("libresim-test.txt")
	var f := FileAccess.open(txt, FileAccess.WRITE)
	f.store_string("nope")
	f.close()
	_extra.append(txt)
	var bad := LiveryStore.import_file(txt)
	if bad.ok or str(bad.error) != "Use a PNG, JPG or WebP.":
		return "a text file should be refused: %s" % [bad]
	var big := dir.path_join("libresim-test-big.png")
	var g := FileAccess.open(big, FileAccess.WRITE)
	var buf := PackedByteArray()
	buf.resize(LiveryStore.MAX_BYTES + 1)
	g.store_buffer(buf)
	g.close()
	_extra.append(big)
	var over := LiveryStore.import_file(big)
	return "" if not over.ok and str(over.error) == "That picture is over 4 MB." else "over 4 MB: %s" % [over]


func test_livery_sticker_lands_inside_its_box_and_mirrors() -> String:
	var slot := {"box": [10, 10, 40, 20], "mirror_box": [10, 40, 40, 20], "scale": 1.0, "dx": 0.0, "dy": 0.0, "mirror": true}
	var where: Dictionary = LiveryStickers.fit(8, 4, slot)
	var box := Rect2(10, 10, 40, 20)
	var mirror := Rect2(10, 40, 40, 20)
	if not box.encloses(where.rect) or not mirror.encloses(where.mirror):
		return "fit left the box: %s / %s" % [where.rect, where.mirror]
	var pushed: Dictionary = LiveryStickers.fit(8, 4, {"box": slot.box, "scale": 0.5, "dx": 1.0, "dy": -1.0})
	if not box.encloses(pushed.rect):
		return "offset fit left the box: %s" % [pushed.rect]
	var picture := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	for x in 8:
		for y in 4:
			picture.set_pixel(x, y, Color.GREEN if x < 4 else Color.RED)
	var name := "libresim-test-stamp.png"
	var path := LiveryStore.images_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(LiveryStore.images_dir())
	picture.save_png(path)
	_extra.append(path)
	var atlas := Image.create(80, 80, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.BLACK)
	LiveryStickers.stamp(atlas, [slot.merged({"image": name}, true)])
	var left := atlas.get_pixel(int(where.rect.position.x) + 2, int(where.rect.position.y) + 2)
	var other := atlas.get_pixel(int(where.mirror.position.x) + 2, int(where.mirror.position.y) + 2)
	if left.g < 0.5 or other.g < 0.5:
		return "picture %s, other side %s (the other side reads the same way up, never flipped)" % [left, other]
	if atlas.get_pixel(0, 0) != Color.BLACK:
		return "a pixel outside the slot was painted"
	return ""


func test_livery_sticker_only_repaints_its_atlas() -> String:
	var def := AircraftDef.load_def("c172")
	if not PaintPipeline.plan(def, "4X-CHV", {}).is_empty():
		return "factory with no sticker still plans nothing"
	var p := PaintPipeline.plan(def, "4X-CHV", {"stickers": {"side": {"image": "abc.png", "scale": 1.0}}})
	if p.size() != 1 or p[0].atlas != "fuselage" or p[0].stickers.size() != 1 or p[0].livery:
		return "only the fuselage atlas, for the sticker: %s" % [p.map(func(a): return [a.atlas, a.livery, a.stickers.size()])]
	var bare := Livery.cache_key("c172", p[0].colors)
	if p[0].key.find(bare) < 0:
		return "the cache key should still carry the colour key"
	return "" if p[0].key.contains("abc.png") else "the cache key should name the picture: " + p[0].key


func test_livery_swatches_stay_square_and_scroll() -> String:
	var keep: Dictionary = Session.setup.duplicate(true)
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = "a320"
	var page: Control = load("res://ui/menu/page_frame.gd").make_page("res://ui/menu/livery_page.gd")
	add_child(page)
	page._sync()
	var chips: Array = []
	for b in page.find_children("*", "Button", true, false):
		if str(b.tooltip_text).begins_with("#"):
			chips.append(b)
	var err := ""
	if chips.size() < 12:
		err = "expected a swatch for each colour, got %d" % chips.size()
	elif page.find_children("Controls", "ScrollContainer", true, false).is_empty():
		err = "the paint controls should scroll on their own, or a short window squashes the swatches"
	else:
		for b in chips:
			var chip := b as Control
			if chip.custom_minimum_size.x < 28 or chip.custom_minimum_size.y < 28:
				err = "a swatch can collapse into a line: %s" % chip.custom_minimum_size
				break
			if chip.size_flags_horizontal & Control.SIZE_FILL or chip.size_flags_vertical & Control.SIZE_FILL:
				err = "a swatch fills its row and turns into a bar"
				break
			if chip.size_flags_horizontal & Control.SIZE_EXPAND or chip.size_flags_vertical & Control.SIZE_EXPAND:
				err = "a swatch stretches"
				break
	page.queue_free()
	Session.setup = keep
	return err


func test_livery_mirror_is_not_a_filled_bar() -> String:
	var keep: Dictionary = Session.setup.duplicate(true)
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = "a320"
	Session.setup.livery = {"a320": {"stickers": {"side": {"image": "none.png", "mirror": true}}}}
	var page: Control = load("res://ui/menu/page_frame.gd").make_page("res://ui/menu/livery_page.gd")
	add_child(page)
	page._sync()
	var boxes := page.find_children("*", "CheckBox", true, false)
	var err := ""
	if boxes.is_empty():
		err = "a placed picture should offer the mirror toggle"
	else:
		var cb := boxes[0] as CheckBox
		var sb := cb.get_theme_stylebox("pressed")
		if not cb.has_theme_stylebox_override("pressed") or (sb is StyleBoxFlat and (sb as StyleBoxFlat).draw_center):
			err = "the mirror toggle still uses the filled button style"
	page.queue_free()
	Session.setup = keep
	return err


func test_livery_preview_texture_has_mipmaps() -> String:
	var paint = load("res://ui/menu/livery_preview_paint.gd")
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var out: Image = paint.for_screen(img)
	if out == null or not out.has_mipmaps():
		return "the preview atlas needs mipmaps, or the fuselage aliases into stripes"
	var big := Image.create(4096, 1024, false, Image.FORMAT_RGBA8)
	big.fill(Color.BLUE)
	var small: Image = paint.for_screen(big)
	if small.get_width() != 2048 or small.get_height() != 512 or not small.has_mipmaps():
		return "a 4096 atlas should preview at 2048 on the long side, got %s" % [small.get_size()]
	return ""


func test_livery_turntable_fills_a_long_fuselage() -> String:
	var frame = load("res://ui/menu/livery_frame.gd")
	var aabb := AABB(Vector3(-20, -2, -2), Vector3(40, 4, 4))
	var dir := Vector3(0.15, 0.28, 1).normalized()
	var aspect := 1.45
	var d: float = frame.distance(aabb, dir, aspect)
	var use: float = frame.frame_use(aabb, dir, aspect, d)
	if use < 0.85 or use > 1.02:
		return "the fuselage should fill the frame, got %s at distance %s" % [use, d]
	var sphere := aabb.size.length() * 0.5 / sin(deg_to_rad(frame.FOV) * 0.5)
	if d > sphere * 0.92:
		return "the fit is no tighter than a bounding sphere (%s vs %s)" % [d, sphere]
	return ""
