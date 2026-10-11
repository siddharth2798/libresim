extends Node
## Debug: the full flight scene, air start, hands off for 60 s. Logs actual roll,
## attitude-indicator roll, heading and the pilot controls the FDM sees, plus the
## per-frame camera step (uneven steps = stutter). Run:
##   godot --headless --path game res://tests/debug_handsoff.tscn -- --airport=VAPO --air=1500

var f: Node
var t := 0.0
var _next := 0.0
var _cam_prev := Vector3.ZERO
var _steps: Array = []
var _ac_prev := Vector3.ZERO
var _ac_steps: Array = []
var _st_prev := -1.0  # simulated time at the rendered pose (one tick behind + fraction)


func _ready() -> void:
	process_priority = 100  # after the aircraft model (0) and camera (10) have moved this frame
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _process(dt: float) -> void:
	t += dt
	# poses are compared against simulated time at the rendered pose (one tick behind + fraction),
	# so a headless run's uneven/capped frames do not show up as stutter
	var fn: FdmNode = f.get_node("Fdm")
	var h := 1.0 / Engine.physics_ticks_per_second
	var st := fn.fdm.time - h + Engine.get_physics_interpolation_fraction() * h
	var cam: Camera3D = get_viewport().get_camera_3d()
	var ac: Node3D = f.get_node("Aircraft")
	if cam and t > 5.0 and st > _st_prev:
		var w := FloatingOrigin.to_world(cam.global_position)
		var wa := FloatingOrigin.to_world(ac.global_position)
		if _ac_prev != Vector3.ZERO:
			_steps.append([st - _st_prev, w.distance_to(_cam_prev)])
			_ac_steps.append([st - _st_prev, wa.distance_to(_ac_prev)])
		_cam_prev = w
		_ac_prev = wa
		_st_prev = st
	if t >= _next:
		_next += 5.0
		print("HO t %5.1f roll %6.2f ai_roll %6.2f pitch %5.2f hdg %6.1f kias %5.1f alt %6.0f | ctl pitch %.3f roll %.3f yaw %.3f trim %.3f thr %.2f" % [t,
			rad_to_deg(Props.get_f("fdm/roll_rad")), rad_to_deg(Props.get_f("instruments/ai/roll_rad")),
			rad_to_deg(Props.get_f("fdm/pitch_rad")), rad_to_deg(Props.get_f("fdm/heading_rad")),
			Props.get_f("fdm/cas_mps") / 0.514444, Props.get_f("fdm/alt_m") / 0.3048,
			Props.get_f("controls/pitch"), Props.get_f("controls/roll"), Props.get_f("controls/yaw"),
			Props.get_f("controls/pitch_trim"), Props.get_f("controls/throttle")])
	if t > 65.0:
		_report("camera", _steps)
		_report("aircraft", _ac_steps)
		get_tree().quit()


func _report(what: String, steps: Array) -> void:
		var speeds: Array = steps.map(func(s): return s[1] / maxf(s[0], 1e-6))
		var dts: Array = steps.map(func(s): return s[0])
		var mean := 0.0
		for s in speeds:
			mean += s
		mean /= maxf(speeds.size(), 1)
		var dev := 0.0
		for s in speeds:
			dev = maxf(dev, absf(s - mean))
		var sd := 0.0
		for s in speeds:
			sd += (s - mean) * (s - mean)
		sd = sqrt(sd / maxf(speeds.size(), 1))
		print("HO %s: %d frames, dt %.1f..%.1f ms, mean speed %.1f m/s, per-frame speed sd %.2f m/s (%.1f %%), max dev %.1f m/s" % [what,
			speeds.size(), dts.min() * 1000.0, dts.max() * 1000.0, mean, sd, sd / maxf(mean, 1e-6) * 100.0, dev])
