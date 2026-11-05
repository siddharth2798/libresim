extends Node
## The reasons list at the bottom of the Free-flight rail (ui/menu/flow_rail.gd) and the footer chips that stay on one row
## (ui/menu/flow_chips.gd, fit_widths). Built headless without a layout pass: the rail is checked through its nodes and
## signals, the chips through FlowChips.layout() with a width set by hand. Looks: the debug_menu screenshots.

## Room the chips have at 1280 x 720 (measured on the screenshot: the footer is 1188 px inside; minus Back 100, Fly 150,
## the widest Next ("Next: Airport & start", 212) and three gaps of 10 leaves 696), a little less to be safe.
const CHIPS_AT_1280 := 690.0

var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _rail() -> FlowRail:
	var r := FlowRail.new()
	add_child(r)
	_nodes.append(r)
	return r


func _setup(aircraft := "c172", extra := {}) -> Dictionary:
	var s := Session.DEFAULT.duplicate(true)
	s.merge(Session.WEATHER.Clear, true)
	s.aircraft = aircraft
	s.airport = "ZZZZ"
	s.wind_kt = 0.0
	s.gust_kt = 0.0
	s.time_h = 12.5
	if aircraft == "a320":
		s.fuel_gal = 8500.0
		s.cabin_kg = 10500.0
		s.cargo_kg = 1500.0
	s.merge(extra, true)
	return s


func _item(step: String, level: String, text: String) -> Dictionary:
	return {"step": step, "level": level, "id": text, "text": text}


# ---- the reasons list ------------------------------------------------------------------------

func test_rail_reasons_are_hidden_when_ready() -> String:
	var r := _rail()
	r.refresh(_setup(), [], 0, {})
	if r.reason_box.visible or not r.reason_btns.is_empty():
		return "a ready setup shows no reasons"
	return ""


func test_rail_reasons_list_bad_first_then_warn() -> String:
	var r := _rail()
	var list := [_item("weather", "warn", "Visibility under 1.6 km"), _item("aircraft", "bad", "Over maximum takeoff weight by 1200 kg"),
		_item("weather", "bad", "Crosswind 25 kt, above 15 kt")]
	r.refresh(_setup(), list, 0, {})
	var got := r.reason_btns.map(func(b): return b.text)
	if not r.reason_box.visible or got != ["▲ Over maximum takeoff weight by 1200 kg", "▲ Crosswind 25 kt, above 15 kt", "▲ Visibility under 1.6 km"]:
		return "order / texts %s" % [got]
	var bad: Color = r.reason_btns[0].get_theme_color("font_color")
	var warn: Color = r.reason_btns[2].get_theme_color("font_color")
	if bad != MenuTheme.BAD or warn != MenuTheme.WARN:
		return "bad is red, warn amber: %s %s" % [bad, warn]
	return ""


func test_rail_reasons_use_the_setup_checks_texts_and_jump_to_their_step() -> String:
	var s := _setup("a320", {"fuel_gal": 19400.0, "cabin_kg": 14000.0, "cargo_kg": 5000.0, "wind_dir_deg": 360.0, "wind_kt": 40.0, "visibility_m": 1000.0})
	var list := SetupChecks.checks(s, {"ident": "27", "length_m": 3000.0, "heading_deg": 270.0})
	var r := _rail()
	r.refresh(s, list, 0, {})
	var want := FlowRail.reason_items(list).map(func(c): return "▲ " + str(c.text))
	if r.reason_btns.map(func(b): return b.text) != want or want.size() < 3:
		return "rail %s, SetupChecks %s" % [r.reason_btns.map(func(b): return b.text), want]
	var jumped := []
	r.step_pressed.connect(func(i): jumped.append(i))
	for b in r.reason_btns:
		b.pressed.emit()
	var steps := FlowRail.reason_items(list).map(func(c): return FlowValues.KEYS.find(c.step))
	if jumped != steps or not (0 in jumped and FlowValues.KEYS.find("weather") in jumped):
		return "jumps %s, steps %s" % [jumped, steps]
	return ""


func test_rail_reasons_are_rebuilt_only_when_the_list_changes() -> String:
	var r := _rail()
	var list := [_item("aircraft", "bad", "CG outside the envelope")]
	r.refresh(_setup(), list, 0, {})
	var first: Button = r.reason_btns[0]
	r.refresh(_setup(), list.duplicate(true), 1, {})
	if r.reason_btns[0] != first:
		return "the same list must keep the same buttons (the focus would be lost on every repaint)"
	r.refresh(_setup(), [], 1, {})
	if r.reason_box.visible or not r.reason_btns.is_empty():
		return "an emptied list hides the box"
	return ""


func test_rail_reasons_sit_below_the_steps_and_the_rail_scrolls() -> String:
	var r := _rail()
	var col: Control = r.reason_box.get_parent()
	if col.get_child(col.get_child_count() - 1) != r.reason_box:
		return "reasons are the last child of the rail column"
	if not (col.get_parent() is ScrollContainer):
		return "the rail column should be inside a ScrollContainer (a 720 px window)"
	if r.reason_box.get_index() <= r.entries[-1].get_index():
		return "reasons come after the steps"
	return ""


# ---- the chips stay on one row ---------------------------------------------------------------

func test_fit_widths_is_pure_and_fair() -> String:
	var nat := [100.0, 200.0, 150.0]
	if FlowChips.fit_widths(nat, 500.0, 6.0, 72.0) != nat:
		return "they fit: natural widths"
	var w := FlowChips.fit_widths(nat, 400.0, 6.0, 72.0)  # room 388: the widest are cut to one width
	var sum: float = w[0] + w[1] + w[2]
	if sum > 388.001 or w[0] != 100.0 or absf(w[1] - w[2]) > 0.01 or w[1] >= 150.0:
		return "cut the widest first: %s" % [w]
	w = FlowChips.fit_widths([300.0, 300.0, 300.0, 40.0], 200.0, 6.0, 72.0)  # hopeless: never below the minimum
	if w[0] != 72.0 or w[3] != 40.0:
		return "minimum width and a narrow chip kept: %s" % [w]
	return ""


func _chips(setup: Dictionary, width: float) -> FlowChips:
	var c := FlowChips.new()
	add_child(c)
	_nodes.append(c)
	c.refresh(setup, SetupChecks.checks(setup, {"ident": "27", "length_m": 3000.0, "heading_deg": 270.0}))
	c.size = Vector2(width, c.get_combined_minimum_size().y)
	c.layout()
	return c


## Row check: same top for every chip, left to right, inside the width; returns "" or the problem.
func _one_row(c: FlowChips, width: float) -> String:
	var x := -1.0
	for b in c.chips:
		if absf(b.position.y - c.chips[0].position.y) > 0.5 or b.position.x < x - 0.5:
			return "chips are not on one row: %s" % [c.chips.map(func(k): return k.position)]
		x = b.position.x + b.size.x
		if b.size.x < FlowChips.MIN_W - 0.5 and b.size.x < c._natural[b.get_index()] - 0.5:
			return "chip %d squeezed below the minimum: %.0f" % [b.get_index(), b.size.x]
	return "" if x <= width + 0.5 else "the row is %.0f px wide, room %.0f" % [x, width]


func test_chips_fit_at_1280_in_the_usual_states() -> String:
	var cases := {
		"c172 runway": _setup("c172", {"airport": "VABB", "runway": "27", "cold": true}),
		"a320 runway": _setup("a320", {"airport": "VABB", "runway": "27"}),
		"c172 stand": _setup("c172", {"airport": "VABB", "start": "stand", "stand": "12"}),
		"a320 stand": _setup("a320", {"airport": "VABB", "start": "stand", "stand": "Gate 4"}),
		"c172 air": _setup("c172", {"airport": "VABB", "start": "air", "air_ft": 1500.0, "air_nm": 5.0}),
		"a320 air": _setup("a320", {"airport": "VABB", "start": "air", "air_ft": 2200.0, "air_nm": 3.0}),
	}
	for k in cases:
		var c := _chips(cases[k], CHIPS_AT_1280)
		var err := _one_row(c, CHIPS_AT_1280)  # six chips: the widest may be shortened, the row does not wrap
		if err != "":
			return "%s: %s" % [k, err]
	return ""


func test_chips_stay_on_one_row_with_the_worst_texts() -> String:
	var long_stand := "Terminal 1 Gate 12A (international departures, north pier)"
	var worst := {
		"stand, long name": _setup("a320", {"airport": "VABB", "start": "stand", "stand": long_stand}),
		"air start, big numbers": _setup("c172", {"airport": "VABB", "start": "air", "air_ft": 12500.0, "air_nm": 25.5, "wind_dir_deg": 270.0, "wind_kt": 25.0,
			"gust_kt": 40.0, "failures": {"engine": [1, 0.0], "left_brake": [1, 0.0], "flaps": [1, 0.0]}, "record": true, "record_height": 1080, "record_fps": 60}),
	}
	worst["air start, big numbers"].random.enabled = true
	for k in worst:
		for width in [CHIPS_AT_1280, 1.5 * CHIPS_AT_1280]:  # 1920 x 1080 is the same layout scaled by 1.5
			var c := _chips(worst[k], width)
			var err := _one_row(c, width)
			if err != "":
				return "%s at %.0f: %s" % [k, width, err]
		var c2 := _chips(worst[k], CHIPS_AT_1280)
		if c2.size.y > 56.0:
			return "%s: the chip row is %.0f px tall, the footer buttons are 56" % [k, c2.size.y]
	var cs := _chips(worst["stand, long name"], CHIPS_AT_1280)
	var stand := FlowValues.KEYS.find("airport")
	var b: Button = cs.chips[stand]
	if b.size.x >= cs._natural[stand] - 1.0 or not b.clip_text or b.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS:
		return "the long stand chip should be shortened with an ellipsis (width %.0f of %.0f)" % [b.size.x, cs._natural[stand]]
	if not b.tooltip_text.contains(long_stand.strip_edges()) and not b.tooltip_text.contains("Terminal 1 Gate 12A"):
		return "the tooltip has the whole name: " + b.tooltip_text
	return ""
