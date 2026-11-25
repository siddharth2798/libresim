extends Node
## Debug: what each _physics_process script costs, per physics step and per render frame, by group
## (FDM, systems, instruments, avionics, other). Used for the tick-rate study (docs/USAGE.md "Tick rates").
##   godot --headless --audio-driver Dummy --path game res://tests/debug_tick_cost.tscn -- \
##     --airport=VABB --runway=27 --air=1500 [--aircraft=a320] [--fps=30|60] [--dur=20] [--tag=<label>] [--oldrate]
## Every physics node gets its own physics priority with a stamp after it, so the time between two stamps is that
## node's script. --fps caps the render rate (Engine.max_fps), so the steps per frame follow the real catch-up
## (120 Hz physics: 2 steps a frame at 60 fps, 4 at 30). Prints one line per node and one per group.

const WARMUP_S := 4.0

var f: Node
var dur := 20.0
var fps := 0
var tag := ""
var _nodes: Array[Node] = []
var _stamps: Array = []
var _us := {}  # label -> total microseconds
var _steps := 0
var _frames := 0
var _t := 0.0
var _armed := false


class Stamp extends Node:
	var us := 0
	var probe: Node
	var first := false
	func _physics_process(_dt: float) -> void:
		if first:
			probe.step_begin()
		us = Time.get_ticks_usec()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dur="): dur = float(a.substr(6))
		elif a.begins_with("--fps="): fps = int(a.substr(6))
		elif a.begins_with("--tag="): tag = a.substr(6)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	if fps > 0:
		Engine.max_fps = fps
	_sandwich.call_deferred()


func _sandwich() -> void:
	await get_tree().create_timer(WARMUP_S).timeout
	if "--plain" in OS.get_cmdline_user_args():
		_armed = true
		return
	var stack: Array[Node] = [f]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and n.is_physics_processing():
			_nodes.append(n)
		stack.append_array(n.get_children())
	if "--oldrate" in OS.get_cmdline_user_args():  # every moved script back at 120 Hz: the "before" of the same build
		for n in _nodes:
			if "_tick" in n:
				n._tick = TickRate.new(120.0)
	var pri := -90000
	var first := Stamp.new()
	first.probe = self
	first.first = true
	first.process_physics_priority = pri
	add_child(first)
	_stamps.append([first, ""])
	pri += 1
	for n in _nodes:
		n.process_physics_priority = pri
		var s := Stamp.new()
		s.probe = self
		s.process_physics_priority = pri + 1
		add_child(s)
		_stamps.append([s, "%s  [%s]" % [str(f.get_path_to(n)), n.get_script().resource_path.get_file()]])
		pri += 2
	_armed = true


func step_begin() -> void:
	if _stamps.size() < 2:
		return
	# called at the start of a step: the previous step's stamps are complete
	if _steps > 0:
		_collect()
	_steps += 1


func _collect() -> void:
	for i in range(1, _stamps.size()):
		var d: int = _stamps[i][0].us - _stamps[i - 1][0].us
		_us[_stamps[i][1]] = _us.get(_stamps[i][1], 0) + d


func _process(dt: float) -> void:
	if not _armed:
		return
	_frames += 1
	_t += dt
	if _t >= dur:
		_finish()


func _group(label: String) -> String:
	if "fdm_node" in label:
		return "FDM"
	if "systems/" in label or label.contains("Systems/"):
		return "systems"
	for g in ["instruments", "avionics"]:
		if label.contains("[") and (label.contains("Instruments/") or label.contains("Avionics/")):
			return "instruments+avionics"
	return "other"


func _finish() -> void:
	set_process(false)
	var steps := maxf(_steps - 1, 1)
	var frames := maxf(_frames, 1)
	var groups := {}
	var rows: Array = []
	for k in _us:
		rows.append([_us[k], k])
		var g := _group(k)
		groups[g] = groups.get(g, 0) + _us[k]
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("TICKCOST %s fps_cap=%d frames=%d steps=%d steps/frame=%.2f  crashed=%s (%s) alt_ft=%.0f kias=%.0f" % [tag, fps, frames, steps,
		steps / frames, Props.get_b("damage/crashed"), Props.get_v("damage/reason", ""), Units.m_to_ft(Props.get_f("fdm/alt_m")), Units.mps_to_kt(Props.get_f("fdm/cas_mps"))])
	for r in rows:
		print("  %-58s %6.1f us/step  %6.3f ms/frame" % [r[1], r[0] / steps, r[0] / frames / 1000.0])
	var total := 0
	for g in groups:
		total += groups[g]
		print("GROUP %-22s %6.1f us/step  %6.3f ms/frame" % [g, groups[g] / steps, groups[g] / frames / 1000.0])
	print("TOTAL %6.1f us/step  %6.3f ms/frame" % [total / steps, total / frames / 1000.0])
	get_tree().quit()
