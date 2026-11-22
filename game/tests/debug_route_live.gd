extends Node
## Debug: editing the route in flight, with real (injected) input in the real flight scene. Needs a display; run with
## --audio-driver Dummy. An "In the air" start on leg 1 of VABB -> WPT01 -> WPT02 -> WPT03 -> VAPO, then:
##   N opens the map, G fits the route, a click on "Edit route", a drag of the second waypoint ahead  -> the GPS follows
##   Esc, a click on "Edit route" in the pause menu, a click on the map (a new point), "Apply and resume" -> the GPS follows
## Prints CHECK lines; screenshots to $FREESIM_SHOTS/live_<aircraft>_<tag>.png (default user://).
##   FREESIM_AIRCRAFT=a320   fly the A320 (autopilot on, NAV): also checks NAV flies the edited route
##   FREESIM_SIZE=1600x900   window size
##   FREESIM_UISCALE=150%    UI size (as tests/debug_route.gd)
##   FREESIM_TAG=720p150_    put before each shot's tag
##   MAP_ONLY=1              stop after the N map shots (map_open, map_edit; the title row clears the top bars)

var f: Node
var _out := ""
var _ac := "c172p"
var _fails := 0


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	_out = OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()
	Session.interactive_override = 0  # nothing is saved
	var choice := OS.get_environment("FREESIM_UISCALE")
	if choice != "":
		if get_window().size_changed.is_connected(UiScale.apply):
			get_window().size_changed.disconnect(UiScale.apply)
		UserOptions.set_v("ui_scale", choice)  # in memory only
		var fs := UiScale.factor_for(Vector2(get_window().size), choice, 1.0)
		get_window().content_scale_factor = fs
		UiScale.factor = fs
		UiScale.changed.emit(fs)
	var s := Session.DEFAULT.duplicate(true)
	if OS.get_environment("FREESIM_AIRCRAFT") != "":
		_ac = OS.get_environment("FREESIM_AIRCRAFT")
	s.aircraft = _ac
	s.airport = "VABB"
	s.runway = "27"
	s.start = "air"
	Session.setup = s
	Session.apply_payload_defaults(AircraftDef.load_def(_ac))
	var cruise := RouteEdit.default_cruise_ft(_ac)
	var d := RouteEdit.db()
	var a: Vector2 = d.position_of("VABB")
	var b: Vector2 = d.position_of("VAPO")
	var side := (b - a).orthogonal().normalized() * 9000.0
	var wps: Array = []
	for k in [[0.25, 1.0], [0.5, -1.0], [0.75, 1.0]]:  # three free waypoints zig-zagging along VABB -> VAPO
		wps.append(RouteBuilder.user_waypoint(a.lerp(b, k[0]) + side * k[1], wps, cruise))
	Session.setup.route = {"dest": "VAPO", "wps": wps, "cruise_ft": cruise, "kind": "manual", "air_at": 1}
	print("planned: ", RouteEdit.as_text(Session.setup))
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _run() -> void:
	await _wait(3.0)
	var t := 0.0
	while f.get("_air_wait") and t < 60.0:  # the loading veil takes every click until the airfield is in
		await _wait(0.5)
		t += 0.5
	await _wait(1.5)
	if _ac != "c172p":
		for k in ["ap1", "athr", "hdg_managed", "spd_managed"]:
			Props.set_v("controls/fcu/" + k, true)
	print("start GPS: ", _gps())
	var map: Control = f.get_node("UI/Map")
	_key(KEY_N)
	await _wait(1.0)
	_key(KEY_G)
	await _wait(1.0)
	var strip: MapStrip = map._strip
	await _shot("map_open")
	_title_check(map, "edit mode off")
	print("map open %s, Edit route button at %s" % [map.visible, _px(strip.buttons.edit, strip.buttons.edit.size * 0.5)])
	await _click(strip.buttons.edit, strip.buttons.edit.size * 0.5)
	await _wait(0.5)
	_check(map.editing(), "the Edit route button turns edit mode on")
	if not map.editing():
		await _shot("map_not_editing")
		print("DONE %s: injected input was ignored, run again" % _ac)
		get_tree().quit(2)
		return
	await _shot("map_edit")
	_title_check(map, "edit mode on")
	if OS.get_environment("MAP_ONLY") != "":
		print("DONE %s: %d failed checks" % [_ac, _fails])
		get_tree().quit(1 if _fails > 0 else 0)
		return
	var legs: Array = map._edit.gestures.legs
	var leg: Dictionary = legs[1] if legs.size() > 2 else legs[0]
	var before := _gps()
	var from_px: Vector2 = map.view.to_px(leg.b)
	var to_px := from_px + Vector2(-90, 70)
	await _drag(map, from_px, to_px)
	await _wait(0.6)
	var after := _gps()
	var moved := str(after[legs.find(leg)]) if legs.find(leg) < after.size() else ""
	var want: Vector2 = map.view.to_world(to_px)
	var got = RouteEdit.db().position_of(moved)
	_check(after.size() == before.size() and got != null and (got as Vector2).distance_to(want) < 800.0 and (got as Vector2).distance_to(leg.b) > 3000.0,
		"dragging %s on the N map: GPS %s -> %s, %s now %.1f nm from where it was" % [leg.ident, before, after, moved, (got as Vector2).distance_to(leg.b) / 1852.0 if got != null else -1.0])
	var gps_node: Gps = f.get_node("Avionics/Gps")
	var flies: Array = gps_node.plan.wps.filter(func(w): return w.ident == moved)
	_check(not flies.is_empty() and got != null and (flies[0].pos as Vector2).distance_to(got) < 1.0,
		"the GPS node flies %s at its new place %s" % [moved, flies[0].pos.round() if not flies.is_empty() else null])
	await _shot("map_dragged")
	_key(KEY_N)
	await _wait(0.5)
	_key(KEY_ESCAPE)
	await _wait(0.8)
	var pause: Control = f.get_node("UI/Pause")
	await _click(pause._nav["route"], pause._nav["route"].size * 0.5)
	await _wait(1.5)
	var live: Control = pause._pages["route"]
	var rmap: RouteMap = live.page.map
	await _shot("pause_open")
	var last: Dictionary = rmap.legs.back()
	var pre_last: Vector2 = rmap.legs[rmap.legs.size() - 2].b if rmap.legs.size() > 1 else rmap.legs[0].a
	var spot := rmap.view.to_px(pre_last.lerp(last.b, 0.5)) + Vector2(70, -60)
	await _click(rmap, spot)
	await _wait(0.6)
	var planned: Array = RouteEdit.route_of(live.page.live).wps.map(func(w): return w.id)
	await _shot("pause_added")
	rmap.gestures.legs = rmap.legs
	var probe: Array = rmap.gestures.shown_legs(-1)
	MapRouteLayer.reserve(rmap.view, probe, MenuTheme.font("medium"), [], MapFeatures.marker_rects(rmap.view, rmap.db))
	for l in probe:
		var at: Vector2 = rmap.view.to_px(l.b)
		print("pause map %s at %s %s, label %s" % [l.ident, at.round(), "on the map" if Rect2(Vector2.ZERO, rmap.size).has_point(at) else "OFF the map", l.get("lbl_text")])
	before = _gps()
	await _click(live.apply_btn, live.apply_btn.size * 0.5)
	await _wait(1.0)
	after = _gps()
	_check(not pause.visible, "Apply resumes the flight")
	var added := str(Session.setup.route.wps.back().id)
	_check(after.size() == before.size() + 1 and str(after[after.size() - 2]) == added and added == str(planned.back()),
		"pause Edit route + Apply: GPS %s -> %s (added %s, the page named it %s)" % [before, after, added, planned.back()])
	_check(Session.setup.route.wps.map(func(w): return w.id).has(planned.back()), "Session.setup.route has the new point")
	if _ac != "c172p":
		_check(MCDU.route() == after, "MCDU F-PLN = GPS route: %s" % [MCDU.route()])
		_check(str(Props.get_v("mcdu/init/from_to")).ends_with("/" + str(planned.back()) + "/VAPO"), "MCDU INIT FROM/TO: %s" % Props.get_v("mcdu/init/from_to"))
	await _wait(4.0)
	var lat := str(Props.get_v("ap/fma/lateral", ""))
	print("AP lateral %s, GPS to %s brg %.0f, heading %.0f" % [lat, Props.get_v("avionics/gps/ident"), Props.get_f("avionics/gps/brg_mag"), rad_to_deg(Props.get_f("fdm/heading_rad"))])
	if _ac != "c172p":
		_check(lat == "NAV" and str(Props.get_v("avionics/gps/ident")) == str(after[0]), "NAV flies the edited route (%s to %s)" % [lat, Props.get_v("avionics/gps/ident")])
	_key(KEY_N)
	await _wait(1.2)
	await _shot("map_after")
	print("DONE %s: %d failed checks" % [_ac, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## The map's title label must not lie under the radio bar or the flight-data bar.
func _title_check(map: Control, when: String) -> void:
	var title: Rect2 = map._strip.title.get_global_rect()
	var hits: Array = []
	for n in get_tree().get_nodes_in_group(MapStrip.CLEAR_GROUP):
		if n is Control and n.is_visible_in_tree() and (n as Control).get_global_rect().intersects(title):
			hits.append(n.name)
	_check(hits.is_empty() and title.size.x >= 150.0, "%s: the map title %s is clear of the top bars %s and readable" % [when, title, hits])
	var under: Array = []
	for n in get_tree().get_nodes_in_group(MapStrip.BOTTOM_GROUP):
		if n is Control and n.is_visible_in_tree() and (n as Control).get_global_rect().intersects(map.get_global_rect()):
			under.append((n as Control).get_global_rect())
	_check(under.is_empty(), "%s: the attribution line is clear of the map %s %s" % [when, map.get_global_rect(), under])


func _gps() -> Array:
	return [str(Props.get_v("controls/gps/target", ""))] + Array(Props.get_v("controls/gps/route_next", []))


func _check(ok: bool, what: String) -> void:
	print("CHECK %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


## Window pixels of `local` in `ctl` (UI scale and Retina included).
func _px(ctl: Control, local: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * (ctl.get_global_transform_with_canvas() * local)


func _button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _move(at: Vector2, rel: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(e)


func _click(ctl: Control, local: Vector2) -> void:
	var at := _px(ctl, local)
	_move(at, Vector2.ZERO, false)
	await get_tree().process_frame
	_button(at, true)
	await get_tree().process_frame
	_button(at, false)
	await get_tree().process_frame


func _drag(ctl: Control, from_local: Vector2, to_local: Vector2) -> void:
	var a := _px(ctl, from_local)
	var b := _px(ctl, to_local)
	_move(a, Vector2.ZERO, false)
	await get_tree().process_frame
	_button(a, true)
	await get_tree().process_frame
	for k in range(1, 9):
		_move(a.lerp(b, k / 8.0), (b - a) / 8.0, true)
		await get_tree().process_frame
	await _shot("map_dragging")
	_button(b, false)
	await get_tree().process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var p := _out.path_join("live_%s_%s%s.png" % [_ac, OS.get_environment("FREESIM_TAG"), tag])
	get_viewport().get_texture().get_image().save_png(p)
	print("saved ", p)
