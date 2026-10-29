class_name CockpitLevers
extends Node
## Moves the cockpit's levers, sidesticks, pedals and knobs with the property tree. Built by Cockpit from
## aircraft.json "cockpit"."levers" and the interior glb's `pivot_<name>` nodes (the C172 has no section:
## nothing is built). Only runs in the cockpit view.
##   levers  {pivot name: {"drive": expr, "map": [[value, deg|m], ...], "move": "translate", "sign": +-1,
##            "lag": seconds, "rate": deg/s | m/s}}
##   drive   a property path, or paths joined by " + " / " - " (a thrust lever is
##           "controls/throttle_1 - controls/reverse_1"); a bool reads 0/1
##   map     piecewise linear and clamped like model.surfaces' "map" (ModelDrives.table); the result is
##           degrees about the pivot's +X (rotate) or metres along it (translate)
##   lag     first-order low pass (a sidestick follows a hand, a lever follows a pilot's grip)
##   rate    travel limit, so a lever never jumps further than a person could move it
## Pivots are nested in the glb where one part sits on another (reverser flap on a thrust lever, pitch
## then roll of a sidestick): each pivot keeps its own base transform and is turned about its own axis.

var _items: Array = []  # {node, basis, pos, terms, map, move, sign, lag, rate, value}
var _active := false


## Pivot nodes found in `interior` for the entries of `cfg` (missing nodes are skipped).
func build(interior: Node, cfg: Dictionary) -> int:
	for k in cfg:
		var node := interior.find_child("pivot_" + str(k), true, false) as Node3D
		var s = cfg[k]
		if node == null or not s is Dictionary or not s.get("map") is Array or (s.map as Array).size() < 2:
			continue
		_items.append({"node": node, "basis": node.transform.basis, "pos": node.position, "terms": parse_drive(str(s.get("drive", ""))),
			"map": s.map, "move": str(s.get("move", "rotate")), "sign": float(s.get("sign", 1.0)), "lag": float(s.get("lag", 0.0)),
			"rate": float(s.get("rate", 0.0)), "value": NAN})
	set_process(not _items.is_empty())
	return _items.size()


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


## Degrees (or metres) the lever wants now.
static func target(item: Dictionary) -> float:
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
