extends Node
## The livery page after the crash report and the "blurry, dull, tiny picture" complaints: Remove must not free the
## button that is emitting, a picture reads upright on both sides at a useful size, and the turntable is drawn sharp
## with a tone mapper that keeps the chosen colour.

const NAME := "libresim-test-mockup.png"
var _extra: Array[String] = []


func teardown() -> void:
	for path in _extra:
		DirAccess.remove_absolute(path)
	_extra.clear()


func _picture() -> void:
	var picture := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	for x in 8:
		for y in 4:
			picture.set_pixel(x, y, Color.GREEN if (x < 4 and y < 2) else Color.RED)  # green only in the top left
	var path := LiveryStore.images_dir().path_join(NAME)
	DirAccess.make_dir_recursive_absolute(LiveryStore.images_dir())
	picture.save_png(path)
	_extra.append(path)


func _button(node: Node, text: String) -> Button:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## Remove emits `edited`, the page rebinds the slots, and the rebind used to free() the button that was still emitting
## (Godot: "freed while a signal is being emitted", then a bus error). The old button must outlive the handler.
func test_livery_remove_does_not_free_the_button_that_is_emitting() -> String:
	var slots: VBoxContainer = load("res://ui/menu/livery_slots.gd").new()
	add_child(slots)
	var stickers := [{"key": "side", "label": "Side", "atlas": "fuselage", "box": [0, 0, 10, 10]}]
	var placed := {"side": {"image": "none.png", "scale": 1.0, "dx": 0.0, "dy": 0.0, "mirror": true}}
	slots.bind(stickers, placed)
	var remove := _button(slots, "Remove")
	if remove == null or remove.disabled:
		slots.queue_free()
		return "a placed picture should have an enabled Remove button"
	var seen := {"alive_in_handler": false, "rebound": false}
	slots.edited.connect(func(_key: String, _fields: Dictionary) -> void:
		slots.bind(stickers, {})
		seen.rebound = true
		seen.alive_in_handler = is_instance_valid(remove))
	remove.pressed.emit()
	var err := ""
	if not seen.rebound:
		err = "Remove did not report the edit"
	elif not seen.alive_in_handler:
		err = "the rebind freed the Remove button in the middle of its own signal"
	elif slots.get_child_count() != 1 or _button(slots, "Remove").disabled == false:
		err = "after removing, the block should show an empty slot (Remove disabled)"
	slots.queue_free()
	return err


## A picture is drawn upright on the other side too (it is never flipped), at the same place on the aircraft.
func test_livery_picture_reads_upright_on_both_sides() -> String:
	_picture()
	var turned := {"box": [4, 4, 40, 20], "mirror_box": [4, 34, 40, 20], "mirror_turn": 180, "scale": 1.0, "dx": 0.0, "dy": 0.0, "mirror": true}
	var plain := {"box": [4, 4, 40, 20], "mirror_box": [4, 34, 40, 20], "mirror_turn": 0, "scale": 1.0, "dx": 0.0, "dy": 0.0, "mirror": true}
	var a := Image.create(60, 60, false, Image.FORMAT_RGBA8)
	a.fill(Color.BLACK)
	LiveryStickers.stamp(a, [plain.merged({"image": NAME}, true)])
	var b := Image.create(60, 60, false, Image.FORMAT_RGBA8)
	b.fill(Color.BLACK)
	LiveryStickers.stamp(b, [turned.merged({"image": NAME}, true)])
	var top_left: Color = a.get_pixel(6, 6)
	var other_top_left: Color = a.get_pixel(6, 36)
	var turned_top_left: Color = b.get_pixel(6, 36)
	var turned_bottom_right: Color = b.get_pixel(41, 51)
	if top_left.g < 0.5 or other_top_left.g < 0.5:
		return "an upright strip should show the same picture, not a flipped one: %s / %s" % [top_left, other_top_left]
	if turned_top_left.r < 0.5 or turned_bottom_right.g < 0.5:
		return "a strip turned half a round should hold the picture turned half a round: %s / %s" % [turned_top_left, turned_bottom_right]
	return ""


## The same spot on the aircraft: an x-reflected strip negates dx, a turned strip negates dy.
func test_livery_other_side_keeps_the_same_place() -> String:
	var base := {"box": [0, 0, 100, 100], "mirror_box": [200, 0, 100, 100], "scale": 0.5, "dx": 1.0, "dy": -1.0}
	var plain: Dictionary = LiveryStickers.fit(10, 10, base.merged({"mirror_turn": 0}, true))
	var turned: Dictionary = LiveryStickers.fit(10, 10, base.merged({"mirror_turn": 180}, true))
	# plain: dx 1 (right) becomes left in the reflected strip, dy stays top
	if not is_equal_approx(plain.mirror.position.x, 200.0) or not is_equal_approx(plain.mirror.position.y, 0.0):
		return "reflected strip: %s" % [plain.mirror]
	# turned: dx stays right, dy -1 (top) becomes the bottom
	if not is_equal_approx(turned.mirror.end.x, 300.0) or not is_equal_approx(turned.mirror.end.y, 100.0):
		return "turned strip: %s" % [turned.mirror]
	return ""


## Pictures at 100 % must be a useful size. The old boxes were 160x100 (side) and 180x120 (fin) on the C172's
## 2048 atlas, 120x70 and 90x80 on the A320's 4096: the new ones cover at least twice that area.
func test_livery_sticker_boxes_are_big_enough_to_see() -> String:
	var old_area := {"c172/side": 16000, "c172/fin": 21600, "a320/side": 8400, "a320/fin": 7200}
	for id in ["c172", "a320"]:
		var lv := Livery.of(AircraftDef.load_def(id))
		for s in lv.stickers:
			var want: int = old_area["%s/%s" % [id, s.key]] * 2
			for b in [s.box, s.mirror_box]:
				if int(b[2]) * int(b[3]) < want:
					return "%s %s box %s is under twice its old area (%d px2)" % [id, s.key, b, want]
			if not s.has("mirror_turn"):
				return "%s %s should say how its other side is laid out (mirror_turn)" % [id, s.key]
	return ""


func test_livery_turntable_is_drawn_sharp_and_keeps_the_colour() -> String:
	var view = load("res://ui/menu/livery_preview.gd").new()
	var holder: Node3D = view._world()
	var env: Environment = (holder.get_child(0) as WorldEnvironment).environment
	var err := ""
	if view.SUPERSAMPLE < 2.0:
		err = "the turntable should be drawn at least twice the panel size, then shrunk"
	elif env.tonemap_mode == Environment.TONE_MAPPER_AGX or env.tonemap_mode == Environment.TONE_MAPPER_FILMIC:
		err = "AgX / Filmic fade a saturated livery colour towards pink and grey on the turntable"
	elif env.background_mode != Environment.BG_SKY or env.ambient_light_source != Environment.AMBIENT_SOURCE_SKY:
		err = "the aircraft should stand in a sky and be lit by it, not on a flat colour"
	holder.free()
	view.free()
	return err
