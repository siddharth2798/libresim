class_name MiniMap
extends Control
## Round mini-map for outside views: the moving map (N, ui/moving_map.gd) in a disc that always
## keeps the aircraft in the middle. It is a piece of the 2D panel overlay (panel.json overlay item
## "minimap", ui/panel_overlay.gd), so it shows only in outside views and in the layouts that list it.
## Drag moves it, wheel zooms, Shift+wheel resizes, right-click = north up / heading up,
## double-click opens the full map. Place, size, zoom and orientation are saved in user://ui.cfg.
## ui/minimap_grab is true while the pointer is over the disc or drags it (the mouse yoke holds still).
## Imagery, airports, navaids and the track come from the full map (its tiles, db, runways, track()).
## In the Custom layout (`custom`) the layout owns the place: a drag or resize emits `arranged(rect)` instead.

const CFG := "user://ui.cfg"
const MIN_D := 160.0  # diameter limits, UI units
const MAX_D := 640.0
const ZOOM_STEP := 1.25
const RESIZE_STEP := 1.1
const DEFAULT_ACROSS_NM := 12.0

signal arranged(rect: Rect2)  # moved or resized by the player while `custom`

var source: Control  # ui/moving_map.gd
var view := MapView.new()
var heading_up := false
var placed := false  # moved or resized by the player: their spot wins over the layout's anchor
var custom := false  # the Custom layout gives the place (place() takes it as it is)

var _canvas: Control
var _centre_frac := Vector2.ZERO  # saved centre as a fraction of the screen
var _d_frac := 0.0  # saved diameter as a fraction of the screen height
var _across := DEFAULT_ACROSS_NM
var _drag := false
var _plan := RoutePlan.new()
var _plan_key := ""


func _init() -> void:
	name = "MiniMap"
	mouse_filter = MOUSE_FILTER_STOP
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY  # the disc drawn in _draw() masks the map
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tooltip_text = "Drag to move · wheel zoom · Shift+wheel size · right-click north/heading up · double-click full map (N)"
	_canvas = Control.new()
	_canvas.mouse_filter = MOUSE_FILTER_IGNORE
	_canvas.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		placed = bool(cf.get_value("minimap", "placed", false))
		_centre_frac = cf.get_value("minimap", "centre", Vector2.ZERO)
		_d_frac = float(cf.get_value("minimap", "diameter", 0.0))
		_across = float(cf.get_value("minimap", "across_nm", DEFAULT_ACROSS_NM))
		heading_up = bool(cf.get_value("minimap", "heading_up", false))


## Put the disc in `r` (the layout's spot), or where the player left it.
func place(r: Rect2) -> void:
	var vs := get_viewport_rect().size
	if placed and _d_frac > 0.0 and not custom:
		var d := _clamp_d(_d_frac * vs.y)
		r = Rect2(_centre_frac * vs - Vector2(d, d) * 0.5, Vector2(d, d))
	size = r.size
	position = r.position
	_clamp_on_screen()
	view.size = size
	view.set_across_nm(_across)


func _clamp_d(d: float) -> float:
	return clampf(d, MIN_D, maxf(MIN_D, minf(MAX_D, get_viewport_rect().size.y - 16.0)))


func _clamp_on_screen() -> void:
	var vs := get_viewport_rect().size
	position = position.clamp(Vector2.ZERO, (vs - size).max(Vector2.ZERO))


func _has_point(p: Vector2) -> bool:  # only the disc takes the mouse, not the square's corners
	return p.distance_to(size * 0.5) <= size.x * 0.5


func _here() -> Vector2:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	return Vector2(p.x, p.y)


# ---- input -------------------------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var k: float = pow(ZOOM_STEP if not e.shift_pressed else RESIZE_STEP, e.factor if e.factor > 0.0 else 1.0)
			var bigger: bool = e.button_index == MOUSE_BUTTON_WHEEL_UP
			if e.shift_pressed:
				resize(k if bigger else 1.0 / k)
			else:
				zoom(1.0 / k if bigger else k)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed and e.double_click and source != null:
				_drag = false
				source.visible = true
			else:
				if not e.pressed and _drag and custom:
					arranged.emit(get_rect())
				_drag = e.pressed
				if not e.pressed:
					_save()
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			heading_up = not heading_up
			_save()
	elif e is InputEventMouseMotion and _drag:
		move_by(e.relative)
	accept_event()


func move_by(d: Vector2) -> void:
	position += d
	_clamp_on_screen()
	_remember_place()


## factor < 1 zooms in.
func zoom(factor: float) -> void:
	view.zoom_at(size * 0.5, factor)
	_across = view.target_m_per_px * size.x / MapView.NM
	_save()


## Grow (factor > 1) or shrink the disc about its centre; the map keeps its range.
func resize(factor: float) -> void:
	var c := position + size * 0.5
	var d := _clamp_d(size.x * factor)
	size = Vector2(d, d)
	position = c - size * 0.5
	_clamp_on_screen()
	view.size = size
	view.set_across_nm(_across)
	_remember_place()
	if custom:
		arranged.emit(get_rect())
	_save()


func _remember_place() -> void:
	if custom:
		return  # arranged() on release
	var vs := get_viewport_rect().size
	placed = true
	_centre_frac = (position + size * 0.5) / vs
	_d_frac = size.x / vs.y


func _save() -> void:
	if not Session.interactive():
		return
	var cf := ConfigFile.new()
	cf.load(CFG)
	cf.set_value("minimap", "placed", placed)
	cf.set_value("minimap", "centre", _centre_frac)
	cf.set_value("minimap", "diameter", _d_frac)
	cf.set_value("minimap", "across_nm", _across)
	cf.set_value("minimap", "heading_up", heading_up)
	cf.save(CFG)


# ---- frame -------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	var on := is_visible_in_tree()
	Props.set_v("ui/minimap_grab", on and (_drag or _has_point(get_local_mouse_position())))  # the mouse yoke holds still
	if not on or source == null or source.tiles == null:
		return
	view.size = size
	source.tiles.process()
	view.step(dt)
	var want_rot := -Props.get_f("fdm/heading_rad") if heading_up else 0.0
	view.rot = lerp_angle(view.rot, want_rot, 1.0 - exp(-9.0 * dt))
	view.centre = _here()
	var next: Array = Props.get_v("controls/gps/route_next", [])
	var target := str(Props.get_v("controls/gps/target", ""))
	var key := target + "|" + ",".join(PackedStringArray(next))
	if key != _plan_key and source.db != null:
		_plan_key = key
		_plan = RoutePlan.from_idents(target, next, source.db.position_of)
	queue_redraw()
	_canvas.queue_redraw()


func _draw() -> void:  # the clip mask
	draw_circle(size * 0.5, size.x * 0.5, Color.WHITE, true, -1.0, true)


func _draw_map() -> void:
	if source == null or source.tiles == null or source.db == null:
		return
	var c := _canvas
	var font := ThemeDB.fallback_font
	var mid := size * 0.5
	var r := size.x * 0.5
	c.draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.12))
	var level := MapView.level_for(view.physical_m_per_px(UiScale.factor), source.tiles.cache.levels.size())
	source.tiles.draw(c, view, level, Color(0.88, 0.88, 0.88))
	var here := _here()
	var legs := _plan.legs(here)
	var taken: Array = []
	MapRouteLayer.reserve(view, legs, font, taken)
	MapFeatures.draw_airports(c, view, source.db, source.runways, font, taken)
	MapFeatures.draw_navaids(c, view, source.db, font, taken)
	MapFeatures.draw_ils(c, view, source.db, font, taken)
	MapFeatures.draw_track(c, view, source.track())
	MapRouteLayer.draw(c, view, legs, Props.get_f("fdm/groundspeed_mps"), font, taken)
	MapFeatures.draw_aircraft(c, view.to_px(here), Props.get_f("fdm/heading_rad"), view.rot)
	# rim, north mark on the rim, range
	c.draw_arc(mid, r - 2.0, 0.0, TAU, 96, Color(1, 1, 1, 0.6), 3.0, true)
	var up := Vector2(0, -1).rotated(view.rot)
	var side := Vector2(-up.y, up.x)
	c.draw_colored_polygon(PackedVector2Array([mid + up * (r - 4.0), mid + up * (r - 18.0) + side * 7.0,
		mid + up * (r - 18.0) - side * 7.0]), Color(0.95, 0.25, 0.2))
	var ts := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	MapStyle.text(c, font, "N", mid + up * (r - 28.0) + Vector2(-ts.x * 0.5, ts.y * 0.35), 12, Color.WHITE)
	MapStyle.pill(c, font, "%s nm" % _nm_text(view.across_nm()), Vector2(mid.x, size.y - 24.0), 12, Color.WHITE, MapStyle.PANEL)


static func _nm_text(nm: float) -> String:
	return "%.1f" % nm if nm < 10.0 else "%d" % int(round(nm))
