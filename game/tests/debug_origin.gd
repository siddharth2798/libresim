extends Node
## Debug: one-frame jumps at a floating-origin shift. Flies hands-off (pass --air=...) and,
## at the end of every frame (after all _process), records the WORLD position (ENU, from
## render position + origin) of the camera, the aircraft and static scenery (a terrain node,
## a runway strip, a tree chunk, a building tile). Static things must not move in world space
## and the camera/aircraft must move smoothly; prints the frames around each shift.
##   godot --path game res://tests/debug_origin.tscn -- --airport=VABB --runway=27 --air=1500 --dur=150

var f: Node
var dur := 150.0
var t := 0.0
var _rows: Array = []  # [frame, shifted?, cam, ac, statics: Dictionary name->Vector3]
var _shift_frames: Array[int] = []
var _frame := 0
var _last := {}
var _worst := {}


class EndStamp extends Node:
	var cb: Callable
	func _process(_dt: float) -> void:
		cb.call()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dur="): dur = float(a.substr(6))
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	var s := EndStamp.new()
	s.process_priority = 100000
	s.cb = _sample
	add_child(s)
	FloatingOrigin.shifted.connect(func(_d): _shift_frames.append(_frame))


func _first_child(path: String) -> Node3D:
	var n := f.get_node_or_null(path)
	if n == null:
		return null
	for c in n.get_children():
		if c is Node3D and c.visible:
			return c
	return null


func _sample() -> void:
	_frame += 1
	t += get_process_delta_time()
	var w := func(n: Node3D) -> Vector3: return FloatingOrigin.to_world(n.global_position) if n else Vector3.INF
	var cur := {"camera": w.call(f.get_node("Camera")), "aircraft": w.call(f.get_node("Aircraft"))}
	# statics: remember the node so the same instance is tracked across frames
	for p in ["Terrain", "Airports", "Trees", "Buildings"]:
		var key := "static:" + p
		if not _last.has(key + "#node") or not is_instance_valid(_last[key + "#node"]):
			_last[key + "#node"] = _first_child(p)
		var n: Node3D = _last[key + "#node"]
		cur[key] = w.call(n) if n and n.is_inside_tree() else Vector3.INF
	var shifted := _shift_frames.has(_frame)
	for k in cur:
		if _last.has(k) and cur[k] != Vector3.INF and _last[k] != Vector3.INF:
			var d: float = (cur[k] - _last[k]).length()
			var tag := "shift" if shifted else "normal"
			var wk := "%s/%s" % [k, tag]
			_worst[wk] = maxf(_worst.get(wk, 0.0), d)
		_last[k] = cur[k]
	if t >= dur:
		print("origin shifts at frames ", _shift_frames, "  (origin now ", FloatingOrigin.origin, ")")
		var keys := _worst.keys()
		keys.sort()
		for k in keys:
			print("  max per-frame world move %-28s %.3f m" % [k, _worst[k]])
		get_tree().quit()
