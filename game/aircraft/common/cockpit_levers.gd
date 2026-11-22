class_name CockpitLevers
extends Node
## Moves the cockpit's levers, sidesticks, pedals and knobs with the property tree. Built by Cockpit from aircraft.json
## "cockpit"."levers" and the interior glb's `pivot_<name>` nodes (the C172 has no section: nothing is built). Runs only in
## the cockpit view.
##   levers  {pivot name: {"drive": expr, "map": [[value, deg|m], ...], "move": "translate", "sign": +-1, "lag": seconds,
##            "rate": deg/s | m/s}}
##   drive   a property path, or paths joined by " + " / " - " (thrust lever: "controls/throttle_1 - controls/reverse_1"); bool = 0/1
##   map     piecewise linear, clamped like model.surfaces' "map" (ModelDrives.table); result = degrees about the pivot's +X
##           (rotate) or metres along it (translate)
##   lag     first-order low pass;  rate: travel limit, so a lever never jumps further than a person could move it
## Pivots are nested in the glb where one part sits on another (reverser flap on a thrust lever, pitch then roll of a
## sidestick): each keeps its own base transform and is turned about its own axis.
##   at      [x, y, z] FlightGear model frame (x aft, y right, z up): a hotspot for a part of the panel the glb does not
##           split out (an EFIS button, the BARO knob). An empty pivot_<name> is made there; "half" (m) is its pick box.
##   momentary  true: a pushbutton that springs back. The pivot pressed in for CockpitPick.PRESS_S after a click,
##           whatever the latched value (an FCU button lights for the mode, it does not stay pushed in).
## Other keys (kind, value, push, pull, step ...) are for CockpitPick / CockpitKnob and kept on the item.

var _items: Array = []  # {node, basis, pos, drive, terms, map, move, sign, lag, rate, value}
var _active := false


## Pivot nodes found in `interior` for the entries of `cfg` (missing nodes are skipped).
func build(interior: Node, cfg: Dictionary) -> int:
	for k in cfg:
		var s = cfg[k]
		if not s is Dictionary:
			continue
		var node := interior.find_child("pivot_" + str(k), true, false) as Node3D
		if node == null and s.get("at") is Array:
			node = _hotspot(interior, str(k), s.at)
		var map: Variant = s.get("map", [[0.0, 0.0], [1.0, 0.0]] if s.has("at") else null)
		if node == null or not map is Array or (map as Array).size() < 2:
			continue
		var drive := str(s.get("drive", ""))
		var it: Dictionary = (s as Dictionary).duplicate(true)
		it.merge({"node": node, "basis": node.transform.basis, "pos": node.position, "drive": drive, "terms": parse_drive(drive),
			"map": map, "move": str(s.get("move", "rotate")), "sign": float(s.get("sign", 1.0)), "lag": float(s.get("lag", 0.0)),
			"rate": float(s.get("rate", 0.0)), "value": NAN, "press_t": 0.0}, true)
		_items.append(it)
	set_process(not _items.is_empty())
	return _items.size()


## An empty pivot at a FlightGear model-frame point, in the glb's own frame (x aft, y up, z left).
static func _hotspot(interior: Node, k: String, at: Array) -> Node3D:
	var n := Node3D.new()
	n.name = "pivot_" + k
	n.position = Vector3(float(at[0]), float(at[2]), -float(at[1]))
	interior.add_child(n)
	return n


## "controls/throttle_1 - controls/reverse_1" -> [[1, path], [-1, path]].
static func parse_drive(expr: String) -> Array:
	var out := []
	var sign := 1.0
	for tok in expr.split(" ", false):
		if tok == "+" or tok == "-":
			sign = 1.0 if tok == "+" else -1.0
		else:
			out.append([sign, tok])
			sign = 1.0
	return out


static func read_drive(terms: Array) -> float:
	var v := 0.0
	for t in terms:
		var x = Props.get_v(t[1], 0.0)
		v += float(t[0]) * (float(x) if not x is bool else (1.0 if x else 0.0))
	return v


## Degrees (or metres) the lever wants now. A momentary button is in (map at 1) only while its press lasts.
static func target(item: Dictionary) -> float:
	if item.get("momentary", false):
		return ModelDrives.table(item.map, 1.0 if float(item.get("press_t", 0.0)) > 0.0 else 0.0) * float(item.sign)
	return ModelDrives.table(item.map, read_drive(item.terms)) * float(item.sign)


## One smoothing step toward `goal`: low pass, then the rate limit. NAN `value` = snap.
static func step(value: float, goal: float, lag: float, rate: float, dt: float) -> float:
	if is_nan(value):
		return goal
	var v := value
	if lag > 0.0:
		v = lerpf(value, goal, 1.0 - exp(-dt / lag))
	else:
		v = goal
	if rate > 0.0:
		v = value + clampf(v - value, -rate * dt, rate * dt)
	return v


func _process(dt: float) -> void:
	var on := str(Props.get_v("view/mode", "")) == "Cockpit"
	if not on:
		_active = false
		return
	if not _active:  # coming into the cockpit: show the controls where they are, do not sweep from the old pose
		_active = true
		for it in _items:
			it.value = NAN
	for it in _items:
		if it.press_t > 0.0:
			it.press_t = maxf(it.press_t - dt, 0.0)
		var v := step(it.value, target(it), it.lag, it.rate, dt)
		if v == it.value:
			continue
		it.value = v
		apply(it, v)


static func apply(item: Dictionary, v: float) -> void:
	var n: Node3D = item.node
	if item.move == "translate":
		n.position = item.pos + (item.basis as Basis).x * v
	else:
		n.transform.basis = (item.basis as Basis) * Basis(Vector3.RIGHT, deg_to_rad(v))
