class_name MapRouteEdit
extends RefCounted
## Edit mode of the in-flight N map (ui/moving_map.gd, its "Edit route" toggle). It shows the route ahead of the
## aircraft (RouteLive.split: what the GPS flies, with the plan's waypoints behind it) from the present position, and
## edits it with the Route step's gestures (RouteGestures) and edits (RouteOps):
##   click                 add a point at the end: the airport, navaid or fix under the cursor, else a free waypoint
##   Shift+click airport   new destination
##   drag a waypoint       move it (dropped on a named point it becomes that point)
##   drag a leg            add a point on it (the leg from the aircraft too: that point is flown first)
##   right-click waypoint  remove it
##   drag the empty map    panned(relative px), the map pans
## Every edit goes into the flight at once (RouteLive.commit: Session.setup.route, GPS, route waypoints, route/dest,
## MCDU); `msg` is what it says about the last one.

signal panned(relative: Vector2)

var on := false
var db: NavDatabase
var gestures: RouteGestures
var msg := ""
var _sp := {}  # RouteLive.split of the route shown
var _key := ""


func _init(view: MapView) -> void:
	gestures = RouteGestures.new(view)
	gestures.clicked.connect(_on_click)
	gestures.wp_dragged.connect(_on_drag)
	gestures.leg_dragged.connect(_on_leg)
	gestures.wp_removed.connect(_on_remove)
	gestures.panned.connect(panned.emit)  # not a lambda: it would hold this RefCounted alive (a cycle)


func set_on(v: bool) -> void:
	on = v
	msg = ""
	gestures.cancel()
	_key = ""
	if not v:
		RouteLive.clear_ppos()


## Re-read the route ahead (cached until the GPS route or the plan changes) and its legs from `here`.
func refresh(here: Vector2) -> void:
	gestures.db = db
	var next: Array = Props.get_v("controls/gps/route_next", [])
	var key := "%s|%s|%d" % [Props.get_v("controls/gps/target", ""), ",".join(PackedStringArray(next)), int(Props.get_v(RouteSetup.REV_PROP, 0))]
	if key != _key or _sp.is_empty():
		_key = key
		_sp = RouteLive.split(Session.setup, db)
	var s := RouteLive.edit_setup(Session.setup, _sp.route, here, false)
	gestures.legs = RouteEdit.legs(s, db, RouteEdit.cruise_kt(str(s.get("aircraft", ""))))


## The legs to draw (MapRouteLayer): bent to the cursor while dragging, the leg from the aircraft bold.
func shown_legs() -> Array:
	var out := gestures.shown_legs(-99)
	if not out.is_empty():
		out[0].active = true
	return out


## A mouse button or held drag for the editor: true when it took it.
func input(e: InputEvent) -> bool:
	if not on or db == null:
		return false
	if gestures.legs.is_empty() and _sp.is_empty():
		refresh(RouteLive.here())
	return gestures.input(e)


func _edit(f: Callable) -> void:
	if _sp.is_empty():
		refresh(RouteLive.here())
	var r: Dictionary = (_sp.route as Dictionary).duplicate(true)
	var res: Dictionary = f.call(r)
	if res.get("ok", false):
		RouteLive.commit(_sp, r, db, RouteLive.airliner())
		_key = ""
		refresh(RouteLive.here())
	msg = str(res.get("msg", ""))


func _on_click(world: Vector2, ident: String, shift: bool) -> void:
	_edit(func(r: Dictionary) -> Dictionary:
		var res := RouteOps.click(r, world, ident, shift, "", db, _sp.passed)
		if res.has("dest"):
			r.dest = str(res.dest)
			r.arr_rwy = ""
			return {"ok": true, "msg": "Destination %s." % res.dest}
		return res)


func _on_drag(i: int, world: Vector2, ident: String) -> void:
	_edit(func(r: Dictionary) -> Dictionary: return RouteOps.drag(r, i, world, ident, db, _sp.passed))


func _on_leg(at: int, world: Vector2, ident: String) -> void:
	_edit(func(r: Dictionary) -> Dictionary: return RouteOps.insert(r, at, world, ident, db, _sp.passed))


func _on_remove(i: int) -> void:
	_edit(func(r: Dictionary) -> Dictionary: return RouteOps.remove(r, i))
