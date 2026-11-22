class_name TouchdownMarks
extends Node
## Your own tyre marks: each wheel that spins up on a runway (TouchdownFx, TouchdownDetect events) leaves a fresh dark
## streak at that spot, drawn by world/runway_v2.gdshader from its `marks` uniform (runway-local {along from ends[0],
## across (+ right travelling from ends[0]), yaw (rad from the ends[0] -> ends[1] direction), half-track dm + strength}).
## Up to MAX per runway, the oldest dropped first. Kept in saved flights (group "saveable", core/situation_systems.gd),
## cleared on a new flight (TouchdownFx.clear).

const MAX := 32
const KEY := "touchdown_marks"

var airports: AirportBuilder
var marks := {}  # runway key -> Array[Vector4], oldest first
var _pending := {}  # keys whose runway mesh was not built yet (a flight loaded at the start)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)


func _process(_dt: float) -> void:
	for k in _pending.keys():
		_push(k)


static func runway_key(r: Dictionary) -> String:
	return "%s/%s" % [str(r.get("airport", "")), str(r.ends[0].ident)]


## The runway under ENU point (e, n) and the mark there for a wheel rolling along `track` (rad from north):
## {key, mark: Vector4(along, across, yaw, strength)}, or {} off every runway.
static func locate(runways: Array, e: float, n: float, track: float, strength: float) -> Dictionary:
	var p := Vector2(e, n)
	for r in runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var u := (b - a).normalized()
		var right := Vector2(u.y, -u.x)
		var along := (p - a).dot(u)
		var across := (p - a).dot(right)
		if along < 0.0 or along > a.distance_to(b) or absf(across) > float(r.width) * 0.5:
			continue
		var dir := Vector2(sin(track), cos(track))
		var yaw := atan2(dir.dot(right), dir.dot(u))
		return {"key": runway_key(r), "mark": Vector4(along, across, yaw, clampf(strength, 0.05, 0.99))}
	return {}


## list with mark v appended, the oldest dropped beyond MAX.
static func appended(list: Array, v: Vector4) -> Array:
	var out := list.duplicate()
	out.append(v)
	while out.size() > MAX:
		out.pop_front()
	return out


## A wheel spun up at ENU (e, n) rolling along track; strength 0..1 (TouchdownFx.puff).
func add(e: float, n: float, track: float, strength: float) -> void:
	if airports == null or airports.data == null:
		return
	var m := locate(airports.data.runways, e, n, track, strength)
	if m.is_empty():
		return
	marks[m.key] = appended(marks.get(m.key, []), m.mark)
	_push(m.key)


func clear() -> void:
	var keys := marks.keys()
	marks.clear()
	for k in keys:
		_push(k)


func save_key() -> String:
	return KEY


func save_state() -> Dictionary:
	var out := {}
	for k in marks:
		out[k] = marks[k].map(func(v: Vector4) -> Array: return [v.x, v.y, v.z, v.w])
	return {"marks": out}


func load_state(d: Dictionary) -> void:
	clear()
	var src: Dictionary = d.get("marks", {})
	for k in src:
		var list := []
		for v in src[k]:
			list = appended(list, Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3])))
		marks[k] = list
		_push(k)


## Hands runway `key`'s marks to its material (marks, mark_count, marks_along: the along range they cover).
func _push(key: String) -> void:
	var mat := airports.runway_material(key) if airports else null
	if mat == null:
		if airports and marks.has(key):
			_pending[key] = true
		return
	_pending.erase(key)
	var list: Array = marks.get(key, [])
	var arr := []
	var lo := INF
	var hi := -INF
	for v in list:
		arr.append(v)
		lo = minf(lo, v.x - 40.0)
		hi = maxf(hi, v.x + 40.0)
	arr.resize(MAX)
	for i in MAX:
		if arr[i] == null:
			arr[i] = Vector4.ZERO
	mat.set_shader_parameter("marks", arr)
	mat.set_shader_parameter("mark_count", list.size())
	mat.set_shader_parameter("marks_along", Vector2(lo, hi) if not list.is_empty() else Vector2.ZERO)
