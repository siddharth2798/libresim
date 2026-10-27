extends Control
## Moving map (N): a large overlay with satellite imagery, airports, VOR / NDB, ILS feathers, the
## aircraft, its track and the magenta GPS route line. Opens centred on the aircraft, about 20 nm
## across (wider if a route is set, so the route fits). Wheel zooms around the cursor, +/- keys
## and buttons too; drag pans; Space follows the aircraft again; O toggles north up / heading up.
## Click an airport or navaid = GPS direct-to; Shift+click adds it to the route; Backspace clears.
## Props: controls/gps/target + controls/gps/route_next (see Gps / RoutePlan), ui/map_open.
## View maths in MapView, imagery in MapTiles, symbols in MapFeatures, route in MapRouteLayer.

const MARGIN := 28.0  # UI units of the window left around the map
const CLICK_SLOP := 6.0  # px of movement that turns a click into a pan
const ZOOM_STEP := 1.25
const RECENTER_S := 0.45  # a recentre glides for this long, then the map locks to the aircraft

var db: NavDatabase
var runways: Array = []
var cache: TerrainTileCache
var view := MapView.new()
var tiles: MapTiles
var follow := true
var heading_up := false

var _track: Array = []
var _track_t := 0.0
var _plan := RoutePlan.new()
var _plan_key := ""
var _press := Vector2.ZERO
var _pressed := false
var _dragging := false
var _glide := 0.0
var _ping := Vector2.ZERO
var _ping_t := 99.0
var _msg := ""
var _msg_t := 0.0
var _title: Label
var _btn := {}  # name -> Button


func setup(nav_db: NavDatabase, ab: AirportBuilder, c: TerrainTileCache) -> void:
	db = nav_db
	cache = c
	tiles = MapTiles.new(c)
	runways = ab.data.runways if ab.data else []
	visible = false
	clip_contents = true  # tile imagery is drawn past the edge of the map otherwise
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = -MARGIN
	mouse_filter = MOUSE_FILTER_STOP
	_build_strip()
	visibility_changed.connect(_on_visibility)
	Props.set_v("ui/map_open", false)


func _exit_tree() -> void:
	if tiles:
		tiles.free_tasks()


func _build_strip() -> void:
	var strip := PanelContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = MapStyle.PANEL
	sb.set_content_margin_all(6.0)
	strip.add_theme_stylebox_override("panel", sb)
	add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	strip.add_child(row)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	row.add_child(_title)
	for spec in [["out", "-", "Zoom out (-)"], ["in", "+", "Zoom in (+)"], ["follow", "Follow", "Keep the aircraft in the middle (Space)"],
			["orient", "North up", "North up / heading up (O)"], ["fit", "Fit route", "Show the whole route (G)"],
			["clear", "Clear route", "Cancel direct-to and route (Backspace)"], ["close", "Close (N)", "Close the map (N)"]]:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE  # Space and Enter must not press a button
		b.toggle_mode = spec[0] in ["follow", "orient"]
		b.pressed.connect(_on_button.bind(spec[0]))
		row.add_child(b)
		_btn[spec[0]] = b
	_sync_buttons()


func _on_button(id: String) -> void:
	match id:
		"in": _zoom(view.size * 0.5, 1.0 / ZOOM_STEP)
		"out": _zoom(view.size * 0.5, ZOOM_STEP)
		"follow": _set_follow(not follow)
		"orient": heading_up = not heading_up
		"fit": _fit_route()
		"clear": _clear_route()
		"close": visible = false
	_sync_buttons()


func _sync_buttons() -> void:
	if _btn.is_empty():
		return
	_btn.follow.set_pressed_no_signal(follow)
	_btn.orient.set_pressed_no_signal(heading_up)
	_btn.orient.text = "Heading up" if heading_up else "North up"
	_btn.fit.disabled = _plan.is_empty()
	_btn.clear.disabled = _plan.is_empty()


# ---- state -------------------------------------------------------------------------------------

func _here() -> Vector2:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	return Vector2(p.x, p.y)


func _view_size() -> Vector2:
	return size if size.x > 64.0 else get_viewport_rect().size - Vector2(MARGIN, MARGIN) * 2.0


func _on_visibility() -> void:
	Props.set_v("ui/map_open", visible)
	if visible:
		_open_view()


## Centre on the aircraft at about 20 nm across, wider so a set route fits.
func _open_view() -> void:
	view.size = _view_size()
	follow = true
	_pressed = false
	_glide = 0.0
	view.centre = _here()
	view.rot = -Props.get_f("fdm/heading_rad") if heading_up else 0.0
	_refresh_plan()
	view.m_per_px = view.scale_around(view.centre, _plan.points(), 130.0)
	view.target_m_per_px = view.m_per_px
	_msg = ""
	_sync_buttons()


## Scene setup for screenshots: keys across_nm, heading_up, centre_on (ident), follow.
func apply_view(d: Dictionary) -> void:
	_open_view()
	heading_up = bool(d.get("heading_up", heading_up))
	view.rot = -Props.get_f("fdm/heading_rad") if heading_up else 0.0
	if d.has("across_nm"):
		view.set_across_nm(float(d.across_nm))
	if d.has("centre_on") and db.position_of(str(d.centre_on)) != null:
		view.centre = db.position_of(str(d.centre_on))
		follow = false
	follow = bool(d.get("follow", follow))
	_sync_buttons()


func wait_imagery() -> void:
	tiles.wait_all()


func _set_follow(on: bool) -> void:
	if on and not follow:
		_glide = RECENTER_S
	follow = on


func _say(s: String) -> void:
	_msg = s
	_msg_t = 4.0


func _refresh_plan() -> void:
	var next: Array = Props.get_v("controls/gps/route_next", [])
	var key := str(Props.get_v("controls/gps/target", "")) + "|" + ",".join(PackedStringArray(next))
	if key != _plan_key and db != null:
		_plan_key = key
		_plan = RoutePlan.from_idents(str(Props.get_v("controls/gps/target", "")), next, db.position_of)
		if _btn.has("fit"):
			_sync_buttons()


func _zoom(px: Vector2, factor: float) -> void:
	if follow and px.distance_to(view.size * 0.5) > 24.0:
		follow = false  # zooming at the cursor away from the middle leaves follow mode
		_sync_buttons()
	view.zoom_at(view.size * 0.5 if follow else px, factor)


func _fit_route() -> void:
	var pts: Array = _plan.points() + [_here()]
	if pts.size() > 1:
		view.fit_bounds(pts, 110.0)
		follow = false
		heading_up = false  # the fit is a north-up picture
		view.rot = 0.0
	_sync_buttons()


func _clear_route() -> void:
	Props.set_v("controls/gps/target", "")
	Props.set_v("controls/gps/route_next", [])
	_say("Route cleared")


func _click(px: Vector2, shift: bool) -> void:
	var id := MapFeatures.pick(view, db, px)
	if id == "":
		_say("No airport or navaid there: click one for direct-to (Shift+click adds it to the route)")
		return
	_ping = db.position_of(id)
	_ping_t = 0.0
	var target := str(Props.get_v("controls/gps/target", ""))
	if shift and target != "":
		var next: Array = Props.get_v("controls/gps/route_next", []).duplicate()
		if (next.back() if not next.is_empty() else target) != id:
			next.append(id)
			Props.set_v("controls/gps/route_next", next)
			_say("%s added: leg %d of the route" % [id, next.size() + 1])
	else:
		Props.set_v("controls/gps/target", id)
		Props.set_v("controls/gps/route_next", [])
		_say("Direct-to %s" % id)
	_refresh_plan()
	_sync_buttons()


# ---- input -------------------------------------------------------------------------------------

func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	if e.keycode == KEY_N and not e.echo and not e.shift_pressed and not e.ctrl_pressed:
		visible = not visible
		return
	if not visible or e.ctrl_pressed or e.meta_pressed:
		return
	match e.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: _on_button("in")
		KEY_MINUS, KEY_KP_SUBTRACT: _on_button("out")
		KEY_SPACE: _set_follow(true); _sync_buttons()
		KEY_O: _on_button("orient")
		KEY_G: _on_button("fit")
		KEY_BACKSPACE: _on_button("clear")
		_: return
	get_viewport().set_input_as_handled()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.pressed:
			var k := pow(ZOOM_STEP, e.factor if e.factor > 0.0 else 1.0)
			_zoom(e.position, 1.0 / k if e.button_index == MOUSE_BUTTON_WHEEL_UP else k)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press = e.position
				_pressed = true
				_dragging = false
			else:
				if _pressed and not _dragging:
					_click(e.position, e.shift_pressed)
				_pressed = false
				_dragging = false
	elif e is InputEventMouseMotion and _pressed:
		if not _dragging and e.position.distance_to(_press) > CLICK_SLOP:
			_dragging = true
			if follow:
				follow = false
				_sync_buttons()
		if _dragging:
			view.pan_px(e.relative)
	accept_event()


# ---- frame -------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	_track_t -= dt
	if _track_t <= 0.0:
		_track_t = 2.0
		_track.append(_here())
		if _track.size() > 600:
			_track.pop_front()
	if not visible or tiles == null:
		return
	view.size = size
	tiles.process()
	view.step(dt)
	var want_rot := -Props.get_f("fdm/heading_rad") if heading_up else 0.0
	view.rot = lerp_angle(view.rot, want_rot, 1.0 - exp(-9.0 * dt))
	if follow:
		if _glide > 0.0:
			_glide -= dt
			view.centre = view.centre.lerp(_here(), 1.0 - exp(-14.0 * dt))
		else:
			view.centre = _here()
	_refresh_plan()
	_title.text = "MAP  %s nm across  ·  %s  ·  %s" % [_nm_text(view.across_nm()), "heading up" if heading_up else "north up", "following" if follow else "free"]
	_ping_t += dt
	_msg_t -= dt
	queue_redraw()


func _draw() -> void:
	if db == null or tiles == null:
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.12))
	var level := MapView.level_for(view.physical_m_per_px(UiScale.factor), tiles.cache.levels.size())
	tiles.draw(self, view, level, Color(0.88, 0.88, 0.88))
	var legs := _plan.legs(_here())
	var taken: Array = []  # label rects placed so far: the route's names win, then airports, navaids, ILS
	MapRouteLayer.reserve(view, legs, font, taken)
	MapFeatures.draw_airports(self, view, db, runways, font, taken)
	MapFeatures.draw_navaids(self, view, db, font, taken)
	MapFeatures.draw_ils(self, view, db, font, taken)
	MapFeatures.draw_track(self, view, _track)
	var here := _here()
	MapRouteLayer.draw(self, view, legs, Props.get_f("fdm/groundspeed_mps"), font, taken)
	if _ping_t < 1.3:
		var pp := view.to_px(_ping)
		var a := 1.0 - _ping_t / 1.3
		draw_arc(pp, 14.0 + _ping_t * 40.0, 0.0, TAU, 32, Color(1, 1, 1, a), 3.0, true)
	MapFeatures.draw_aircraft(self, view.to_px(here), Props.get_f("fdm/heading_rad"), view.rot)
	MapFeatures.draw_north(self, Vector2(size.x - 44.0, 92.0), view.rot, font)
	MapFeatures.draw_scale_bar(self, view, Vector2(24.0, size.y - 56.0), font)
	_draw_texts(font, legs)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.3), false, 2.0)


func _draw_texts(font: Font, legs: Array) -> void:
	if not legs.is_empty():
		var ids := PackedStringArray()
		for l in legs:
			ids.append(l.ident)
		var rem: float = legs.back().cum_m
		var s := "ROUTE  %s   %.1f nm   ETE %s" % [" > ".join(ids), rem / MapView.NM, RoutePlan.format_ete(RoutePlan.ete_s(rem, Props.get_f("fdm/groundspeed_mps")))]
		MapStyle.pill(self, font, s, Vector2(size.x * 0.5, size.y - 46.0), 15, Color.WHITE, MapStyle.ROUTE)
	var hint := _msg if _msg_t > 0.0 else "Wheel or +/- zoom   ·   drag to pan   ·   click airport = direct-to   ·   Shift+click = add to route   ·   N close"
	var ts := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	MapStyle.text(self, font, hint, Vector2((size.x - ts.x) * 0.5, size.y - 14.0), 13, Color(1, 1, 0.8) if _msg_t > 0.0 else Color(0.9, 0.9, 0.9))
	if not db.ils.is_empty() and view.across_nm() <= MapFeatures.SHOW_ILS_NM:
		MapStyle.text(self, font, "* ILS frequencies are simulated", Vector2(size.x - 210.0, size.y - 14.0), 12, Color(0.8, 0.8, 0.8))


static func _nm_text(nm: float) -> String:
	return "%.2f" % nm if nm < 1.0 else ("%.1f" % nm if nm < 100.0 else "%d" % int(round(nm)))
