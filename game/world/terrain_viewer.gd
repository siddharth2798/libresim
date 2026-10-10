extends Node3D
## M2 terrain viewer scene: wires the free camera to the terrain.
## Command line: -- --at=<east>,<north>,<alt> --heading=<deg> --shot=<png> (screenshot & quit)

var _shot := ""
var _t := 0.0


func _ready() -> void:
	var cam: FreeCamera = $Camera
	cam.terrain = $Terrain
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var v := a.substr(5).split(",")
			cam.start_enu = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif a.begins_with("--heading="):
			cam.start_heading_deg = float(a.substr(10))
		elif a.begins_with("--pitch="):
			cam.pitch = deg_to_rad(float(a.substr(8)))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
	cam._reset()


func _process(dt: float) -> void:
	if _shot.is_empty():
		return
	_t += dt
	if _t > 5.0 and _t - dt <= 5.0:  # let tiles stream in
		get_viewport().get_texture().get_image().save_png(_shot)
		print("saved ", _shot, "  fps ", Engine.get_frames_per_second())
		get_tree().quit()
