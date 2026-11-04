extends Node
## The wind dial of the Weather step (ui/menu/wind_math.gd, wind_dial.gd) and the page's wind line
## (conditions_page.gd): bearing <-> click maths, head / crosswind components, the limit colouring per
## aircraft (the readiness check's own limits), input handling and the page wiring. The page tests use
## runway 27 of VABB from the local data (skipped when it is missing); Session.setup is restored.

const Page := preload("res://ui/menu/conditions_page.gd")
const L := WindMath.Level

var _keep := {}


func _setup(extra := {}) -> Dictionary:
	if _keep.is_empty():
		_keep = Session.setup
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.merge({"airport": "VABB", "runway": "27", "start": "runway", "wind_kt": 0.0, "gust_kt": 0.0}, true)
	Session.setup.merge(extra, true)
	return Session.setup


func teardown() -> void:
	if not _keep.is_empty():
		Session.setup = _keep
		_keep = {}


func _dial() -> WindDial:
	var d := WindDial.new()
	add_child(d)
	d.size = Vector2(140, 140)
	return d


func _click(pos: Vector2, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_dial_direction_from_offset_is_the_compass_bearing() -> String:
	var want := {Vector2(0, -50): 0.0, Vector2(50, 0): 90.0, Vector2(0, 50): 180.0, Vector2(-50, 0): 270.0, Vector2(50, -86.6025): 30.0, Vector2(-86.6025, -50): 300.0}
	for off in want:
		var got := WindMath.dir_from_offset(off)
		if absf(got - float(want[off])) > 0.01:
			return "offset %s should be %s degrees, got %s" % [off, want[off], got]
	return ""


func test_dial_direction_snaps_to_10_wraps_at_north_and_ignores_the_centre() -> String:
	if WindMath.dir_from_offset(Vector2(-3, -50)) != 0.0:  # 3.4 degrees west of north rounds to 000, never 360
		return "just west of north should be 0, got %s" % WindMath.dir_from_offset(Vector2(-3, -50))
	if WindMath.dir_from_offset(Vector2(-8, -50)) != 350.0:
		return "9 degrees west of north should be 350, got %s" % WindMath.dir_from_offset(Vector2(-8, -50))
	if WindMath.dir_from_offset(Vector2(1, 1)) != -1.0:
		return "the centre has no direction"
	for d in range(0, 360, 10):  # offset_of is the inverse
		var back := WindMath.dir_from_offset(WindMath.offset_of(float(d)) * 40.0)
		if back != float(d):
			return "bearing %d came back as %s" % [d, back]
	return ""


func test_dial_components_head_tail_cross() -> String:
	var c := WindMath.components(270.0, 10.0, 270.0)
	if absf(c.x - 10.0) > 1e-4 or absf(c.y) > 1e-4:
		return "wind straight down the runway: head 10 cross 0, got %s" % c
	c = WindMath.components(90.0, 10.0, 270.0)
	if absf(c.x + 10.0) > 1e-4:
		return "wind from behind is a tailwind (negative head), got %s" % c
	c = WindMath.components(0.0, 20.0, 270.0)  # from the north on a westbound runway: from the right
	if absf(c.x) > 1e-4 or absf(c.y - 20.0) > 1e-4:
		return "north wind on runway 27: 20 kt crosswind from the right, got %s" % c
	if WindMath.components(180.0, 20.0, 270.0).y > -19.99:
		return "south wind on runway 27 comes from the left"
	return ""


func test_dial_levels_follow_each_aircrafts_limit() -> String:
	var c172 := WindMath.limit_kt("c172")
	var a320 := WindMath.limit_kt("a320")
	if c172 != 15.0 or a320 != 33.0:
		return "limits should be the aircraft.json data (15 / 33), got %s / %s" % [c172, a320]
	var x25 := Vector2(0, 25)  # 25 kt of pure crosswind
	if WindMath.level(x25, c172) != L.BAD:
		return "25 kt crosswind is over the C172 limit"
	if WindMath.level(x25, a320) != L.OK:
		return "25 kt crosswind is fine for the A320 (limit 33)"
	if WindMath.level(Vector2(0, 14), c172) != L.WARN or WindMath.level(Vector2(0, 8), c172) != L.OK:
		return "14 kt is amber and 8 kt is fine for the C172"
	if WindMath.level(Vector2(0, 15), c172) != L.WARN:
		return "exactly the limit is not over it (the check asks above), so amber"
	if WindMath.level(Vector2(-6, 0), a320) != L.BAD or WindMath.level(Vector2(-5, 0), a320) != L.WARN or WindMath.level(Vector2(-1, 0), a320) != L.OK:
		return "tailwind: red above 5 kt, amber from 2, none below"
	return ""


func test_dial_level_agrees_with_the_readiness_check() -> String:
	for ac in ["c172", "a320"]:
		for kt in [5.0, 12.0, 16.0, 25.0, 34.0]:
			for dir in [0.0, 90.0, 180.0, 270.0]:
				var s := _setup({"aircraft": ac, "wind_kt": kt, "wind_dir_deg": dir})
				var rwy := SetupChecks.runway_of(s)
				if rwy.is_empty():
					return ""  # no data/ here
				var comp := WindMath.components(dir, kt, float(rwy.heading_deg))
				var bad := WindMath.level(comp, WindMath.limit_kt(ac)) == L.BAD
				var asks := SetupChecks.checks(s).any(func(c): return c.id in ["tailwind", "crosswind"])
				if bad != asks:
					return "%s %d kt from %d: dial bad=%s but the readiness check asks=%s" % [ac, kt, dir, bad, asks]
	return ""


func test_dial_line_text() -> String:
	var head := WindMath.line("27", 270.0, 8.0, Vector2(8, 0), true)
	if head != "Rwy 27: headwind 8 kt, crosswind 0 kt right":
		return "line: %s" % head
	var tail := WindMath.line("09", 270.0, 8.0, Vector2(-8, 0.4), true)
	if not tail.contains("TAILWIND 8 kt"):
		return "line: %s" % tail
	if WindMath.line("", 270.0, 8.0, Vector2.ZERO, false).contains("Rwy"):
		return "without a runway only the wind is described"
	return ""


func test_dial_click_and_drag_pick_directions() -> String:
	var d := _dial()
	var got := []
	d.direction_picked.connect(func(x): got.append(x))
	d._gui_input(_click(Vector2(70, 70) + Vector2(60, 0)))  # right of centre: east
	var m := InputEventMouseMotion.new()
	m.position = Vector2(70, 70) + Vector2(0, 60)  # south
	d._gui_input(m)
	d._gui_input(_click(Vector2(10, 10), false))  # release
	m.position = Vector2(70, 70) + Vector2(-60, 0)
	d._gui_input(m)  # not dragging any more: nothing
	var ok: bool = got == [90.0, 180.0]
	d.free()
	return "" if ok else "click east then drag south should emit 90 then 180 (and a motion after release nothing): %s" % [got]


func test_dial_click_on_the_centre_is_ignored_and_arrows_turn_by_10() -> String:
	var d := _dial()
	d.set_state(270.0, 8.0, 0.0, 269.4, "27", 15.0)
	var got := []
	d.direction_picked.connect(func(x): got.append(x))
	d._gui_input(_click(Vector2(70, 70)))
	d._gui_input(_click(Vector2(70, 70), false))
	d._gui_input(_key(KEY_RIGHT))
	d._gui_input(_key(KEY_LEFT))
	d.set_state(0.0, 8.0, 0.0, 269.4, "27", 15.0)
	d._gui_input(_key(KEY_LEFT))  # 0 - 10 wraps to 350
	d._gui_input(_key(KEY_A))
	var ok: bool = got == [280.0, 260.0, 350.0]
	d.free()
	return "" if ok else "centre click ignored, Right +10, Left -10, wrap to 350, other keys nothing: %s" % [got]


func test_dial_state_level_without_a_runway_is_plain() -> String:
	var d := _dial()
	d.set_state(0.0, 30.0, 0.0, -1.0, "", 15.0)
	var plain: bool = d.level() == L.OK
	d.set_state(0.0, 30.0, 0.0, 269.4, "27", 15.0)
	var red: bool = d.level() == L.BAD
	d.set_state(0.0, 30.0, 0.0, 269.4, "27", 33.0)
	var fine: bool = d.level() == L.WARN  # 30 kt is over 80 % of 33 kt, below the limit
	d.free()
	return "" if plain and red and fine else "levels: no runway OK=%s, C172 BAD=%s, A320 WARN=%s" % [plain, red, fine]


func test_dial_page_line_colour_follows_the_aircraft() -> String:
	var res := {}
	for ac in ["c172", "a320"]:
		var s := _setup({"aircraft": ac, "wind_dir_deg": 0.0, "wind_kt": 25.0})
		if SetupChecks.runway_of(s).is_empty():
			return ""  # no data/ here
		var page: Control = Page.new()
		add_child(page)
		res[ac] = page._xwind.get_theme_color("font_color")
		if ac == "c172" and (page._dial.limit_kt != 15.0 or not page._xwind.text.begins_with("Rwy 27")):
			page.free()
			return "the dial should carry the C172 limit and the chosen runway: %s / %s" % [page._dial.limit_kt, page._xwind.text]
		if ac == "a320" and page._dial.limit_kt != 33.0:
			page.free()
			return "the dial should carry the A320 limit, got %s" % page._dial.limit_kt
		page.free()
	if res.c172 != MenuTheme.BAD:
		return "25 kt crosswind: red for the C172, got %s" % res.c172
	if res.a320 == MenuTheme.BAD or res.a320 == MenuTheme.WARN:
		return "25 kt crosswind: not red or amber for the A320 (limit 33), got %s" % res.a320
	return ""


func test_dial_page_wiring_writes_the_setup_and_stand_start_has_no_runway() -> String:
	var s := _setup({"wind_dir_deg": 270.0, "wind_kt": 8.0})
	if SetupChecks.runway_of(s).is_empty():
		return ""  # no data/ here
	var page: Control = Page.new()
	add_child(page)
	page._dial.direction_picked.emit(180.0)
	var err := ""
	if s.wind_dir_deg != 180.0 or page._sl.wind_dir_deg.value != 180.0:
		err = "a dial pick should set wind_dir_deg and the slider, got %s" % s.wind_dir_deg
	page._xbtn.pressed.emit()  # 90 degrees across runway 27 (269.4): 359.4 snaps to 0
	if err == "" and s.wind_dir_deg != 0.0:
		err = "90° crosswind on runway 27 should give 000, got %s" % s.wind_dir_deg
	if err == "":
		s.start = "stand"
		page._sync()
		if not page._xbtn.disabled or page._xwind.text.contains("Rwy") or page._dial.runway_heading >= 0.0:
			err = "a stand start shows the wind only: %s" % page._xwind.text
	page.free()
	return err
