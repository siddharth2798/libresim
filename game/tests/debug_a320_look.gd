extends Node
## Debug: screenshots of the aircraft in the real scene from camera views or free-camera points given in structural
## metres (x aft, y right, z up), optionally with the exterior lights on.
##   godot --path game res://tests/debug_a320_look.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --clean \
##     --shots=<abs dir> [--at=8] [--lights] [--eyepoint] \
##     --views="name|chase;door|free|-24,-16,1|-13,-2,0.5;pilot|cockpit"
## A view is  name | mode [| eye | target]:  mode = cockpit|chase|orbit|wing|tail|flyby|tower or free (eye and target
## structural metres from the model origin; fov = 65). Screenshots are named <name>.png in --shots (use an absolute path).
var f: Node
var _shots := ""
var _at := 8.0
var _lights := false
var _jetway := false
var _views: Array = []
const MODES := {"cockpit": 0, "chase": 1, "orbit": 2, "free": 3, "tower": 4, "wing": 5, "tail": 6, "flyby": 7}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--at="):
			_at = float(a.substr(5))
		elif a == "--jetway":
			_jetway = true
		elif a == "--lights":
			_lights = true
		elif a.begins_with("--views="):
			for v in a.substr(8).split(";", false):
				_views.append(v.split("|"))
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	await get_tree().create_timer(_at).timeout
	if _lights:
		for k in ["nav", "beacon", "strobe", "landing", "taxi"]:
			Props.set_v("controls/lights/" + k, true)
		Props.set_v("controls/electrical/master_bat", true)
	if _jetway:
		_report_jetway()
	var cam: CameraRig = f.get_node("Camera")
	for v in _views:
		var mode: String = v[1] if v.size() > 1 else "chase"
		cam.set_mode(MODES[mode])
		cam._label_t = 0.0
		if mode == "free":
			_place(cam, _vec(v[2]), _vec(v[3]))
		await get_tree().create_timer(2.0).timeout
		if mode == "free":
			_place(cam, _vec(v[2]), _vec(v[3]))
		await get_tree().create_timer(0.7).timeout
		if _lights:  # freeze the flashing lights in their bright phase for the shot
			var al: AircraftLights = (f.get_node("Aircraft") as AircraftModel).find_children("*", "AircraftLights", true, false)[0]
			al.set_process(true)
			al._t = 0.01
			al._process(0.0)
			al.set_process(false)
			await get_tree().process_frame
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(_shots.path_join(v[0] + ".png"))
		print("SHOT ", v[0])
	get_tree().quit()


func _place(cam: CameraRig, eye: Vector3, target: Vector3) -> void:
	var m: AircraftModel = f.get_node("Aircraft")
	var enu_e := FloatingOrigin.to_world(m.global_transform * m._s(eye))
	var enu_t := FloatingOrigin.to_world(m.global_transform * m._s(target))
	cam._free_enu = enu_e
	var d := enu_t - enu_e
	cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))


## --jetway: the jetway mesh corner nearest the L1 door (structural metres, x aft, y right, z up) = where a cab meets it.
func _report_jetway() -> void:
	var m: AircraftModel = f.get_node("Aircraft")
	var cg: Vector3 = f.get_node("Fdm").fdm.mb.cg
	var door := Vector3(-13.78, -1.95, 0.5)
	var best := [INF, "", Vector3.ZERO]
	for n in f.get_node("AirportOps").find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var bb := mi.get_aabb()
		for i in 8:
			var l := m.to_local(mi.global_transform * bb.get_endpoint(i))
			var st := Vector3(l.z + cg.x, l.x + cg.y, l.y + cg.z)
			if st.z > -1.0 and st.distance_to(door) < best[0]:  # parts at door height or above (not the ground marks)
				best = [st.distance_to(door), mi.name, st]
	print("JETWAY nearest high corner %s struct (%.2f %.2f %.2f)  d to door %.1f  (door -13.78 -1.95 0.5)" % [best[1], best[2].x, best[2].y, best[2].z, best[0]])
