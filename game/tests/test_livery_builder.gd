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
	var flipped := atlas.get_pixel(int(where.mirror.position.x) + 2, int(where.mirror.position.y) + 2)
	if left.g < 0.5 or flipped.r < 0.5:
		return "picture %s, mirror %s (mirror should be the flipped side)" % [left, flipped]
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
