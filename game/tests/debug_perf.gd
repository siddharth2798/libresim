extends Node
## Debug: frame-time profiler for a hands-off flight. Logs one CSV row per frame and
## attributes _process time to each processing node (priority sandwich), plus GPU time,
## physics time, pipeline compiles and terrain/building counters. Optional screenshot burst.
##   godot --path game res://tests/debug_perf.tscn -- --airport=VABB --runway=27 --air=1500 \
##     --quality=high --log=/tmp/f.csv --dur=60 [--burst=/tmp/b@20x10] [--view=chase]
## --burst=<dir>@<t>x<n>: save n consecutive frames from t seconds on (flicker hunting);
## add --freeze to stop sim time during the burst (static camera: any change = instability).
## A summary of the worst frames and the top time consumers is printed at the end.

var f: Node
var t := 0.0
var dur := 60.0
var log_path := ""
var burst_dir := ""
var burst_t := -1.0
var burst_n := 0
var _rows: PackedStringArray = []
var _stamps: Array = []  # [stamp node, label of the node that runs before it]
var _last_us := 0
var _nodes: Array[Node] = []
var _frame := 0
var _shot_i := 0
var _vp: RID
var _sum := {}  # label -> total us


class Stamp extends Node:
	var us := 0
	func _process(_dt: float) -> void:
		us = Time.get_ticks_usec()


class PStamp extends Node:
	var probe: Node
	var is_end := false
	var us := 0
	func _physics_process(_dt: float) -> void:
		if is_end:
			probe.phys_us += Time.get_ticks_usec() - probe.phys_start
		else:
			probe.phys_start = Time.get_ticks_usec()


var phys_us := 0
var phys_start := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--log="): log_path = a.substr(6)
		elif a.begins_with("--dur="): dur = float(a.substr(6))
		elif a.begins_with("--burst="):
			var p := a.substr(8).split("@")
			burst_dir = p[0]
			var q := p[1].split("x")
			burst_t = float(q[0]); burst_n = int(q[1])
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	process_priority = -100000
	_sandwich.call_deferred()


## Give every processing node in the flight scene its own priority with a stamp after it.
func _sandwich() -> void:
	var stack: Array[Node] = [f]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_script() != null and n.is_processing() and n != self:
			_nodes.append(n)
		for c in n.get_children():
			stack.append(c)
	var first := Stamp.new()
	first.process_priority = -99999
	add_child(first)
	_stamps.append([first, ""])
	var pri := -99998
	for n in _nodes:
		n.process_priority = pri
		var s := Stamp.new()
		s.process_priority = pri + 1
		add_child(s)
		_stamps.append([s, str(f.get_path_to(n))])
		pri += 2
	var last := Stamp.new()
	last.process_priority = 99999
	add_child(last)
	_stamps.append([last, "(other nodes)"])
	var pa := PStamp.new()
	pa.process_physics_priority = -99999
	pa.probe = self
	add_child(pa)
	var pb := PStamp.new()
	pb.process_physics_priority = 99999
	pb.probe = self
	pb.is_end = true
	add_child(pb)
	var hdr := "frame,t,frame_ms,gpu_ms,render_cpu_ms,process_ms,physics_ms,draws,objects,pipe_compiles,terrain_nodes,top1,top1_ms,top2,top2_ms"
	_rows.append(hdr)


func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	_frame += 1
	if _stamps.size() > 1 and _frame > 3:
		_record(frame_ms)
	if burst_n > 0 and t >= burst_t:
		if "--freeze" in OS.get_cmdline_user_args():  # static camera: any change is instability
			Engine.time_scale = 0.0
		get_viewport().get_texture().get_image().save_png("%s/f%03d.png" % [burst_dir, _shot_i])
		_shot_i += 1
		burst_n -= 1
	t += dt if Engine.time_scale > 0.0 else 1.0 / 60.0
	if t >= dur:
		_finish()


func _record(frame_ms: float) -> void:
	var per: Array = []
	for i in range(1, _stamps.size()):
		var d: int = _stamps[i][0].us - _stamps[i - 1][0].us
		per.append([d, _stamps[i][1]])
		_sum[_stamps[i][1]] = _sum.get(_stamps[i][1], 0) + d
	_sum["(physics)"] = _sum.get("(physics)", 0) + phys_us
	per.sort_custom(func(a, b): return a[0] > b[0])
	var R := RenderingServer
	var pc := 0
	for k in [R.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, R.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			R.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, R.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			R.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		pc += R.get_rendering_info(k)
	var terr = f.get_node("Terrain")
	_rows.append("%d,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%d,%s,%.2f,%s,%.2f" % [_frame, t, frame_ms,
		R.viewport_get_measured_render_time_gpu(_vp), R.viewport_get_measured_render_time_cpu(_vp),
		(_stamps[-1][0].us - _stamps[0][0].us) / 1000.0,
		phys_us / 1000.0,
		R.get_rendering_info(R.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		R.get_rendering_info(R.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), pc, terr.visible_nodes,
		per[0][1], per[0][0] / 1000.0, per[1][1], per[1][0] / 1000.0])
	phys_us = 0


func _finish() -> void:
	set_process(false)
	if log_path != "":
		var fa := FileAccess.open(log_path, FileAccess.WRITE)
		fa.store_string("\n".join(_rows) + "\n")
	var ms: Array = []
	for i in range(1, _rows.size()):
		ms.append(float(_rows[i].split(",")[2]))
	ms.sort()
	if ms.size() > 0:
		var avg: float = ms.reduce(func(a, b): return a + b, 0.0) / ms.size()
		print("PERF frames %d avg %.2f ms p50 %.2f p95 %.2f p99 %.2f max %.2f  >33ms %d  >50ms %d" % [ms.size(), avg,
			ms[ms.size() / 2], ms[int(ms.size() * 0.95)], ms[int(ms.size() * 0.99)], ms[-1],
			ms.filter(func(x): return x > 33.3).size(), ms.filter(func(x): return x > 50.0).size()])
	var tops: Array = []
	for k in _sum:
		tops.append([_sum[k], k])
	tops.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(8, tops.size()):
		print("  %-40s %.2f ms/frame" % [tops[i][1], tops[i][0] / 1000.0 / maxf(_frame - 3, 1)])
	get_tree().quit()
