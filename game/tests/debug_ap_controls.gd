extends Node
## Debug: the A320 disconnect key, the Autopilot failure and the wheel over cockpit knobs in the real flight scene with injected
## input (a key event through Input.parse_input_event, a wheel event at the projected knob), one report line per step.
##   godot --audio-driver Dummy --path game res://tests/debug_ap_controls.tscn -- --aircraft=a320 --airport=VABB --air \
##     --shots=<abs dir> --steps=ap1,wait:3,key:disc,wait:1,shot:warn,wheel:hdg_sel:3,wheel:hdg_sel:-1,set:failures/ap=true
## Steps: <pivot> click, key:disc (Ctrl+Backspace) / key:athr (Ctrl+Shift+Backspace), wheel:<pivot>:<notches> (+ up), wait:<s>,
## set:<prop>=<value>, shot:<name>. Pivots: ap1 ap2 athr hdg_sel spd_sel alt_sel vs_sel.
var f: Node
var _shots := ""
var _steps: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--steps="):
			_steps = a.substr(8).split(",", false)
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _mouse(at: Vector2, button: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button as MouseButton
	e.pressed = down
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _key(code: int, ctrl: bool, shift: bool) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code as Key
		e.physical_keycode = code as Key
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame


func _report(step: String) -> void:
	print("STEP %-20s | ap1=%d ap2=%d athr=%d warn=%d count=%d fail=%d | FMA %s | EWD [%s] | hdg_sel %.0f alt_sel %.0f spd %.0f fov %.1f | t %.0f" % [
		step, int(Props.get_b("ap/ap1")), int(Props.get_b("ap/ap2")), int(Props.get_b("ap/athr")), int(Props.get_b("ap/disconnect_warning")),
		int(Props.get_v("ap/disconnect_count", 0)), int(Props.get_b("failures/ap")), str(Props.get_v("ap/fma/misc", "")).replace("\n", "/"),
		str(Props.get_v("ewd/warnings_text", "")).replace("\n", "; "), Props.get_f("controls/fcu/hdg_deg"), Props.get_f("controls/fcu/alt_ft"),
		Props.get_f("controls/fcu/spd_kt"), (f.get_node("Camera") as CameraRig)._fov_goal, Time.get_ticks_msec() / 1000.0])


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
	var target := (m.cockpit.interior.find_child("pivot_hdg_sel", true, false) as Node3D).global_position
	cam._look_goal = CameraLook.aim_at(m.global_transform.basis.inverse() * (target - cam.global_position).normalized())
	cam._look = cam._look_goal
	var look := cam._look_goal
	cam._fov_goal = 40.0
	cam._fov_cockpit = 40.0
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
		elif p[0] == "key":
			await _key(KEY_BACKSPACE, true, p[1] == "athr")
		else:
			var name: String = p[1] if p[0] == "wheel" else p[0]
			var pv := m.cockpit.interior.find_child("pivot_" + name, true, false) as Node3D
			var at: Vector2 = get_viewport().get_final_transform() * cam.unproject_position(pv.global_position)
			if p[0] == "wheel":
				var n := int(p[2])
				for i in absi(n):
					await _mouse(at, MOUSE_BUTTON_WHEEL_UP if n > 0 else MOUSE_BUTTON_WHEEL_DOWN, true)
			else:
				await _mouse(at, MOUSE_BUTTON_LEFT, true)
				await _mouse(at, MOUSE_BUTTON_LEFT, false)
			cam._look_goal = look
			cam._look = look
			await get_tree().create_timer(0.6).timeout
		_report(st)
	get_tree().quit()
