extends Node
## Options > Screen layout (ui/screen_layout.gd, ui/menu/screen_layout_tab.gd, ui/menu/screen_layout_preview.gd):
## the per-aircraft piece catalogs, the Custom layout's storage, the panel overlay showing it, the preview's
## drag / resize / switches, the flight-data bar's place, and the mini-map in Custom. Uses a throw-away ui.cfg.

const CFG := "user://test_screen_layout.cfg"

var _made: Array = []
var _old_cfg := ""


func _use_test_cfg() -> void:
	if ScreenLayout.cfg_path != CFG:
		_old_cfg = ScreenLayout.cfg_path
	ScreenLayout.cfg_path = CFG
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))


func teardown() -> void:  # run_tests.gd calls this after every test
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	if _old_cfg != "":
		ScreenLayout.cfg_path = _old_cfg


func _screen(sz := Vector2i(1280, 720)) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = sz
	add_child(sv)
	_made.append(sv)
	return sv


func _c172() -> AircraftDef:
	return AircraftDef.load_def("c172")


func _preview() -> ScreenLayoutPreview:
	_use_test_cfg()
	var p := ScreenLayoutPreview.new()
	_screen().add_child(p)
	p.size = Vector2(640, 360)
	p.set_aircraft(_c172())
	return p


func _press(p: Control, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	p._gui_input(e)


func _motion(p: Control, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	p._gui_input(e)


func test_every_aircraft_offers_pieces_that_exist_on_its_panel() -> String:
	for id in ["c172", "a320"]:
		var def := AircraftDef.load_def(id)
		var cat := ScreenLayout.catalog(def)
		if cat.is_empty():
			return "%s has no Screen layout pieces" % id
		var ids := cat.map(func(c): return c.id)
		if not "minimap" in ids:
			return "%s should offer the mini-map" % id
		for c in cat:
			if c.items != ["minimap"] and ScreenLayout.region(def, c.items).size.x <= 0.0:
				return "%s piece %s names items its panel does not have: %s" % [id, c.id, c.items]
	var split: Array = AircraftDef.load_def("a320").json("panel").overlay.Split
	if not split.any(func(p): return p.items == ["minimap"]):
		return "the A320 Split layout should show the mini-map"
	return ""


func test_defaults_follow_the_anchors_and_stay_on_screen() -> String:
	_use_test_cfg()
	for id in ["c172", "a320"]:
		var def := AircraftDef.load_def(id)
		var d := ScreenLayout.defaults(def)
		for c in ScreenLayout.catalog(def):
			var r := ScreenLayout.rect_px(d[c.id], ScreenLayout.aspect(def, c.items), ScreenLayout.REF)
			if not Rect2(Vector2.ZERO, ScreenLayout.REF).grow(1.0).encloses(r):
				return "%s %s default is off screen: %s" % [id, c.id, r]
	var mm: Dictionary = ScreenLayout.defaults(_c172()).minimap
	if mm.x < 0.7 or mm.y > 0.1 or not mm.on:
		return "the C172 mini-map should default to the top-right and shown, got %s" % mm
	return ""


func test_custom_layout_saves_loads_and_resets() -> String:
	_use_test_cfg()
	var def := _c172()
	var p := ScreenLayout.load_pieces(def)
	p.sixpack.merge({"x": 0.4, "y": 0.2, "h": 0.25, "on": false}, true)
	p.radios.on = true
	var rev := int(Props.get_v("ui/layout_rev", 0))
	ScreenLayout.save_pieces(def, p)
	if int(Props.get_v("ui/layout_rev", 0)) == rev:
		return "a save should bump ui/layout_rev so the flight rebuilds"
	var back := ScreenLayout.load_pieces(def)
	if back.sixpack.on or not is_equal_approx(back.sixpack.x, 0.4) or not is_equal_approx(back.sixpack.h, 0.25) or not back.radios.on:
		return "the saved layout should come back, got %s" % back
	if ScreenLayout.load_pieces(AircraftDef.load_def("a320")).has("sixpack"):
		return "each aircraft has its own layout"
	ScreenLayout.reset(def)
	if not ScreenLayout.load_pieces(def).sixpack.on:
		return "reset should bring back the defaults"
	return ""


func test_layout_choice_is_saved_by_name_and_old_index_still_reads() -> String:
	_use_test_cfg()
	var ov: GDScript = load("res://ui/panel_overlay.gd")
	if ov.saved_layout() != 1:
		return "no saved choice = Split"
	var cf := ConfigFile.new()
	cf.set_value("panel", "layout", 4)  # Off, before Custom existed
	cf.save(CFG)
	if ov.LAYOUTS[ov.saved_layout()] != "Off":
		return "an old saved index 4 meant Off, got %s" % ov.LAYOUTS[ov.saved_layout()]
	ScreenLayout.use_custom()
	if ov.LAYOUTS[ov.saved_layout()] != "Custom":
		return "editing the layout should select Custom"
	return ""


func test_overlay_shows_the_custom_layout() -> String:
	_use_test_cfg()
	var def := _c172()
	var p := ScreenLayout.load_pieces(def)
	p.nav.on = false
	p.engine.merge({"on": true, "x": 0.3, "y": 0.5, "h": 0.2}, true)
	ScreenLayout.save_pieces(def, p)
	var ov: Control = load("res://ui/panel_overlay.gd").new()
	_screen().add_child(ov)
	ov.layout = ov.LAYOUTS.find("Custom")
	var vs := Vector2(1280, 720)
	var got := {}
	for pl in ov.placements(vs):
		got[str(pl[0])] = pl[1]
	if got.has(str(["vor1", "vor2", "adf"])):
		return "a piece switched off must not show"
	var want := ScreenLayout.rect_px(p.engine, ScreenLayout.aspect(def, ["tach", "strip"]), vs)
	if not got.has(str(["tach", "strip"])) or not got[str(["tach", "strip"])].is_equal_approx(want):
		return "the engine piece should be at its Custom place %s, got %s" % [want, got]
	return ""


func test_preview_drag_moves_and_corner_resizes_keeping_the_shape() -> String:
	var p := _preview()
	var b := p.box("sixpack")
	var asp := b.size.x / b.size.y
	_press(p, b.get_center(), true)
	_motion(p, b.get_center() + Vector2(120, -60))
	_press(p, b.get_center() + Vector2(120, -60), false)
	var moved := p.box("sixpack")
	if not moved.position.is_equal_approx(b.position + Vector2(120, -60)):
		return "a drag should move the box, got %s from %s" % [moved.position, b.position]
	if not is_equal_approx(ScreenLayout.load_pieces(_c172()).sixpack.x, p.pieces.sixpack.x):
		return "the move should be saved on release"
	if ScreenLayout.layout_name("") != "Custom":
		return "editing should select the Custom layout"
	_press(p, moved.end - Vector2(2, 2), true)
	_motion(p, moved.end + Vector2(0, 40))
	_press(p, moved.end + Vector2(0, 40), false)
	var big := p.box("sixpack")
	if big.size.y <= moved.size.y + 20.0 or absf(big.size.x / big.size.y - asp) > 0.02:
		return "the corner should resize and keep the shape, got %s" % big.size
	return ""


func test_preview_moves_and_scales_the_flight_data_bar() -> String:
	var p := _preview()
	p.hud_on = true
	var b := p.box("hud")
	_press(p, b.get_center(), true)
	_motion(p, b.get_center() + Vector2(0, 200))
	_press(p, b.get_center() + Vector2(0, 200), false)
	if ScreenLayout.hud().y <= 0.3:
		return "dragging the bar down should save its new place, got %s" % ScreenLayout.hud()
	p.scale_box("hud", 1.5)
	p._commit("hud")
	if absf(ScreenLayout.hud().scale - 1.5) > 0.01:
		return "the wheel should scale the bar, got %s" % ScreenLayout.hud().scale
	return ""


func test_tab_switch_hides_a_piece_and_reset_restores() -> String:
	_use_test_cfg()
	var t := ScreenLayoutTab.new()
	_screen().add_child(t)
	t.select_aircraft("c172")
	if not "sixpack" in t.preview.shown():
		return "the six-pack is shown by default"
	t.set_piece_on(false, "sixpack")
	if "sixpack" in t.preview.shown() or ScreenLayout.load_pieces(_c172()).sixpack.on:
		return "switching the six-pack off should hide it and save"
	t.reset_layout()
	if not ScreenLayout.load_pieces(_c172()).sixpack.on:
		return "reset should show the six-pack again"
	return ""


func test_flight_data_bar_sits_where_the_layout_says() -> String:
	_use_test_cfg()
	ScreenLayout.save_hud({"x": 0.55, "y": 0.5, "scale": 1.5})
	var h: Control = load("res://ui/hud.gd").new()
	_screen().add_child(h)
	h._place = ScreenLayout.hud()
	var vs := Vector2(1280, 720)
	h.place_bar(vs)
	var bar: Control = h._bar
	var centre := bar.position.x + bar.size.x * bar.scale.x * 0.5
	if absf(centre - 704.0) > 1.0 or absf(bar.position.y - 360.0) > 1.0 or not is_equal_approx(bar.scale.x, 1.5):
		return "the bar should be centred at x 704, top 360, scale 1.5; got %s scale %s" % [bar.position, bar.scale]
	return ""


func test_minimap_in_custom_reports_its_new_place() -> String:
	var mm := MiniMap.new()
	mm.source = load("res://ui/moving_map.gd").new()
	mm.source.visible = false
	_made.append(mm.source)
	_screen().add_child(mm)
	mm.custom = true
	mm.placed = false
	mm.place(Rect2(100, 100, 200, 200))
	var got := []
	mm.arranged.connect(func(r): got.append(r))
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(100, 100)
	mm._gui_input(e)
	mm.move_by(Vector2(50, 0))
	e = e.duplicate()
	e.pressed = false
	mm._gui_input(e)
	if got.size() != 1 or not got[0].position.is_equal_approx(Vector2(150, 100)):
		return "a drag in Custom should report the new place, got %s" % [got]
	if mm.placed:
		return "in Custom the layout owns the place, not the mini-map's own setting"
	return ""
