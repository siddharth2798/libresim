extends Node
## Round mini-map in outside views (ui/mini_map.gd, a piece of ui/panel_overlay.gd): the C172 Split
## layout shows it instead of the radio stack; it is a disc, drags, zooms, resizes and opens the full map.

var _made: Array = []


func teardown() -> void:  # run_tests.gd calls this after every test
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()


## A 1280 x 720 screen to put the pieces on (the headless window is tiny).
func _screen() -> SubViewport:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	add_child(sv)
	_made.append(sv)
	return sv


func _full_map() -> Control:
	var m: Control = load("res://ui/moving_map.gd").new()
	m.visible = false
	add_child(m)
	_made.append(m)
	return m


func _mini(at: Rect2) -> MiniMap:
	var mm := MiniMap.new()
	mm.source = _full_map()
	_screen().add_child(mm)
	mm.placed = false  # ignore a place saved in this machine's ui.cfg
	mm.heading_up = false
	mm.place(at)
	return mm


func _button(mm: MiniMap, idx: MouseButton, pressed: bool, pos: Vector2, shift := false, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = pressed
	e.position = pos
	e.shift_pressed = shift
	e.double_click = double
	mm._gui_input(e)


func test_c172_split_layout_shows_the_minimap_not_the_radio_stack() -> String:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/c172/panel.json"))
	var items := []
	for piece in raw.overlay.Split:
		items.append_array(piece.items)
	if "radios" in items:
		return "the Split layout still shows the radio stack"
	if not "minimap" in items:
		return "the Split layout should show the round mini-map"
	if not "radios" in raw.overlay.Full[0].items:
		return "the Full layout keeps the radio stack"
	return ""


func test_overlay_minimap_piece_is_a_disc_at_its_anchor() -> String:
	var ov: Control = load("res://ui/panel_overlay.gd").new()
	_screen().add_child(ov)
	ov.map = _full_map()
	var vs := Vector2(1280, 720)
	ov.layout = 1  # Split
	var spot := Rect2()
	for p in ov.placements(vs):
		if p[0] == ["minimap"]:
			spot = p[1]
	if spot.size.x <= 0.0:
		return "the Split layout should place the mini-map"
	ov._add_minimap(spot)
	if ov._pieces.size() != 1 or not ov._pieces[0][0] is MiniMap:
		return "the overlay should hold one MiniMap piece, got %s" % [ov._pieces]
	var mm: MiniMap = ov._pieces[0][0]
	mm.placed = false
	mm.place(spot)
	if not is_equal_approx(mm.size.x, mm.size.y) or not is_equal_approx(mm.size.y, vs.y * 0.32):
		return "the mini-map should be a square box of 0.32 x screen height, got %s" % mm.size
	if absf(mm.position.x + mm.size.x - (vs.x - 8.0)) > 1.0:
		return "the mini-map should sit at the top-right, got x %.0f" % mm.position.x
	return ""


func test_minimap_takes_the_mouse_only_inside_the_disc() -> String:
	var mm := _mini(Rect2(100, 100, 300, 300))
	if not mm._has_point(Vector2(150, 150)):
		return "the middle of the disc should take the mouse"
	if mm._has_point(Vector2(10, 10)):
		return "the corner of the box outside the disc must let the mouse through"
	return ""


func test_minimap_drags_wheel_zooms_and_shift_wheel_resizes() -> String:
	var mm := _mini(Rect2(200, 200, 300, 300))
	_button(mm, MOUSE_BUTTON_LEFT, true, Vector2(150, 150))
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(-80, 40)
	mm._gui_input(mv)
	_button(mm, MOUSE_BUTTON_LEFT, false, Vector2(150, 150))
	if not mm.position.is_equal_approx(Vector2(120, 240)):
		return "a drag should move the disc by the mouse motion, got %s" % mm.position
	if not mm.placed:
		return "a dragged disc keeps its own place"
	mm._gui_input(mv)  # button released: no more moving
	if not mm.position.is_equal_approx(Vector2(120, 240)):
		return "motion after release must not move the disc"
	var before := mm.view.target_m_per_px
	_button(mm, MOUSE_BUTTON_WHEEL_UP, true, Vector2(150, 150))
	if mm.view.target_m_per_px >= before:
		return "wheel up should zoom in"
	var centre := mm.position + mm.size * 0.5
	_button(mm, MOUSE_BUTTON_WHEEL_UP, true, Vector2(150, 150), true)
	if mm.size.x <= 300.0 or not (mm.position + mm.size * 0.5).is_equal_approx(centre):
		return "Shift+wheel up should grow the disc about its centre, got %s at %s" % [mm.size, mm.position]
	mm.move_by(Vector2(-5000, -5000))
	if mm.position.x < 0.0 or mm.position.y < 0.0:
		return "the disc must stay on screen"
	return ""


func test_minimap_double_click_opens_the_full_map_and_right_click_turns_it() -> String:
	var mm := _mini(Rect2(100, 100, 300, 300))
	_button(mm, MOUSE_BUTTON_RIGHT, true, Vector2(150, 150))
	if not mm.heading_up:
		return "right-click should switch to heading up"
	_button(mm, MOUSE_BUTTON_LEFT, true, Vector2(150, 150), false, true)
	if not mm.source.visible:
		return "double-click should open the full map"
	return ""


func test_minimap_drag_holds_the_mouse_yoke() -> String:
	var mm := _mini(Rect2(400, 300, 200, 200))
	_button(mm, MOUSE_BUTTON_LEFT, true, Vector2(100, 100))
	mm._process(0.016)
	if not Props.get_b("ui/minimap_grab"):
		return "dragging the mini-map should hold the mouse yoke"
	_button(mm, MOUSE_BUTTON_LEFT, false, Vector2(100, 100))
	mm.visible = false
	mm._process(0.016)
	if Props.get_b("ui/minimap_grab"):
		return "a hidden mini-map must free the mouse yoke"
	if not FileAccess.get_file_as_string("res://input/keyboard_controls.gd").contains("ui/minimap_grab"):
		return "the mouse yoke should hold still while the mini-map has the pointer"
	return ""
