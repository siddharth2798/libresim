class_name RouteMap
extends Control
## The map of the Route step: north-up, satellite imagery dimmed under the symbols (MapTiles, when the terrain data is
## there and a display is), faint published airways, airway fixes (small), airports and VOR / NDB (MapFeatures), and the
## route in magenta (MapRouteLayer: legs with course, distance and time, a marker per waypoint, the selected one ringed).
## The departure has a green ring, the destination an accent one. It holds no route: the page hands it the legs
## (RouteEdit.legs) and turns its signals into edits:
##   left click            clicked(world, ident, shift): ident = airport / navaid / fix under the cursor, "" = empty map
##   click a waypoint      wp_selected(i)
##   drag a waypoint       wp_dragged(i, world, ident): dropped on a named point = that point, else a free waypoint there
##   drag a leg            leg_dragged(insert_at, world, ident): a new waypoint on that leg
##   right click waypoint  wp_removed(i)
##   wheel / + -           zoom at the cursor;  drag empty map / arrows: pan;  F or the Fit button: show the whole route
## The gestures are RouteGestures (shared with the N map's edit mode). View maths: MapView. Drawing: MapStyle, RouteMapLayers.

signal clicked(world: Vector2, ident: String, shift: bool)
signal wp_selected(index: int)
signal wp_dragged(index: int, world: Vector2, ident: String)
signal leg_dragged(insert_at: int, world: Vector2, ident: String)
signal wp_removed(index: int)

const ZOOM_STEP := 1.25
const PAN_STEP := 60.0
const BG := Color(0.035, 0.05, 0.075)

var view := MapView.new()
var db: NavDatabase
var runways: Array = []  # [{ends: [{x, y}, {x, y}], width}] for MapFeatures.draw_airports
var legs: Array = []  # RouteEdit.legs()
var dep := {}  # {id, pos, label} of the departure, {} when unknown
var dest := {}  # {id, pos} of the destination, {} when none
var selected := -1  # wps index of the selected waypoint (-2 = destination)
var tas_mps := 60.0  # ETE speed of the leg labels
var aircraft := {}  # {pos, hdg (rad)}: the aircraft symbol (the in-flight editor), {} = none
var fit_btn: Button
var gestures := RouteGestures.new(view)  # mouse -> the signals above (shared with the N map's edit mode)

var _tiles: MapTiles
var _want_fit := true


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	custom_minimum_size = Vector2(320, 240)
	tooltip_text = "Click: add a point  ·  drag a waypoint: move it  ·  drag a leg: add a waypoint on it  ·  right-click: remove\nShift+click an airport: fly there  ·  wheel or + / -: zoom  ·  drag the empty map or arrows: pan  ·  F: fit"
	fit_btn = Button.new()
	fit_btn.text = "Fit"
	fit_btn.tooltip_text = "Show the whole route (F)"
	fit_btn.focus_mode = Control.FOCUS_NONE  # the map itself takes F
	MenuTheme.style_quiet(fit_btn)
	fit_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fit_btn.offset_left = -64
	fit_btn.offset_right = -10
	fit_btn.offset_top = 10
	fit_btn.offset_bottom = 44
	fit_btn.pressed.connect(fit)
	add_child(fit_btn)
	resized.connect(_on_resized)
	gestures.clicked.connect(func(w, id, sh): clicked.emit(w, id, sh))
	gestures.wp_selected.connect(func(i): wp_selected.emit(i))
	gestures.wp_dragged.connect(func(i, w, id): wp_dragged.emit(i, w, id))
	gestures.leg_dragged.connect(func(i, w, id): leg_dragged.emit(i, w, id))
	gestures.wp_removed.connect(func(i): wp_removed.emit(i))
	gestures.panned.connect(func(rel): view.pan_px(rel))


func _exit_tree() -> void:
	if _tiles != null:
		_tiles.free_tasks()


## New route to show; `refit` frames it (a new destination, an auto-route, a typed route).
func show_route(new_legs: Array, dep_pt: Dictionary, dest_pt: Dictionary, sel: int, refit := false) -> void:
	legs = new_legs
	dep = dep_pt
	dest = dest_pt
	selected = sel
	if refit:
		_want_fit = true
		_on_resized()
	queue_redraw()


## Frame the departure, every waypoint and the destination (only the departure: 120 nm around it).
func fit() -> void:
	view.size = size
	var pts := route_points()
	if pts.size() >= 2:
		view.fit_bounds(pts, 70.0)
	elif not pts.is_empty():
		view.centre = pts[0]
		view.set_across_nm(120.0)
	queue_redraw()


## The legs as drawn now: the latest show_route() legs (not the ones of the last mouse event), bent while dragging.
func drawn_legs() -> Array:
	gestures.legs = legs
	return gestures.shown_legs(selected)


## The departure to ring: none when the aircraft symbol marks the start (in flight the route starts at PPOS, no airport).
func ring_dep() -> Dictionary:
	return {} if not aircraft.is_empty() else dep


func route_points() -> Array:
	var pts := []
	if not dep.is_empty():
		pts.append(dep.pos)
	for l in legs:
		pts.append(l.b)
	if not dest.is_empty() and not pts.has(dest.pos):
		pts.append(dest.pos)
	return pts


func _on_resized() -> void:
	view.size = size
	if _want_fit and size.x > 10.0 and size.y > 10.0:
		_want_fit = false
		fit()


## Airport, navaid or (when shown) fix under `px`, "" if none (RouteGestures.pick).
func pick(px: Vector2) -> String:
	gestures.db = db
	return gestures.pick(px)


## What a press at `px` takes hold of (RouteGestures.hit).
func hit(px: Vector2) -> Dictionary:
	gestures.legs = legs
	return gestures.hit(px)


func _gui_input(e: InputEvent) -> void:
	gestures.db = db
	gestures.legs = legs
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			var k := pow(ZOOM_STEP, mb.factor if mb.factor > 0.0 else 1.0)
			zoom_at(mb.position, 1.0 / k if mb.button_index == MOUSE_BUTTON_WHEEL_UP else k)
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				grab_focus()
			gestures.input(mb)
			queue_redraw()
		accept_event()
	elif e is InputEventMouseMotion and gestures.pressed:
		gestures.input(e)
		queue_redraw()
		accept_event()
	elif e is InputEventKey and e.pressed:
		_key(e as InputEventKey)


func _key(k: InputEventKey) -> void:
	var c := size * 0.5
	match k.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom_at(c, 1.0 / ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT: zoom_at(c, ZOOM_STEP)
		KEY_LEFT: view.pan_px(Vector2(PAN_STEP, 0))
		KEY_RIGHT: view.pan_px(Vector2(-PAN_STEP, 0))
		KEY_UP: view.pan_px(Vector2(0, PAN_STEP))
		KEY_DOWN: view.pan_px(Vector2(0, -PAN_STEP))
		KEY_F: fit()
		_: return
	queue_redraw()
	accept_event()


func zoom_at(px: Vector2, factor: float) -> void:
	view.size = size
	view.zoom_at(px, factor)
	set_process(true)


func _process(dt: float) -> void:
	var moving := view.step(dt)
	var loading := _tiles != null and _tiles.process()
	if moving or loading:
		queue_redraw()
	elif not is_visible_in_tree():
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		set_process(true)


## Imagery only with a display (headless runs draw nothing) and the terrain data.
func _imagery() -> MapTiles:
	if _tiles == null and DisplayServer.get_name() != "headless" and FileAccess.file_exists(Paths.data("terrain/meta.json")):
		_tiles = MapTiles.new(TerrainTileCache.new())
		_tiles.preload_coarse()
		set_process(true)
	return _tiles


func _draw() -> void:
	view.size = size
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var font := MenuTheme.font("medium")
	var tiles := _imagery()
	if tiles != null:
		var level := MapView.level_for(view.physical_m_per_px(UiScale.factor), tiles.cache.levels.size())
		tiles.draw(self, view, level, Color(0.42, 0.45, 0.5))
	if db == null:
		return
	var shown := drawn_legs()
	var taken: Array = []
	MapRouteLayer.reserve(view, shown, font, taken, MapFeatures.marker_rects(view, db) + [fit_btn.get_rect()])
	RouteMapLayers.draw_airways(self, view, db)
	RouteMapLayers.draw_fixes(self, view, db, font, taken)
	RouteMapLayers.draw_ends(self, view, ring_dep(), dest)  # under the labels, so the ring never hides the airport's name
	MapFeatures.draw_airports(self, view, db, runways, font, taken)
	MapFeatures.draw_navaids(self, view, db, font, taken)
	MapRouteLayer.draw(self, view, shown, tas_mps, font, taken)
	gestures.draw_snap(self)
	if not aircraft.is_empty():
		MapFeatures.draw_aircraft(self, view.to_px(aircraft.pos), float(aircraft.hdg), 0.0)
	MapFeatures.draw_scale_bar(self, view, Vector2(18.0, size.y - 22.0), font)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.14) if not has_focus() else Color(MenuTheme.ACCENT, 0.8), false, 1.5 if not has_focus() else 2.0)
