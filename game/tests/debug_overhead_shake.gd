extends Node
## Debug: does the A320 overhead move against the cockpit in flight, and why? Runs the real flight scene in the cockpit
## view, then for --frames rendered frames records (1) an overhead switch's transform against the interior root,
## (2) the cockpit eye's seat offset, (3) how far the engine's float32 render-space path (camera and node global
## transforms, what the GPU used before CockpitPrecision; unproject_position still uses it)
## puts an overhead point and a main-panel point on screen away from the exact cockpit-frame projection.
##   godot --path game res://tests/debug_overhead_shake.tscn --audio-driver Dummy -- --aircraft=a320 --air=35000 \
##     --air-kt=250 --view=cockpit [--turb=0.6] [--fov=15] [--frames=240] [--shots=<abs dir>] [--still] [--ahead]
## --shots saves the first 60 frames (aimed at the overhead); --still holds the seat dip at 0 (tests/debug_overhead_hold.gd).
var f: Node
var _frames := 240
var _fov := 15.0
var _turb := -1.0
var _shots := ""
var _still := false
var _ahead := false  # --ahead: the seated view straight ahead instead of aiming at the overhead
var _rows: Array = []
var _n := 0
var _armed := false
var _rest := Transform3D.IDENTITY


func _ready() -> void:
	process_priority = 50  # after the camera rig (10): this frame's camera
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--fov="):
			_fov = float(a.substr(6))
		elif a.begins_with("--turb="):
			_turb = float(a.substr(7))
		elif a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a == "--still":
			_still = true
		elif a == "--ahead":
			_ahead = true
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	if _still:  # before the camera rig (10): no seat dip this frame, so only render precision can move the panel
		var hold := Node.new()
		hold.process_priority = 5
		hold.set_script(_HOLD)
		add_child(hold)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(8.0).timeout
	if _turb >= 0.0:
		Props.set_v("weather/turbulence", _turb)
	var cam: CameraRig = f.get_node("Camera")
	cam.set_mode(CameraRig.Mode.COCKPIT)
	cam._label_t = 0.0
	var m: AircraftModel = f.get_node("Aircraft")
	var sw := _switch(m)
	var dir := (m.cockpit.eye.direction_to(m.transform.affine_inverse() * sw.global_position))
	cam._look_goal = Vector2.ZERO if _ahead else CameraLook.aim_at(dir)
	cam._fov_goal = _fov
	await get_tree().create_timer(3.0).timeout
	_rest = _rel(m, sw)
	get_viewport().warp_mouse(Vector2(2, 2))  # no hover tip in the shots
	await get_tree().process_frame
	await get_tree().process_frame
	_armed = true


## The A320 beacon switch on the overhead; without one (C172) the first panel gauge quad.
func _switch(m: AircraftModel) -> Node3D:
	var n := m.cockpit.interior.find_child("pivot_beacon_lt", true, false) as Node3D
	return n if n != null else m.cockpit._quads[0][0]


## The node's transform in the interior root's frame, from the local chain (no world-space float32 rounding).
func _rel(m: AircraftModel, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != m.cockpit.interior and p != m.cockpit:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


const _HOLD := preload("res://tests/debug_overhead_hold.gd")


func _process(_dt: float) -> void:
	if not _armed:
		return
	var cam: CameraRig = f.get_node("Camera")
	var m: AircraftModel = f.get_node("Aircraft")
	var sw := _switch(m)
	var drift := _rel(m, sw).origin.distance_to(_rest.origin)
	var p_local := (m.cockpit.interior.transform if m.cockpit.interior.is_ancestor_of(sw) else Transform3D()) * _rel(m, sw).origin
	var q: MeshInstance3D = m.cockpit._quads[0][0]
	var q_local: Vector3 = q.transform.origin
	var eye_inv := cam.cockpit_local.affine_inverse()  # camera from aircraft
	var row := {"t": Time.get_ticks_msec(), "alt": cam.global_position.y, "seat_mm": cam._seat.x * 1000.0, "drift_mm": drift * 1000.0,
		"fov": cam.fov}
	for k in [["ovh", p_local, sw.global_position], ["pfd", q_local, q.global_position]]:
		var exact := _project(cam, eye_inv * k[1])
		var f32 := cam.unproject_position(k[2])
		row[k[0] + "_err_px"] = exact.distance_to(f32)
		row[k[0] + "_px"] = f32
		row[k[0] + "_exact"] = exact
		row[k[0] + "_dist"] = (eye_inv * k[1]).length()
	_rows.append(row)
	if _shots != "" and _n < 60:
		get_viewport().get_texture().get_image().save_png(_shots.path_join("f%03d.png" % _n))
	_n += 1
	if _n >= _frames:
		_report()
		get_tree().quit()


## Screen pixel of a point given in the camera's own frame (the camera looks along -Z).
func _project(cam: Camera3D, v: Vector3) -> Vector2:
	var vs := get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(cam.fov) * 0.5)  # vertical fov (keep_aspect height)
	var x := v.x / -v.z / tan_half
	var y := v.y / -v.z / tan_half
	return Vector2(vs.x * 0.5 + x * vs.y * 0.5, vs.y * 0.5 - y * vs.y * 0.5)


func _report() -> void:
	var stats := {"seat_mm": [], "drift_mm": [], "ovh_err_px": [], "pfd_err_px": [], "ovh_step_px": [], "pfd_step_px": [],
		"ovh_exact_step_px": []}
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		for k in ["seat_mm", "drift_mm", "ovh_err_px", "pfd_err_px"]:
			stats[k].append(r[k])
		if i > 0:
			var o: Dictionary = _rows[i - 1]
			stats.ovh_step_px.append((r.ovh_px - r.ovh_exact).distance_to(o.ovh_px - o.ovh_exact))
			stats.pfd_step_px.append((r.pfd_px - r.pfd_exact).distance_to(o.pfd_px - o.pfd_exact))
			stats.ovh_exact_step_px.append((r.ovh_exact as Vector2).distance_to(o.ovh_exact))
	var r0: Dictionary = _rows[0]
	var m: AircraftModel = f.get_node("Aircraft")
	var cp := m.cockpit.find_children("*", "CockpitPrecision", true, false)
	var all_m := m.cockpit.find_children("*", "MeshInstance3D", true, false).size()
	if not cp.is_empty():
		print("SHAKE precision: %d of %d cockpit meshes camera-relative, %d materials converted" % [cp[0]._meshes.size(), all_m, cp[0]._mats.size()])
		for row in cp[0]._mats:
			var tex = (row[1] as ShaderMaterial).get_shader_parameter("texture_albedo")
			if str(row[0].resource_name) == "a320_fd_main" and tex is Texture2D:
				print("SHAKE preset %s, a320_fd_main atlas %s" % [Graphics.preset, tex.get_size()])
	print("SHAKE alt %.0f m  fov %.1f  overhead %.2f m  pfd %.2f m from the eye  frames %d" % [r0.alt, r0.fov, r0.ovh_dist, r0.pfd_dist, _rows.size()])
	for k in stats:
		var a: Array = stats[k]
		var mx := 0.0
		var s := 0.0
		for v in a:
			mx = maxf(mx, absf(v))
			s += v * v
		var lo: float = a.min() if not a.is_empty() else 0.0
		var hi: float = a.max() if not a.is_empty() else 0.0
		print("SHAKE %-18s rms %.3f  max|.| %.3f  range %.3f..%.3f" % [k, sqrt(s / maxf(a.size(), 1.0)), mx, lo, hi])
