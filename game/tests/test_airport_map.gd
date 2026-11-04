extends Node
## The clickable airport map and the air-start side view: hit-testing of runway ends and stands
## (ui/menu/airport_map_math.gd, airport_diagram.gd), that the map, the search box and the lists give the same
## Session.setup (airport_page.gd), and the glide-profile maths (glide_math.gd, glide_profile.gd).

var _keep := {}
var _nodes: Array = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes = []
	if not _keep.is_empty():
		Session.setup = _keep
		_keep = {}


func _fresh(aircraft := "c172") -> void:
	if _keep.is_empty():
		_keep = Session.setup.duplicate(true)
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = aircraft
	Session.apply_payload_defaults(AircraftDef.load_def(aircraft))


func _runways() -> Array:
	return [{"length": 1000.0, "width": 45.0, "ends": [{"x": 0.0, "y": 0.0, "ident": "09", "heading_true": 90.0},
		{"x": 1000.0, "y": 0.0, "ident": "27", "heading_true": 270.0}]}]


func _stands() -> Array:
	return [{"x": 500.0, "y": 200.0, "name": "Gate 1", "jetbridge": true, "heading_deg": 0.0},
		{"x": 520.0, "y": 200.0, "name": "Bay 1", "jetbridge": false, "heading_deg": 0.0}]


func _view() -> Dictionary:
	return AirportMapMath.view(AirportMapMath.bounds(_runways(), _stands()), Vector2(600, 400))


func test_map_math_screen_and_world_round_trip() -> String:
	var v := _view()
	for p in [Vector2(0, 0), Vector2(1000, 0), Vector2(500, 200), Vector2(-120, 80)]:
		var back := AirportMapMath.to_world(v, AirportMapMath.to_screen(v, p))
		if back.distance_to(p) > 0.01:
			return "round trip %s -> %s" % [p, back]
	var north := AirportMapMath.to_screen(v, Vector2(500, 200)).y < AirportMapMath.to_screen(v, Vector2(500, 0)).y
	return "" if north else "north (larger y) must be up on the screen"


func test_map_hit_picks_the_nearest_stand_within_the_tolerance() -> String:
	var v := _view()
	var rw := _runways()
	var st := _stands()
	var s0 := AirportMapMath.to_screen(v, Vector2(st[0].x, st[0].y))
	var s1 := AirportMapMath.to_screen(v, Vector2(st[1].x, st[1].y))
	var gap := s0.distance_to(s1)
	if gap < 3.0 or gap > 2.0 * AirportMapMath.STAND_TOL_PX:
		return "fixture: the two stands are %.1f px apart (want 3 to 22)" % gap
	var at0 := AirportMapMath.pick(v, rw, st, s0)
	var at1 := AirportMapMath.pick(v, rw, st, s1)
	var between := AirportMapMath.pick(v, rw, st, s0 + (s1 - s0) * 0.3)
	if at0.get("index", -1) != 0 or at1.get("index", -1) != 1 or between.get("index", -1) != 0:
		return "nearest stand: %s %s %s" % [at0, at1, between]
	var beyond := AirportMapMath.pick(v, rw, st, s0 + Vector2(0, AirportMapMath.STAND_TOL_PX + 14.0))
	return "a point beyond the tolerance must not pick a stand: %s" % [beyond] if beyond.get("kind", "") == "stand" else ""


func test_map_hit_picks_the_runway_end_by_ident_end_or_strip() -> String:
	var v := _view()
	var rw := _runways()
	var a := AirportMapMath.to_screen(v, Vector2(0, 0))
	var z := AirportMapMath.to_screen(v, Vector2(1000, 0))
	var cases := [
		["the 09 threshold", a, "09"], ["the 27 threshold", z, "27"],
		["the 09 label", AirportMapMath.end_label_pos(v, rw[0], 0), "09"], ["the 27 label", AirportMapMath.end_label_pos(v, rw[0], 1), "27"],
		["the strip near 09", a.lerp(z, 0.25) + Vector2(0, 4), "09"], ["the strip near 27", a.lerp(z, 0.75) - Vector2(0, 4), "27"]]
	for c in cases:
		var h := AirportMapMath.pick(v, rw, [], c[1])
		if h.get("kind", "") != "runway" or h.get("ident", "") != c[2]:
			return "%s: %s, want runway %s" % [c[0], h, c[2]]
	var miss := AirportMapMath.pick(v, rw, [], a.lerp(z, 0.5) + Vector2(0, 80))
	return "" if miss.is_empty() else "80 px off the strip picked %s" % [miss]


func test_map_stand_beats_the_runway_under_it() -> String:
	var rw := _runways()
	var st := [{"x": 500.0, "y": 0.0, "name": "Bay 1", "jetbridge": false}]  # on the centre line
	var v := AirportMapMath.view(AirportMapMath.bounds(rw, st), Vector2(600, 400))
	var h := AirportMapMath.pick(v, rw, st, AirportMapMath.to_screen(v, Vector2(500, 0)))
	return "" if h.get("kind") == "stand" else "a stand on the strip must win: %s" % [h]


func _click(d: Control, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	d._gui_input(e)


func test_map_diagram_emits_runway_and_stand_picks_and_hovers() -> String:
	var d := AirportDiagram.new()
	add_child(d)
	_nodes.append(d)
	d.size = Vector2(600, 400)
	d.show_airport(_runways(), [], _stands())
	var picked := []
	d.runway_picked.connect(func(id): picked.append("r:" + id))
	d.stand_picked.connect(func(s): picked.append("s:" + str(s.name)))
	var v := AirportMapMath.view(AirportMapMath.bounds(_runways(), _stands()), d.size, 6.0)  # the diagram keeps 6 px free
	_click(d, AirportMapMath.to_screen(v, Vector2(1000, 0)))
	_click(d, AirportMapMath.to_screen(v, Vector2(520, 200)))
	_click(d, AirportMapMath.to_screen(v, Vector2(500, 200)))
	_click(d, Vector2(2, 2))  # nothing there
	if picked != ["r:27", "s:Bay 1", "s:Gate 1"]:
		return "picks %s" % [picked]
	var m := InputEventMouseMotion.new()
	m.position = AirportMapMath.to_screen(v, Vector2(500, 200))
	d._gui_input(m)
	if d.hover.get("kind") != "stand" or d.tooltip_text != "Gate 1  (jetbridge gate)":
		return "hover %s, tip '%s'" % [d.hover, d.tooltip_text]
	m = InputEventMouseMotion.new()
	m.position = Vector2(2, 2)
	d._gui_input(m)
	return "" if d.hover.is_empty() and d.tooltip_text == "" else "hover must clear: %s '%s'" % [d.hover, d.tooltip_text]


func _page() -> Control:
	var page: Control = load("res://ui/menu/airport_page.gd").new()
	add_child(page)
	_nodes.append(page)
	return page


func _setup_keys() -> Dictionary:
	var s: Dictionary = Session.setup
	return {"airport": s.airport, "runway": s.runway, "stand": s.stand, "start": s.start, "cold": s.cold, "air_ft": s.air_ft, "air_nm": s.air_nm}


## Needs data/processed (airports, runways, stand data). Passes without it.
func test_map_and_lists_give_the_same_setup() -> String:
	_fresh()
	Session.setup.airport = "VABB"
	var page := _page()
	if page._airports.is_empty():
		return ""
	page.pick_airport("VABB")
	var d: AirportDiagram = page._diagram
	d.size = Vector2(700, 460)
	var v := AirportMapMath.view(AirportMapMath.bounds(d.runways, d.stands), d.size, 6.0)
	# runway: the map, the chip and the call all agree
	var end: Dictionary = {}
	for r in d.runways:
		for e in r.ends:
			if end.is_empty() or e.ident != Session.setup.runway:
				end = e
	var ident := str(end.ident)
	page.pick_runway(Session.setup.runway)  # something else first
	_click(d, AirportMapMath.to_screen(v, Vector2(end.x, end.y)))
	var by_map := _setup_keys()
	Session.setup.runway = ""
	page._panel.runway_button(ident).pressed.emit()
	var by_chip := _setup_keys()
	Session.setup.runway = ""
	page.pick_runway(ident)
	var by_call := _setup_keys()
	if by_map != by_chip or by_map != by_call or by_map.runway != ident or by_map.start != "runway":
		return "runway %s: map %s, chip %s, call %s" % [ident, by_map, by_chip, by_call]
	# stand: from the map and from the list; the name round-trips to the same stand in AirportOps
	var rows: Array = page.stand_rows()
	if rows.is_empty():
		return "VABB has no stands on offer"
	var row: Dictionary = rows[rows.size() >> 1]
	_click(d, AirportMapMath.to_screen(v, Vector2(row.stand.x, row.stand.y)))
	var s_map := _setup_keys()
	Session.setup.start = "runway"
	Session.setup.stand = ""
	page._panel.stand_button(row.name).pressed.emit()
	var s_list := _setup_keys()
	if s_map != s_list or s_map.start != "stand":
		return "stand %s: map %s, list %s" % [row.name, s_map, s_list]
	var picked_stand := str(s_map.stand)
	var ops := AirportOps.new()
	ops.data = {"VABB": {"stands": page.current_airport().stands}}
	var found: Dictionary = ops.find_stand("VABB", picked_stand)
	ops.free()
	if picked_stand != row.name or Vector2(found.get("x", 0.0), found.get("y", 0.0)).distance_to(Vector2(row.stand.x, row.stand.y)) > 0.5:
		return "the stand '%s' must reach the same stand in find_stand (got %s)" % [picked_stand, found]
	# a runway click while parked starts on that runway; during an air start it stays an air start
	_click(d, AirportMapMath.to_screen(v, Vector2(end.x, end.y)))
	if Session.setup.start != "runway":
		return "a runway click at a stand should switch to a runway start: %s" % Session.setup.start
	Session.setup.start = "air"
	_click(d, AirportMapMath.to_screen(v, Vector2(end.x, end.y)))
	return "" if Session.setup.start == "air" else "a runway click during an air start must keep it: %s" % Session.setup.start


func test_map_search_pick_equals_choosing_the_airport_directly() -> String:
	_fresh()
	var page := _page()
	if page._airports.size() < 2:
		return ""
	page.pick_airport("VAPO")
	var direct := _setup_keys()
	page.pick_airport("VABB")
	page._search.picked.emit("VAPO")
	var via_search := _setup_keys()
	if direct != via_search or direct.airport != "VAPO" or direct.runway == "":
		return "direct %s, search %s" % [direct, via_search]
	var ap: Dictionary = page.current_airport()
	return "" if page._search.text.begins_with("VAPO") and str(ap.icao) == "VAPO" else "search box shows '%s'" % page._search.text


func test_map_page_selection_is_drawn_on_the_map() -> String:
	_fresh()
	var page := _page()
	if page._airports.is_empty():
		return ""
	page.pick_airport("VABB")
	page.pick_runway(page._diagram.runways[0].ends[1].ident)
	var ident: String = page._diagram.runways[0].ends[1].ident
	if page._diagram.selected_runway != ident or page._diagram.start.is_empty():
		return "runway %s selected on the map: '%s', start %s" % [ident, page._diagram.selected_runway, page._diagram.start]
	var rows: Array = page.stand_rows()
	page.pick_stand(rows[0].name)
	if page._diagram.selected_stand != rows[0].name or page._diagram.selected_runway != "":
		return "stand selection on the map: '%s' / runway '%s'" % [page._diagram.selected_stand, page._diagram.selected_runway]
	Session.setup.air_nm = 8.0
	page._put("start", "air")
	var label: String = page._diagram.start.get("label", "")
	return "" if label == "8 nm out" and page._diagram.start.from != Vector2.INF else "air start marker: %s" % [page._diagram.start]


func test_glide_path_height_angle_and_verdict() -> String:
	if not is_equal_approx(GlideMath.path_ft(5.0), 5.0 * AirStart.FT_PER_NM_3DEG):
		return "the 3 degree path is %s ft per nm" % AirStart.FT_PER_NM_3DEG
	var ang := GlideMath.angle_deg(GlideMath.path_ft(5.0), 5.0)
	if absf(ang - 3.0) > 0.05:
		return "the path height at 5 nm is %.2f degrees, want 3" % ang
	var cases := [[1590.0, 5.0, "close to the 3° path"], [1500.0, 5.0, "close to the 3° path"], [3000.0, 5.0, "above the 3° path"], [800.0, 5.0, "below the 3° path"]]
	for c in cases:
		if GlideMath.verdict(c[0], c[1]) != c[2]:
			return "%s ft at %s nm: '%s', want '%s'" % [c[0], c[1], GlideMath.verdict(c[0], c[1]), c[2]]
	return "" if GlideMath.caption(1500.0, 5.0) == "Path angle to the threshold: 2.8° (close to the 3° path)" else "caption: " + GlideMath.caption(1500.0, 5.0)


func test_glide_layout_marker_and_path_line() -> String:
	var size := Vector2(300, 120)
	var near := GlideMath.layout(size, 1000.0, 3.0)
	var far := GlideMath.layout(size, 1000.0, 9.0)
	if far.marker.x >= near.marker.x:
		return "farther out must be further left: %s vs %s" % [far.marker, near.marker]
	var high := GlideMath.layout(size, 3000.0, 5.0)
	var low := GlideMath.layout(size, 800.0, 5.0)
	if high.marker.y >= low.marker.y or not (high.plot as Rect2).has_point(high.marker) or not (low.plot as Rect2).has_point(low.marker):
		return "higher must be higher on the screen and inside the plot: %s vs %s" % [high.marker, low.marker]
	var on := GlideMath.layout(size, GlideMath.path_ft(5.0), 5.0)  # exactly on the path: marker lies on the dashed line
	var a: Vector2 = on.marker - on.threshold
	var b: Vector2 = on.path_end - on.threshold
	if absf(a.cross(b)) > 0.5:
		return "a marker on the 3 degree path must lie on its line (cross %.2f)" % a.cross(b)
	var flat := GlideMath.layout(size, 300.0, 5.0)  # the path leaves the top of the plot before the far edge
	if not is_equal_approx(flat.path_end.y, (flat.plot as Rect2).position.y):
		return "the path line must stop at the top of the plot: %s" % flat.path_end
	var a1 := GlideMath.layout(size, 1500.0, 5.0)  # the scale belongs to the aircraft, not to the numbers: a step moves only the marker
	var a2 := GlideMath.layout(size, 1500.0, 5.5)
	if [a1.span_nm, a1.span_ft] != [a2.span_nm, a2.span_ft] or a1.path_end != a2.path_end:
		return "the scale must not change with the distance: %s vs %s" % [a1.span_nm, a2.span_nm]
	var a320 := GlideMath.layout(size, 3500.0, 11.0, 40.0, 15000.0)
	return "" if a320.span_nm == 40.0 and a320.span_ft == 6750.0 else "an aircraft's own limits set the range: %s" % [a320]


func test_glide_profile_reads_the_setup() -> String:
	_fresh()
	var g := GlideProfile.new()
	add_child(g)
	_nodes.append(g)
	Session.setup.air_ft = 2600.0
	Session.setup.air_nm = 8.0
	Session.setup.air_kt = 110.0
	g.refresh()
	if g.ft != 2600.0 or g.nm != 8.0 or g.kias != 110.0 or g.caption != GlideMath.caption(2600.0, 8.0):
		return "profile %s ft %s nm %s kt '%s'" % [g.ft, g.nm, g.kias, g.caption]
	return "" if g.tooltip_text.contains("2,600 ft") and g.tooltip_text.contains("110 kt") else "tooltip: " + g.tooltip_text
