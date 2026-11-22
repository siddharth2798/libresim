class_name RouteGestures
extends RefCounted
## Mouse gestures that edit a route on a map, shared by the Route step's map (RouteMap) and the in-flight N map's edit
## mode (MapRouteEdit). It holds no route: `legs` are RouteEdit.legs() (each with wp = index in wps, -1 / -2 for the
## departure / destination, and insert_at), `view` is the map's MapView. input() turns mouse events into signals:
##   left click            clicked(world, ident, shift): ident = airport / navaid / fix under the cursor, "" = empty map
##   click a waypoint      wp_selected(i)
##   drag a waypoint       wp_dragged(i, world, ident): dropped on a named point = that point, else a free waypoint there
##   drag a leg            leg_dragged(insert_at, world, ident): a new waypoint on that leg
##   right click waypoint  wp_removed(i)
##   drag the empty map    panned(relative px)
## Wheel and keys stay with the map. While a drag is held, shown_legs() bends the route to the cursor and draw_snap()
## marks where the point will land.

signal clicked(world: Vector2, ident: String, shift: bool)
signal wp_selected(index: int)
signal wp_dragged(index: int, world: Vector2, ident: String)
signal leg_dragged(insert_at: int, world: Vector2, ident: String)
signal wp_removed(index: int)
signal panned(relative: Vector2)

const CLICK_SLOP := 6.0
const WP_HIT := 13.0  # px: a press this close to a waypoint grabs it
const LEG_HIT := 8.0  # px: this close to a leg (away from its ends) grabs the leg

var view: MapView
var db: NavDatabase
var legs: Array = []
var grab := {}  # what the left button pressed on: {kind: "wp" | "leg" | "pan", index}
var pressed := false
var dragging := false
var drag_px := Vector2.ZERO
var _press := Vector2.ZERO


func _init(v: MapView = null) -> void:
	view = v if v != null else MapView.new()


## Airport, navaid or (zoomed in enough to show them) airway fix under `px`, "" if none.
func pick(px: Vector2) -> String:
	if db == null:
		return ""
	var id := MapFeatures.pick(view, db, px, 16.0)
	if id != "" or view.across_nm() > RouteMapLayers.SHOW_FIX_NM:
		return id
	var bd := 10.0
	for f in db.fixes:
		var d := view.to_px(db.fixes[f]).distance_to(px)
		if d < bd:
			bd = d
			id = f
	return id


## What a press at `px` takes hold of: a waypoint (not the departure or destination), a leg away from its ends, or the map.
func hit(px: Vector2) -> Dictionary:
	for l in legs:
		if int(l.wp) >= 0 and view.to_px(l.b).distance_to(px) < WP_HIT:
			return {"kind": "wp", "index": int(l.wp)}
	for l in legs:
		var a := view.to_px(l.a)
		var b := view.to_px(l.b)
		var c := Geometry2D.get_closest_point_to_segment(px, a, b)
		if c.distance_to(px) < LEG_HIT and c.distance_to(a) > WP_HIT and c.distance_to(b) > WP_HIT:
			return {"kind": "leg", "index": int(l.insert_at)}
	return {"kind": "pan", "index": -1}


## True when `e` was a left / right button or a held drag (the map then redraws and accepts it).
func input(e: InputEvent) -> bool:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var h := hit(mb.position)
			if h.kind == "wp":
				wp_removed.emit(h.index)
			return true
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_press = mb.position
			grab = hit(mb.position)
			pressed = true
			dragging = false
		elif pressed:
			_release(mb.position, mb.shift_pressed)
		return true
	if e is InputEventMouseMotion and pressed:
		var mm := e as InputEventMouseMotion
		if not dragging and mm.position.distance_to(_press) > CLICK_SLOP:
			dragging = true
		if dragging:
			if grab.kind == "pan":
				panned.emit(mm.relative)
			drag_px = mm.position
		return true
	return false


## Drop any press in progress (the map closed or left edit mode).
func cancel() -> void:
	pressed = false
	dragging = false
	grab = {}


func _release(px: Vector2, shift: bool) -> void:
	var g := grab
	var dragged := dragging
	cancel()
	if not dragged:
		if g.kind == "wp":
			wp_selected.emit(g.index)
		else:
			clicked.emit(view.to_world(px), pick(px), shift)
	elif g.kind == "wp":
		wp_dragged.emit(g.index, view.to_world(px), pick(px))
	elif g.kind == "leg":
		leg_dragged.emit(g.index, view.to_world(px), pick(px))


## True while a waypoint or leg (not the map) is being dragged.
func moving_point() -> bool:
	return dragging and grab.get("kind", "") != "pan"


## Where a dragged waypoint lands: a ring on the named point it snaps to, else a cross (RouteMapLayers.draw_snap).
func draw_snap(ci: CanvasItem) -> void:
	if moving_point() and db != null:
		RouteMapLayers.draw_snap(ci, view.to_world(drag_px), view, pick(drag_px), db)


## The legs as drawn: the selected waypoint's leg is the "active" (bold, ringed) one; a waypoint or leg being dragged
## follows the cursor. dist_m / cum_m are worked out again for the bent route.
func shown_legs(selected: int) -> Array:
	var out := []
	var to := view.to_world(drag_px)
	var kind: String = grab.get("kind", "") if dragging else ""
	var idx: int = int(grab.get("index", -1))
	for l in legs:
		var c: Dictionary = l.duplicate()
		c.active = int(l.wp) == selected and selected != -1
		if kind == "wp":
			if int(l.wp) == idx:
				c.b = to
			elif out.size() > 0 and int(out.back().wp) == idx:
				c.a = to
		if kind == "leg" and int(l.insert_at) == idx:
			var first := c.duplicate()
			first.b = to
			first.ident = "+"
			out.append(first)
			c.a = to
		out.append(c)
	var cum := 0.0
	for c in out:
		c.dist_m = (c.a as Vector2).distance_to(c.b)
		cum += c.dist_m
		c.cum_m = cum
	return out
