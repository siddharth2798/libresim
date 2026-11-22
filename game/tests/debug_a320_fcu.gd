extends Node
## Debug: the A320 glareshield FCU in the real flight scene, worked with injected mouse clicks.
## The pilot's head is turned to the FCU and zoomed in; each step clicks a cockpit control at its projected
## window position (Input.parse_input_event), waits, prints the properties and saves <shots>/<tag>_<step>.png.
##   godot --path game res://tests/debug_a320_fcu.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --air \
##     --view=cockpit --shots=<abs dir> --tag=day [--tod=21] [--steps=ap1,loc,athr,ap1] [--fov=16] [--aim=athr]
## A step is a pivot name (click it), "+name" (Shift+click: pull a knob), "drag:name:px" (drag a knob up by px).
var f: Node
var _shots := ""
var _tag := "fcu"
var _fov := 16.0
var _aim := "athr"
var _steps: PackedStringArray = ["ap1", "loc", "athr", "appr", "ap1"]
const PROPS := ["controls/fcu/ap1", "ap/ap1", "controls/fcu/ap2", "ap/ap2", "controls/fcu/athr", "ap/athr", "controls/fcu/loc",
	"ap/loc", "controls/fcu/appr", "ap/appr", "controls/fcu/spd_managed", "controls/fcu/hdg_managed", "controls/fcu/vs_managed",
	"controls/fcu/hdg_deg", "controls/fcu/spd_kt", "controls/fcu/alt_ft", "controls/fcu/vs_fpm", "ap/fma/lateral", "ap/fma/vertical",
	"controls/fcu/fd", "ap/fd", "controls/efis/ls", "controls/efis/nd_filter", "controls/nd/range_nm", "controls/nd/mode",
	"controls/baro/std", "controls/baro/hpa"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--fov="):
			_fov = float(a.substr(6))
		elif a.begins_with("--aim="):
			_aim = a.substr(6)
		elif a.begins_with("--steps="):
			_steps = a.substr(8).split(",", false)
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _pivot(m: AircraftModel, n: String) -> Node3D:
	return m.cockpit.interior.find_child("pivot_" + n, true, false) as Node3D


## Window position of a world point (viewport -> window: content scale and Retina).
## --aim=<pivot> or --aim=fg:x,y,z (FlightGear model frame, x aft, y right, z up).
func _aim_point(m: AircraftModel) -> Vector3:
	if _aim.begins_with("fg:"):
		var p := _aim.substr(3).split(",")
		return m.to_global(m.fg_to_local(Vector3(float(p[0]), float(p[1]), float(p[2]))))
	return _pivot(m, _aim).global_position


## --probe-px="x,y;x,y": the FlightGear-frame point of the interior surface under each viewport pixel.
func _probe_px(cam: Camera3D, m: AircraftModel, spec: String) -> void:
	var zero := m.fg_to_local(Vector3.ZERO)
	var meshes: Array = m.cockpit.interior.find_children("*", "MeshInstance3D", true, false)
	for px in spec.split(";", false):
		var xy := px.split(",")
		var sp := Vector2(float(xy[0]), float(xy[1]))
		var from := cam.project_ray_origin(sp)
		var dir := cam.project_ray_normal(sp)
		var best := INF
		var best_n := ""
		var best_p := Vector3.ZERO
		for mi in meshes:
			var inst := mi as MeshInstance3D
			if inst.mesh == null or not inst.is_visible_in_tree():
				continue
			var inv := inst.global_transform.affine_inverse()
			var hit := inst.mesh.generate_triangle_mesh().intersect_ray(inv * from, (inv.basis * dir).normalized())
			if hit.is_empty():
				continue
			var w: Vector3 = inst.global_transform * (hit.position as Vector3)
			var t := (w - from).length()
			if t < best:
				best = t
				best_n = inst.name
				best_p = w
		var l := m.to_local(best_p) - zero
		print("PROBE px %s -> %s FG (%.4f, %.4f, %.4f)" % [px, best_n, l.z, l.x, l.y])


func _window_at(cam: Camera3D, p: Vector3) -> Vector2:
	return get_viewport().get_final_transform() * cam.unproject_position(p)


func _click(at: Vector2, shift := false) -> void:
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


func _report(step: String) -> void:
	var s := "STATE %s:" % step
	for p in PROPS:
		s += " %s=%s" % [p.trim_prefix("controls/"), Props.get_v(p, null)]
	print(s)


func _run() -> void:
	await get_tree().create_timer(8.0).timeout
	var cam: CameraRig = f.get_node("Camera")
	var m: AircraftModel = f.get_node("Aircraft")
	cam.set_mode(0)
	Props.set_v("view/mode", "Cockpit")
	await get_tree().process_frame
	var target := _aim_point(m)
	cam._look_goal = CameraLook.aim_at(m.global_transform.basis.inverse() * (target - cam.global_position).normalized())
	cam._look = cam._look_goal
	var look := cam._look_goal
	cam._fov_goal = _fov
	cam._fov_cockpit = _fov
	await get_tree().create_timer(2.0).timeout
	print("VIEWPORT ", get_viewport().get_visible_rect().size, " window ", DisplayServer.window_get_size(), " final ", get_viewport().get_final_transform())
	for n in ["ap1", "ap2", "athr", "loc", "appr", "spd_sel", "hdg_sel", "alt_sel", "vs_sel", "athr_disc_l"]:
		var pv := _pivot(m, n)
		if pv == null:
			print("PICK %s: no pivot" % n)
			continue
		var sp := cam.unproject_position(pv.global_position)
		var hit := CockpitPick.pick(m.cockpit.lever_items(), cam.project_ray_origin(sp), cam.project_ray_normal(sp))
		print("PICK %s at %s -> %s" % [n, sp, (hit.get("node") as Node).name if not hit.is_empty() else "nothing"])
	_report("start")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-px="):
			_probe_px(cam, m, a.substr(11))
	for ln in ["lamp_athr", "hdg_sel"]:
		var lm := m.cockpit.interior.find_child(ln, true, false) as MeshInstance3D
		var mat := lm.get_active_material(0)
		print("LAMP %s %s %s" % [ln, mat.get_class(), (mat as BaseMaterial3D).resource_name if mat is BaseMaterial3D else ""])
		if mat is BaseMaterial3D:
			var b := mat as BaseMaterial3D
			print("   emis %s %s tex %s energy %.2f albedo_tex %s ao %s shading %d" % [b.emission_enabled, b.emission, b.emission_texture.resource_path if b.emission_texture else "-", b.emission_energy_multiplier, b.albedo_texture.resource_path if b.albedo_texture else "-", b.ao_enabled, b.shading_mode])
	get_viewport().get_texture().get_image().save_png(_shots.path_join("%s_0_idle.png" % _tag))
	var i := 0
	for st in _steps:
		i += 1
		var shift := st.begins_with("+")
		var parts := st.trim_prefix("+").split(":")
		var pv := _pivot(m, parts[1] if parts[0] == "drag" else parts[0])
		var at := _window_at(cam, pv.global_position)
		if parts[0] == "drag":
			await _drag(at, -float(parts[2]))
		else:
			await _click(at, shift)
		await get_tree().create_timer(1.2).timeout
		cam._look_goal = look  # the real pointer may have dragged the head while the injected button was down
		cam._look = look
		await get_tree().create_timer(0.3).timeout
		_report(st)
		if OS.get_cmdline_user_args().has("--lamp-probe"):
			var lm := m.cockpit.interior.find_child("lamp_athr", true, false) as MeshInstance3D
			var b := lm.get_active_material(0) as BaseMaterial3D
			print("LAMPNOW vis %s emis %s %s energy %.2f tex %s" % [lm.is_visible_in_tree(), b.emission_enabled, b.emission, b.emission_energy_multiplier, b.emission_texture])
			get_viewport().get_texture().get_image().save_png(_shots.path_join("%s_probe_a.png" % _tag))
			b.emission_enabled = false
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png(_shots.path_join("%s_probe_noemis.png" % _tag))
			lm.visible = false
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png(_shots.path_join("%s_probe_hidden.png" % _tag))
		get_viewport().get_texture().get_image().save_png(_shots.path_join("%s_%d_%s.png" % [_tag, i, st.replace(":", "_").replace("+", "pull_")]))
	get_tree().quit()
