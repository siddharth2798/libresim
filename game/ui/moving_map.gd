extends Control
## Moving map (N): a large overlay with satellite imagery, weather radar, airports, VOR / NDB, ILS feathers, the
## aircraft, its track and the magenta GPS route line. Opens centred on the aircraft, about 20 nm
## across (wider if a route is set, so the route fits). Wheel zooms around the cursor, +/- keys
## and buttons too; drag pans; Space follows the aircraft again; O toggles north up / heading up.
## Click an airport or navaid = GPS direct-to; Shift+click adds it to the route; Backspace clears.
## "Edit route" (toggle): the planned route ahead is edited on the map as on the Route step (MapRouteEdit: drag a
## waypoint, drag a leg to add one, click to add, right-click to remove), live into the GPS; wheel zoom and pan stay.
## Props: controls/gps/target + controls/gps/route_next (see Gps / RoutePlan), route/rev, ui/map_open.
## View maths in MapView, imagery in MapTiles, symbols in MapFeatures, route in MapRouteLayer.

const MARGIN := 28.0  # UI units of the window left around the map
const CLICK_SLOP := 6.0  # px of movement that turns a click into a pan
const ZOOM_STEP := 1.25
const RECENTER_S := 0.45  # a recentre glides for this long, then the map locks to the aircraft
const HINT := "Wheel or +/- zoom   ·   drag to pan   ·   click airport = direct-to   ·   Shift+click = add to route   ·   N close"
const EDIT_HINT := "Click: add a point   ·   drag a waypoint: move   ·   drag a leg: insert   ·   right-click: remove   ·   Shift+click airport: destination"

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
var _strip: MapStrip  # title line and buttons
var _edit: MapRouteEdit  # the "Edit route" mode (editor())


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
	_strip = MapStrip.new()
	_strip.pressed.connect(_on_button)
	add_child(_strip)
	_title = _strip.title
	_sync_buttons()


func _on_button(id: String) -> void:
	match id:
		"in": _zoom(view.size * 0.5, 1.0 / ZOOM_STEP)
		"out": _zoom(view.size * 0.5, ZOOM_STEP)
		"follow": _set_follow(not follow)
		"orient": heading_up = not heading_up
		"fit": _fit_route()
		"clear": _clear_route()
		"edit": editor().set_on(not editor().on)
		"close": visible = false
	_sync_buttons()


func _sync_buttons() -> void:
	if _strip != null:
		_strip.sync(follow, heading_up, not _plan.is_empty(), editing())


# ---- state -------------------------------------------------------------------------------------

func _here() -> Vector2:
	return RouteLive.here()


## Breadcrumb track (ENU points, one every 2 s), shared with the mini-map.
func track() -> Array:
	return _track


func _on_visibility() -> void:
	Props.set_v("ui/map_open", visible)
	if _edit != null:
		_edit.set_on(false)  # the map always opens in its plain mode
	if visible:
		_open_view()


## The route editor of the "Edit route" mode, made on first use.
func editor() -> MapRouteEdit:
	if _edit == null:
		_edit = MapRouteEdit.new(view)
		_edit.panned.connect(func(rel):
			view.pan_px(rel)
			if follow:
				follow = false
				_sync_buttons())
	_edit.db = db
	return _edit


func editing() -> bool: return _edit != null and _edit.on


## Centre on the aircraft at about 20 nm across, wider so a set route fits.
func _open_view() -> void:
	clear_top(true)
	view.size = size if size.x > 64.0 else get_viewport_rect().size - Vector2(MARGIN, MARGIN) * 2.0
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


## Edges clear of the top bars (only moves down while open; `reset` at opening) and the attribution line (MapStrip).
func clear_top(reset := false) -> void:
	offset_top = maxf(MARGIN if reset else offset_top, maxf(MARGIN, MapStrip.top_clear(self) + 6.0))
	offset_bottom = -maxf(MARGIN, MapStrip.bottom_clear(self) + 4.0)


func _set_follow(on: bool) -> void:
	if on and not follow:
		_glide = RECENTER_S
	follow = on


func _say(s: String) -> void:
	_msg = s
	_msg_t = 4.0


func _refresh_plan() -> void:
	var next: Array = Props.get_v("controls/gps/route_next", [])
	var target := str(Props.get_v("controls/gps/target", ""))
	var key := "%s|%s|%d" % [target, ",".join(PackedStringArray(next)), int(Props.get_v(RouteSetup.REV_PROP, 0))]
	if key != _plan_key and db != null:
		_plan_key = key
		_plan = RoutePlan.from_idents(target, next, db.position_of)
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
	var wheel: bool = e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	if editing() and not wheel and editor().input(e):
		_pressed = false
		accept_event()
		return
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
	clear_top()
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
	if editing():
		_edit.refresh(_here())
	_title.text = ("EDIT ROUTE  ·  " if editing() else "") + "MAP  %s nm across  ·  %s  ·  %s" % [_nm_text(view.across_nm()), "heading up" if heading_up else "north up", "following" if follow else "free"]
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
	var legs := _edit.shown_legs() if editing() else _plan.legs(_here())
	var taken: Array = []  # label rects placed so far: the route's names win, then airports, navaids, ILS
	MapRouteLayer.reserve(view, legs, font, taken, MapFeatures.marker_rects(view, db) + MapRouteLayer.chrome_rects(size, _strip.get_rect() if _strip else Rect2()))
	MapFeatures.draw_airports(self, view, db, runways, font, taken)
	MapFeatures.draw_navaids(self, view, db, font, taken)
	MapFeatures.draw_ils(self, view, db, font, taken)
	MapFeatures.draw_track(self, view, _track)
	var here := _here()
	MapRouteLayer.draw(self, view, legs, Props.get_f("fdm/groundspeed_mps"), font, taken)
	if editing():
		_edit.gestures.draw_snap(self)
	if _ping_t < 1.3:
		var pp := view.to_px(_ping)
		var a := 1.0 - _ping_t / 1.3
		draw_arc(pp, 14.0 + _ping_t * 40.0, 0.0, TAU, 32, Color(1, 1, 1, a), 3.0, true)
	MapFeatures.draw_aircraft(self, view.to_px(here), Props.get_f("fdm/heading_rad"), view.rot)
	MapFeatures.draw_north(self, Vector2(size.x - 44.0, 92.0), view.rot, font)
	MapFeatures.draw_scale_bar(self, view, Vector2(24.0, size.y - 56.0), font)
	var msg := _msg if _msg_t > 0.0 else (_edit.msg if editing() and _edit.msg != "" else "")
	var hint := msg if msg != "" else (EDIT_HINT if editing() else HINT)
	MapRouteLayer.draw_footer(self, size, legs, Props.get_f("fdm/groundspeed_mps"), font, hint,
		Color(1, 1, 0.8) if msg != "" else Color(0.9, 0.9, 0.9), not db.ils.is_empty() and view.across_nm() <= MapFeatures.SHOW_ILS_NM)
	draw_rect(Rect2(Vector2.ZERO, size), Color(MapStyle.ROUTE, 0.9) if editing() else Color(1, 1, 1, 0.3), false, 4.0 if editing() else 2.0)


static func _nm_text(nm: float) -> String:
	return "%.2f" % nm if nm < 1.0 else ("%.1f" % nm if nm < 100.0 else "%d" % int(round(nm)))
