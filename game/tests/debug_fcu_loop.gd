extends Node
## Debug: closed-loop drive of the A320 FCU in the real flight scene with injected mouse input, one report line per step
## (windows, FMA, lamps, aircraft state). The head looks at the FCU; clicks use the projected pivot positions.
##   godot --audio-driver Dummy --path game res://tests/debug_fcu_loop.tscn -- --aircraft=a320 --airport=VABB --air \
##     --shots=<abs dir> --steps=ap1,athr,wait:5,+hdg_sel,shot:name [--fov=40]
## Steps (comma separated): <pivot> click (push), +<pivot> Shift+click (pull), drag:<pivot>:<px> (up = more),
## wait:<s>, set:<prop>=<value> (number, true/false or text), shot:<name> (saves <shots>/<name>.png).
## Pivots: ap1 ap2 athr loc appr spd_sel hdg_sel alt_sel vs_sel.
var f: Node
var _shots := ""
var _fov := 40.0
var _aim := "athr"  # a pivot name, or fg:x,y,z (FlightGear model frame: x aft, y right, z up; the captain PFD is fg:-17.03,-0.553,0.128)
var _steps: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--aim="):
			_aim = a.substr(6)
		elif a.begins_with("--fov="):
			_fov = float(a.substr(6))
		elif a.begins_with("--steps="):
			_steps = a.substr(8).split(",", false)
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _click(at: Vector2, shift: bool) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.shift_pressed = shift
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame


func _drag(at: Vector2, dy: float) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await get_tree().process_frame
	for i in 10:
		var mm := InputEventMouseMotion.new()
		mm.position = at + Vector2(0, dy * (i + 1) / 10.0)
		mm.global_position = mm.position
		mm.relative = Vector2(0, dy / 10.0)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mm)
		await get_tree().process_frame
	var u := e.duplicate() as InputEventMouseButton
	u.pressed = false
	u.position = at + Vector2(0, dy)
	Input.parse_input_event(u)
	await get_tree().process_frame


func _fma() -> String:
	var s := ""
	for c in ["thrust", "vertical", "lateral", "approach", "misc"]:
		s += "[%s]" % str(Props.get_v("ap/fma/" + c, "")).replace("\n", "/")
	return s


func _windows() -> String:
	var a := FcuWindows.spd()
	var h := FcuWindows.hdg()
	var l := FcuWindows.alt()
	var v := FcuWindows.vs()
	return "SPD %s%s HDG %s%s ALT %s%s V/S %s" % [a.text, "." if a.dot else "", h.text, "." if h.dot else "", l.text,
		"." if l.dot else "", v.text]


func _lamps() -> String:
	var s := ""
	for k in ["ap1", "ap2", "athr", "athr_active", "loc", "appr"]:
		s += " %s=%d" % [k, 1 if Props.get_b("ap/" + k) else 0]
	return s


func _report(step: String) -> void:
	print("STEP %-22s | %s | FMA %s | lamps%s | NAV2 %.2f %s%s | alt %.0f vs %.0f hdg %.0f cas %.0f t %.0f" % [step, _windows(), _fma(), _lamps(),
		Props.get_f("controls/nav2/freq_mhz"), Props.get_v("avionics/nav2/ident", ""), " GS" if Props.get_b("avionics/nav2/gs_valid") else "",
		Units.m_to_ft(Props.get_f("fdm/alt_m")), Props.get_f("fdm/vs_mps") / Units.FPM, rad_to_deg(Props.get_f("fdm/heading_rad")),
		Units.mps_to_kt(Props.get_f("fdm/cas_mps")), Time.get_ticks_msec() / 1000.0])


func _put(spec: String) -> void:
	var kv := spec.split("=")
	var v: Variant = kv[1]
	if kv[1] == "true" or kv[1] == "false":
		v = kv[1] == "true"
	elif kv[1].is_valid_float():
		v = float(kv[1])
	Props.set_v(kv[0], v)


func _run() -> void:
	await get_tree().create_timer(8.0).timeout
	var cam: CameraRig = f.get_node("Camera")
	var m: AircraftModel = f.get_node("Aircraft")
	cam.set_mode(0)
	Props.set_v("view/mode", "Cockpit")
	await get_tree().process_frame
	var target := (m.cockpit.interior.find_child("pivot_athr", true, false) as Node3D).global_position
	if _aim.begins_with("fg:"):
		var p := _aim.substr(3).split(",")
		target = m.to_global(m.fg_to_local(Vector3(float(p[0]), float(p[1]), float(p[2]))))
	elif _aim != "athr":
		target = (m.cockpit.interior.find_child("pivot_" + _aim, true, false) as Node3D).global_position
	cam._look_goal = CameraLook.aim_at(m.global_transform.basis.inverse() * (target - cam.global_position).normalized())
	cam._look = cam._look_goal
	var look := cam._look_goal
	cam._fov_goal = _fov
	cam._fov_cockpit = _fov
	await get_tree().create_timer(2.0).timeout
	_report("start")
	for st in _steps:
		var p := st.split(":")
		if p[0] == "wait":
			await get_tree().create_timer(float(p[1])).timeout
		elif p[0] == "set":
			_put(st.substr(4))
		elif p[0] == "shot":
			get_viewport().get_texture().get_image().save_png(_shots.path_join(p[1] + ".png"))
		else:
			var pv := m.cockpit.interior.find_child("pivot_" + (p[1] if p[0] == "drag" else p[0].trim_prefix("+")), true, false) as Node3D
			var at: Vector2 = get_viewport().get_final_transform() * cam.unproject_position(pv.global_position)
			if p[0] == "drag":
				await _drag(at, -float(p[2]))
			else:
				await _click(at, p[0].begins_with("+"))
			cam._look_goal = look
			cam._look = look
			await get_tree().create_timer(0.6).timeout
		_report(st)
	get_tree().quit()
