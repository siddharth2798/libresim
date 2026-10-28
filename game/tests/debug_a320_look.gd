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
var _views: Array = []
const MODES := {"cockpit": 0, "chase": 1, "orbit": 2, "free": 3, "tower": 4, "wing": 5, "tail": 6, "flyby": 7}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--at="):
			_at = float(a.substr(5))
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
