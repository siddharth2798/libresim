extends Node
## Debug (windowed, the GPU draws): gear close-ups of an air-start aircraft banked at several angles, gear down.
## The FDM is held and given a roll; the camera sits on the airframe (body frame) so a part that moves relative to
## the airframe shows at once. Saves <out>/<tag>_<roll>_<view>.png and a chase view, prints the gear node offsets.
##   godot --path game --windowed --resolution 960x600 --audio-driver Dummy res://tests/debug_gear_bank.tscn -- \
##     --out=<dir> --tag=before [--aircraft=a320] [--rolls=0,45,75,-75] [--pitch=3]
const VIEWS := {  # body frame (forward, right, up) m from the aircraft node: [eye, target]
	"mainL": [Vector3(3.0, -10.0, -2.2), Vector3(-1.4, -3.9, -3.4)],
	"mainR": [Vector3(3.0, 10.0, -2.2), Vector3(-1.4, 3.9, -3.4)],
	"nose": [Vector3(11.0, -3.5, -3.0), Vector3(10.6, 0.0, -3.4)],
}
var _out := "user://"
var _tag := "bank"
var _rolls: Array = [0.0, 45.0, 75.0, -75.0]
var _pitch := 3.0
var _flight: Node
var _cam: CameraRig
var _model: Node3D
var _aim := ""
var _chase := false


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--tag="): _tag = a.substr(6)
		elif a.begins_with("--pitch="): _pitch = float(a.substr(8))
		elif a.begins_with("--rolls="):
			_rolls = []
			for s in a.substr(8).split(","):
				_rolls.append(float(s))
	DirAccess.make_dir_recursive_absolute(_out)
	_flight = load("res://world/flight.tscn").instantiate()
	add_child(_flight)
	_cam = _flight.get_node("Camera")
	_model = _flight.get_node("Aircraft")
	_run.call_deferred()


func _process(_dt: float) -> void:
	if _model == null or _cam == null or _cam.mode != CameraRig.Mode.FREE:
		return
	var t := _model.global_transform
	var eye: Vector3
	var target: Vector3
	if _chase:
		eye = t.origin + t.basis.x * -22.0 + t.basis.y * -8.0 + (-t.basis.z) * -14.0
		eye.y = maxf(eye.y, t.origin.y - 18.0)
		target = t.origin + t.basis.y * -3.0
	elif _aim != "":
		var v: Array = VIEWS[_aim]
		eye = t.origin + (-t.basis.z) * v[0].x + t.basis.x * v[0].y + t.basis.y * v[0].z
		target = t.origin + (-t.basis.z) * v[1].x + t.basis.x * v[1].y + t.basis.y * v[1].z
	else:
		return
	var d := target - eye
	_cam._free_enu = FloatingOrigin.to_world(eye)
	_cam._look = Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	_cam._look_goal = _cam._look


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _run() -> void:
	await _wait(3.0)
	var fn: FdmNode = _flight.get_node("Fdm")
	fn.paused = true
	_cam.set_mode(CameraRig.Mode.FREE)
	var ext: Node3D = _model.get("_glb") if _model.get("_glb") else _model.get_child(0)
	for r in _rolls:
		var e := fn.fdm.euler()
		fn.fdm.q = FDM.euler_to_quat(deg_to_rad(r), deg_to_rad(_pitch), e.z)
		fn._snap()
		await _wait(1.0)
		_report(ext, r)
		for v in VIEWS:
			_aim = v
			_chase = false
			await _wait(0.8)
			get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%d_%s.png" % [_tag, int(r), v]))
		_aim = ""
		_chase = true
		await _wait(0.8)
		get_viewport().get_texture().get_image().save_png(_out.path_join("%s_%d_chase.png" % [_tag, int(r)]))
		_chase = false
	get_tree().quit()


func _report(ext: Node3D, r: float) -> void:
	var out := PackedStringArray()
	for nm in ["pivot_gear_main_L", "MLGSlidingTubeAxleL", "MLGSlidingTubeAxleR", "MLGTorqueLinkL1"]:
		var nd := ext.find_child(nm, true, false) as Node3D
		if nd:
			out.append("%s %s" % [nm, nd.position])
	print("GEARBANK roll %d: %s" % [int(r), "; ".join(out)])
