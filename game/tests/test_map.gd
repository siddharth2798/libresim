extends Node
## Moving map logic: view maths (zoom around a point, pan, fit, scale bar, imagery level, clipping),
## the GPS route (sequencing, legs, bearing / ETE), the Gps node following it, picking, imagery fallback.

const NM := 1852.0

var _made: Array = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in _made:
			if is_instance_valid(n):
				n.free()


func _near(a: Vector2, b: Vector2, tol := 0.01) -> bool:
	return a.distance_to(b) <= tol


func test_map_world_screen_round_trip_with_rotation() -> String:
	var v := MapView.new()
	v.centre = Vector2(-55997.0, 37576.0)
	v.m_per_px = 37.0
	for rot in [0.0, 0.7, -2.4]:
		v.rot = rot
		var w := Vector2(-52000.0, 41000.0)
		if not _near(v.to_world(v.to_px(w)), w, 0.05):
			return "round trip failed at rot %.1f" % rot
	v.rot = 0.0
	if not (v.to_px(v.centre + Vector2(0, 1000)).y < v.size.y * 0.5):
		return "north must be up the screen"
	if not (v.to_px(v.centre + Vector2(1000, 0)).x > v.size.x * 0.5):
		return "east must be right of the centre"
	v.rot = -PI * 0.5  # heading east is up: a point to the east appears above the centre
	if not (v.to_px(v.centre + Vector2(1000, 0)).y < v.size.y * 0.5):
		return "heading-up view should put the eastern point up"
	return ""


func test_map_zoom_keeps_the_point_under_the_cursor_and_clamps() -> String:
	var v := MapView.new()
	v.size = Vector2(1200, 700)
	v.set_across_nm(20.0)
	var px := Vector2(900, 200)
	var w := v.to_world(px)
	v.zoom_at(px, 0.5)
	var moving := false
	for i in 200:
		moving = v.step(1.0 / 60.0)
		if not _near(v.to_px(w), px, 0.5):
			return "point drifted from the cursor at step %d" % i
		if not moving:
			break
	if moving or absf(v.across_nm() - 10.0) > 0.01:
		return "ease should end at 10 nm across, got %.2f" % v.across_nm()
	v.zoom_at(px, 0.0001)
	for i in 400:
		v.step(1.0 / 60.0)
	if absf(v.across_nm() - MapView.MIN_ACROSS_NM) > 0.001:
		return "zoom in must stop at %.1f nm, got %.3f" % [MapView.MIN_ACROSS_NM, v.across_nm()]
	v.zoom_at(px, 1.0e6)
	for i in 400:
		v.step(1.0 / 60.0)
	if absf(v.across_nm() - MapView.MAX_ACROSS_NM) > 0.1:
		return "zoom out must stop at %.0f nm, got %.1f" % [MapView.MAX_ACROSS_NM, v.across_nm()]
	return ""


func test_map_ease_is_smooth_not_a_jump() -> String:
	var v := MapView.new()
	v.set_across_nm(20.0)
	v.zoom_at(v.size * 0.5, 0.5)
	v.step(1.0 / 60.0)
	if v.across_nm() >= 20.0 or v.across_nm() <= 10.5:
		return "one frame should move part of the way, got %.2f nm" % v.across_nm()
	return ""


func test_map_pan_follows_the_drag() -> String:
	var v := MapView.new()
	v.centre = Vector2(1000, 1000)
	v.m_per_px = 10.0
	var w := v.to_world(Vector2(300, 300))
	v.pan_px(Vector2(40, -25))  # dragging the map right and up
	if not _near(v.to_px(w), Vector2(340, 275), 0.01):
		return "the map point should have followed the pointer, now at %s" % v.to_px(w)
	v.rot = 0.9
	var w2 := v.to_world(Vector2(500, 100))
	v.pan_px(Vector2(-33, 17))
	if not _near(v.to_px(w2), Vector2(467, 117), 0.01):
		return "pan with a rotated view failed"
	return ""


func test_map_scale_around_fits_route_and_defaults_to_20_nm() -> String:
	var v := MapView.new()
	v.size = Vector2(1200, 700)
	var here := Vector2(5000, 5000)
	var near_mpp := v.scale_around(here, [here + Vector2(3000, 2000)], 100.0)
	if absf(near_mpp * v.size.x / NM - 20.0) > 0.01:
		return "a close target should keep the 20 nm default, got %.2f" % (near_mpp * v.size.x / NM)
	var far := here + Vector2(-80.0 * NM, 30.0 * NM)
	v.m_per_px = v.scale_around(here, [far], 100.0)
	v.centre = here
	var px := v.to_px(far)
	if not Rect2(Vector2.ZERO, v.size).has_point(px):
		return "far waypoint is off screen at %s" % px
	if v.to_px(here).distance_to(v.size * 0.5) > 0.1:
		return "the aircraft must stay in the middle"
	var huge := v.scale_around(here, [here + Vector2(1.0e7, 0)], 100.0)
	if absf(huge * v.size.x / NM - MapView.MAX_ACROSS_NM) > 0.1:
		return "an absurd route is limited to the widest view"
	return ""


func test_map_fit_bounds_centres_and_contains_all() -> String:
	var v := MapView.new()
	v.size = Vector2(1000, 600)
	var pts := [Vector2(0, 0), Vector2(60.0 * NM, 5000.0), Vector2(30.0 * NM, -20000.0)]
	v.fit_bounds(pts, 80.0)
	for p in pts:
		if not Rect2(Vector2(60, 60), v.size - Vector2(120, 120)).has_point(v.to_px(p)):
			return "point %s outside the padded view at %s" % [p, v.to_px(p)]
	return ""


func test_map_scale_bar_and_imagery_level() -> String:
	var s := MapView.nice_scale(37.0, 170.0)  # 170 px = 3.4 nm -> 2 nm
	if s.label != "2 nm" or s.px > 170.0 or s.px < 80.0:
		return "scale bar at 37 m/px: %s" % s
	var s2 := MapView.nice_scale(0.5, 170.0)  # 85 m -> 0.04 nm
	if s2.px > 170.0 or s2.nm <= 0.0:
		return "scale bar at 0.5 m/px: %s" % s2
	var s3 := MapView.nice_scale(300.0, 170.0)  # 27.5 nm -> 20
	if s3.label != "20 nm":
		return "scale bar at 300 m/px: %s" % s3
	if MapView.level_for(10.0, 7) != 0 or MapView.level_for(20.0, 7) != 1 or MapView.level_for(0.4, 7) != 0:
		return "level at 10 / 20 / 0.4 m/px"
	if MapView.level_for(5000.0, 7) != 6:
		return "level must clamp to the coarsest"
	return ""


func test_map_clip_segment() -> String:
	var r := Rect2(0, 0, 100, 100)
	var inside := MapView.clip_segment(Vector2(10, 10), Vector2(90, 20), r)
	if inside.size() != 2 or inside[0] != Vector2(10, 10) or inside[1] != Vector2(90, 20):
		return "a segment inside must be unchanged"
	var cut := MapView.clip_segment(Vector2(-100, 50), Vector2(300, 50), r)
	if cut.size() != 2 or not _near(cut[0], Vector2(0, 50)) or not _near(cut[1], Vector2(100, 50)):
		return "a crossing segment must be cut to the edges: %s" % [cut]
	if not MapView.clip_segment(Vector2(-50, -50), Vector2(-10, 200), r).is_empty():
		return "a segment outside must vanish"
	var diag := MapView.clip_segment(Vector2(-50, 150), Vector2(150, -50), r)
	if diag.size() != 2 or not _near(diag[0], Vector2(0, 100)) or not _near(diag[1], Vector2(100, 0)):
		return "diagonal clip: %s" % [diag]
	return ""


func test_route_bearing_distance_and_ete() -> String:
	if absf(RoutePlan.bearing_deg(Vector2.ZERO, Vector2(0, 100)) - 0.0) > 0.01 or absf(RoutePlan.bearing_deg(Vector2.ZERO, Vector2(100, 0)) - 90.0) > 0.01:
		return "bearing north / east"
	if absf(RoutePlan.bearing_deg(Vector2.ZERO, Vector2(-5, -5)) - 225.0) > 0.01:
		return "bearing south-west"
	if RoutePlan.format_ete(RoutePlan.ete_s(NM * 10.0, 50.0 * 0.514444)) != "12:00":
		return "ETE for 10 nm at 50 kt: %s" % RoutePlan.format_ete(RoutePlan.ete_s(NM * 10.0, 50.0 * 0.514444))
	if RoutePlan.format_ete(3725.0) != "1:02:05":
		return "ETE over an hour"
	if RoutePlan.ete_s(1000.0, 0.0) <= 0.0:
		return "a parked aircraft still gets a finite ETE"
	return ""


func _lookup(ident: String) -> Variant:
	return {"A": Vector2(0, 0), "B": Vector2(10000, 0), "C": Vector2(10000, 20000)}.get(ident)


func test_route_legs_and_sequencing() -> String:
	var rp := RoutePlan.from_idents("B", ["C", "ZZZ"], _lookup)  # ZZZ is unknown and dropped
	if rp.wps.size() != 2 or rp.next_idents() != ["C"]:
		return "route should be B, C; got %s" % [rp.wps]
	var legs := rp.legs(Vector2.ZERO)
	if legs.size() != 2 or not legs[0].active or legs[1].active or absf(legs[1].cum_m - 30000.0) > 0.01:
		return "legs wrong: %s" % [legs]
	if rp.update(Vector2(5000, 0)):
		return "far from B it must not sequence"
	if not rp.update(Vector2(10000.0 - 0.5 * NM, 0)):
		return "within 1 nm of B it must sequence to C"
	if rp.active().ident != "C" or not rp.next_idents().is_empty() or rp.from_pos != Vector2(10000, 0):
		return "after sequencing C is active and the leg starts at B"
	if rp.update(Vector2(10000, 20000)):
		return "the last waypoint is kept (direct-to stays active)"
	if absf(rp.remaining_m(Vector2(10000, 0)) - 20000.0) > 0.01:
		return "remaining distance"
	return ""


func test_gps_follows_route_and_sequences_through_props() -> String:
	var g := Gps.new()
	g.db = NavDatabase.new()
	_made.append(g)
	var a = g.db.position_of("VABB")
	var b = g.db.position_of("VAPO")
	if a == null or b == null:
		return ""  # no airport data on this machine
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("failures/gps", false)
	Props.set_v("fdm/groundspeed_mps", 50.0)
	Props.set_v("fdm/position_enu", Vector3(a.x + 20000.0, a.y, 800.0))
	Props.set_v("controls/gps/target", "VABB")
	Props.set_v("controls/gps/route_next", ["VAPO"])
	g._physics_process(0.01)
	if Props.get_v("avionics/gps/ident") != "VABB" or absf(Props.get_f("avionics/gps/dist_nm") - 20000.0 / NM) > 0.05:
		return "GPS should lead to VABB first"
	Props.set_v("fdm/position_enu", Vector3(a.x + 300.0, a.y, 100.0))
	g._physics_process(0.01)
	if Props.get_v("controls/gps/target") != "VAPO" or not Props.get_v("controls/gps/route_next").is_empty():
		return "passing VABB must make VAPO the target, got %s" % Props.get_v("controls/gps/target")
	if Props.get_v("avionics/gps/ident") != "VAPO":
		return "GPS output must follow the next leg"
	Props.set_v("controls/gps/target", "")
	Props.set_v("controls/gps/route_next", [])
	g._physics_process(0.01)
	if Props.get_v("avionics/gps/ident") != "":
		return "clearing the route clears the GPS"
	return ""


func test_map_pick_finds_the_airport_under_the_click() -> String:
	var db := NavDatabase.new()
	var p = db.position_of("VAPO")
	if p == null:
		return ""
	var v := MapView.new()
	v.size = Vector2(1200, 700)
	v.centre = p
	v.set_across_nm(10.0)
	if MapFeatures.pick(v, db, v.size * 0.5 + Vector2(6, 4)) != "VAPO":
		return "a click on VAPO should pick it"
	if MapFeatures.pick(v, db, Vector2(5, 5)) == "VAPO":
		return "a click far away must not pick VAPO"
	return ""


func test_map_imagery_falls_back_to_a_coarser_tile_while_loading() -> String:
	var cache := TerrainTileCache.new()
	if cache.levels.is_empty():
		return ""
	var tiles := MapTiles.new(cache)
	tiles.preload_coarse()
	tiles.wait_all()
	var db := NavDatabase.new()
	var p = db.position_of("VAPO")
	if p == null:
		tiles.free_tasks()
		return ""
	var ts := cache.level_size(0)
	var c := tiles.cell(0, floori(p.x / ts), floori(p.y / ts))  # level-0 tile is not loaded yet
	var ok: bool = not c.is_empty() and c[0] is Texture2D and c[1].size.x > 0.0 and c[1].size.x <= c[0].get_width()
	tiles.wait_all()
	var c2 := tiles.cell(0, floori(p.x / ts), floori(p.y / ts))
	tiles.free_tasks()
	if not ok:
		return "no coarse fallback while the fine tile loads"
	if c2.is_empty():
		return "the tile never became a texture"
	return ""


func _map_at(db: NavDatabase, ident: String, across_nm: float) -> Control:
	var m: Control = load("res://ui/moving_map.gd").new()
	m.db = db
	add_child(m)
	_made.append(m)
	m.view.size = Vector2(1200, 700)
	m.view.centre = db.position_of(ident)
	m.view.set_across_nm(across_nm)
	m.follow = false
	Props.set_v("controls/gps/target", "")
	Props.set_v("controls/gps/route_next", [])
	return m


func _mouse(m: Control, pressed: bool, pos: Vector2, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.shift_pressed = shift
	m._gui_input(e)


func test_map_click_is_direct_to_and_a_drag_is_not() -> String:
	var db := NavDatabase.new()
	if db.position_of("VAPO") == null:
		return ""
	var m := _map_at(db, "VAPO", 10.0)
	var c: Vector2 = m.view.size * 0.5
	_mouse(m, true, c)
	_mouse(m, false, c)
	if Props.get_v("controls/gps/target") != "VAPO":
		return "a click on VAPO should set the direct-to"
	Props.set_v("controls/gps/target", "")
	_mouse(m, true, c)
	var mv := InputEventMouseMotion.new()
	mv.position = c + Vector2(60, 0)
	mv.relative = Vector2(60, 0)
	m._gui_input(mv)
	_mouse(m, false, c + Vector2(60, 0))
	if Props.get_v("controls/gps/target") != "":
		return "a drag must not set a direct-to"
	if m.follow:
		return "a pan leaves follow mode"
	if m.view.centre.x >= db.position_of("VAPO").x:
		return "dragging the map right moves the centre west"
	return ""


func test_map_shift_click_builds_a_route_and_clear_removes_it() -> String:
	var db := NavDatabase.new()
	if db.position_of("VAPO") == null or db.position_of("VABB") == null:
		return ""
	var m := _map_at(db, "VAPO", 250.0)
	_mouse(m, true, m.view.to_px(db.position_of("VAPO")))
	_mouse(m, false, m.view.to_px(db.position_of("VAPO")))
	var pb: Vector2 = m.view.to_px(db.position_of("VABB"))
	_mouse(m, true, pb, true)
	_mouse(m, false, pb, true)
	if Props.get_v("controls/gps/target") != "VAPO" or Props.get_v("controls/gps/route_next") != ["VABB"]:
		return "route should be VAPO then VABB, got %s %s" % [Props.get_v("controls/gps/target"), Props.get_v("controls/gps/route_next")]
	m._plan_key = ""
	m._refresh_plan()
	if m._plan.wps.size() != 2:
		return "the map should show both legs"
	m._on_button("clear")
	if Props.get_v("controls/gps/target") != "" or not Props.get_v("controls/gps/route_next").is_empty():
		return "clear route must cancel the target and the legs"
	return ""
