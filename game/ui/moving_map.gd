extends Control
## Moving map (N): north-up satellite map (terrain imagery tiles at a level matching
## the zoom) with airports & runways, VOR/NDB, ILS feathers, the aircraft and its track,
## and the GPS direct-to line. Wheel zooms, click an airport/navaid = GPS direct-to.

const NM := 1852.0

var db: NavDatabase
var runways: Array = []
var cache: TerrainTileCache
var _m_per_px := 120.0
var _tex := {}  # Vector3i -> ImageTexture
var _track: Array[Vector2] = []
var _track_t := 0.0


func setup(nav_db: NavDatabase, ab: AirportBuilder, c: TerrainTileCache) -> void:
	db = nav_db
	cache = c
	runways = ab.data.runways if ab.data else []
	visible = false
	clip_contents = true  # tile imagery is drawn past the edge of the map otherwise
	anchor_left = 0.42
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = -10
	offset_top = 40
	offset_bottom = -40
	mouse_filter = MOUSE_FILTER_STOP


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_N:
		visible = not visible


func _here() -> Vector2:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	return Vector2(p.x, p.y)


func _to_px(w: Vector2) -> Vector2:
	var d := (w - _here()) / _m_per_px
	return size * 0.5 + Vector2(d.x, -d.y)


func _process(dt: float) -> void:
	_track_t -= dt
	if _track_t <= 0.0:
		_track_t = 2.0
		_track.append(_here())
		if _track.size() > 600:
			_track.pop_front()
	if visible:
		queue_redraw()


func _tile_tex(level: int, tx: int, ty: int) -> Texture2D:
	var k := Vector3i(level, tx, ty)
	if _tex.has(k):
		return _tex[k]
	var p := Paths.data("terrain/img/%d/%d_%d.dds" % [level, tx, ty])
	var t: Texture2D = null
	if FileAccess.file_exists(p):
		var img := Image.new()
		if img.load_dds_from_buffer(FileAccess.get_file_as_bytes(p)) == OK:
			t = ImageTexture.create_from_image(img)
	_tex[k] = t
	if _tex.size() > 120:
		_tex.erase(_tex.keys()[0])
	return t


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.12, 0.92))
	# imagery: choose the level whose 768 px tiles are closest to screen resolution
	var level := clampi(int(round(log(_m_per_px / 10.0) / log(2.0))), 0, cache.levels.size() - 1)
	var ts := cache.level_size(level)
	var half := size * 0.5 * _m_per_px
	var c := _here()
	for ty in range(floori((c.y - half.y) / ts), floori((c.y + half.y) / ts) + 1):
		for tx in range(floori((c.x - half.x) / ts), floori((c.x + half.x) / ts) + 1):
			if not cache.has_tile(level, tx, ty):
				continue
			# region tiles may lack imagery: draw the ancestor's on a sub-rect
			var node := Vector3i(level, tx, ty)
			var src := cache.tmeta.tex_source(level, tx, ty, TerrainMeta.HAS_IMG)
			var t := _tile_tex(src.x, src.y, src.z) if src != TerrainMeta.NONE else null
			if t:
				var r := TerrainMeta.sub_rect(node, src)
				var w := float(t.get_width())
				var a := _to_px(Vector2(tx * ts, (ty + 1) * ts))
				draw_texture_rect_region(t, Rect2(a, Vector2(ts, ts) / _m_per_px), Rect2((r.x) * w, (r.y - r.z) * w, r.z * w, r.z * w), Color(0.85, 0.85, 0.85))
	# runways, airports
	for r in runways:
		draw_line(_to_px(Vector2(r.ends[0].x, r.ends[0].y)), _to_px(Vector2(r.ends[1].x, r.ends[1].y)), Color.WHITE, maxf(3.0, r.width / _m_per_px), true)
	var font := ThemeDB.fallback_font
	for a in db.airports:
		var p := _to_px(Vector2(a.x, a.y))
		if Rect2(Vector2.ZERO, size).has_point(p) and a.type != "heliport":
			draw_arc(p, 9, 0, TAU, 16, Color(0.4, 0.8, 1.0), 2.0)
			draw_string(font, p + Vector2(11, 4), a.icao if a.icao != "" else a.ident, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.9, 1))
	for v in db.vors:
		var p2 := _to_px(Vector2(v.x, v.y))
		draw_colored_polygon(PackedVector2Array([p2 + Vector2(-7, 0), p2 + Vector2(-3, -6), p2 + Vector2(3, -6), p2 + Vector2(7, 0), p2 + Vector2(3, 6), p2 + Vector2(-3, 6)]), Color(0.2, 0.5, 1.0))
		draw_string(font, p2 + Vector2(9, -6), "%s %.2f" % [v.ident, v.mhz], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.75, 1))
	for n in db.ndbs:
		var p3 := _to_px(Vector2(n.x, n.y))
		draw_circle(p3, 5, Color(0.8, 0.3, 0.8))
		draw_string(font, p3 + Vector2(8, -6), "%s %.0f" % [n.ident, n.khz], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.6, 0.9))
	for s in db.ils:
		var th := Vector2(s.threshold.x, s.threshold.y)
		var back := -Vector2(sin(deg_to_rad(s.course_true)), cos(deg_to_rad(s.course_true))) * 10.0 * NM
		for k in [-1.0, 1.0]:
			draw_line(_to_px(th), _to_px(th + back.rotated(deg_to_rad(2.5 * k))), Color(0.4, 1.0, 0.4, 0.7), 1.5)
		draw_string(font, _to_px(th + back * 0.6) + Vector2(4, 0), "%s %.2f*" % [s.ident, s.mhz], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 1, 0.5))
	# GPS line, track, aircraft
	var tgt: String = str(Props.get_v("avionics/gps/ident", ""))
	if tgt != "":
		for a in db.airports + db.vors + db.ndbs:
			if a.get("ident") == tgt or a.get("icao") == tgt:
				draw_line(size * 0.5, _to_px(Vector2(a.x, a.y)), Color(1, 0.3, 1), 2.0)
				break
	for i in range(1, _track.size()):
		draw_line(_to_px(_track[i - 1]), _to_px(_track[i]), Color(1, 1, 0.3, 0.6), 1.5)
	var hd := Props.get_f("fdm/heading_rad")
	var f := Vector2(sin(hd), -cos(hd))
	var rgt := Vector2(-f.y, f.x)
	var c0 := size * 0.5
	draw_colored_polygon(PackedVector2Array([c0 + f * 12, c0 - f * 8 + rgt * 8, c0 - f * 4, c0 - f * 8 - rgt * 8]), Color(1, 0.9, 0.2))
	draw_string(font, Vector2(10, 20), "MAP  %.1f nm across · wheel zoom · click = GPS direct-to · N close" % (size.x * _m_per_px / NM), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var note := "* ILS frequencies are simulated" if not db.ils.is_empty() else ""
	draw_string(font, Vector2(10, size.y - 10), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	if e.button_index == MOUSE_BUTTON_WHEEL_UP:
		_m_per_px = maxf(_m_per_px / 1.3, 8.0)
	elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_m_per_px = minf(_m_per_px * 1.3, 3000.0)
	elif e.button_index == MOUSE_BUTTON_LEFT:
		var best := ""
		var bd := 24.0
		for a in db.airports:
			var d: float = _to_px(Vector2(a.x, a.y)).distance_to(e.position)
			if d < bd:
				bd = d
				best = a.icao if a.icao != "" else a.ident
		for v in db.vors + db.ndbs:
			var d2: float = _to_px(Vector2(v.x, v.y)).distance_to(e.position)
			if d2 < bd:
				bd = d2
				best = v.ident
		if best != "":
			Props.set_v("controls/gps/target", best)
	accept_event()
