extends Node
## Debug: start at a stand and render it.
##   godot --path game res://tests/debug_stand.tscn -- --airport=VABB --stand
## One orbit shot goes to the user data dir (a2.png). With --shots=<dir> it saves three PNGs there
## instead: stand_chase.png (default chase camera), stand_orbit.png (orbit 60 m away, from behind
## the stand's tail so the terminal is beyond the nose) and stand_overview.png (free camera
## --alt=<m> above the stand, default 120, 60 m behind it, looking down and ahead).
## --cam=east,north,height_agl,yaw_deg,pitch_deg instead puts the free camera there (any start, e.g.
## --runway=09) and saves one cam.png to the --shots dir after 6 s.
## Add --tod=12 --weather=clear etc. as for the game.
var t := 0.0
var f: Node
var _shots := ""
var _alt := 120.0
var _cam := PackedFloat64Array()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--alt="):
			_alt = float(a.substr(6))
		elif a.begins_with("--cam="):
			_cam = PackedFloat64Array(Array(a.substr(6).split(",")).map(func(v): return float(v)))
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("SHOT ", name)


func _process(dt: float) -> void:
	t += dt
	var cam: CameraRig = f.get_node("Camera")
	if _shots == "":
		if t > 1.0:
			cam.mode = CameraRig.Mode.ORBIT
			cam._dist = 90.0
			cam._look = Vector2(0.6, -0.55)
		if t > 4.0:
			print("STAND ", Props.get_v("ops/stand", "?"))
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/a2.png")
			get_tree().quit()
		return
	if _cam.size() == 5:
		if t > 3.0 and t - dt <= 3.0:
			cam.set_mode(CameraRig.Mode.FREE)
			cam._free_enu = Vector3(_cam[0], _cam[1], f.get_node("Terrain").height_at(_cam[0], _cam[1]) + _cam[2])
			cam._look = Vector2(-deg_to_rad(_cam[3]), deg_to_rad(_cam[4]))
		elif t > 6.0 and t - dt <= 6.0:
			_save("cam")
			get_tree().quit()
		return
	if t > 5.0 and t - dt <= 5.0:
		print("STAND ", Props.get_v("ops/stand", "?"))
		_save("stand_chase")
		cam.set_mode(CameraRig.Mode.ORBIT)
		cam._dist = 60.0
		cam._look = Vector2(-Props.get_f("fdm/heading_rad", 0.0) + PI, 0.1)
	elif t > 7.0 and t - dt <= 7.0:
		_save("stand_orbit")
		var p: Vector3 = f.get_node("Fdm").position_enu()
		cam.set_mode(CameraRig.Mode.FREE)
		var hd := Props.get_f("fdm/heading_rad", 0.0)
		cam._free_enu = Vector3(p.x - sin(hd) * 60.0, p.y - cos(hd) * 60.0, f.get_node("Terrain").height_at(p.x, p.y) + _alt)
		cam._look = Vector2(-hd, -1.0)
	elif t > 9.0 and t - dt <= 9.0:
		_save("stand_overview")
		get_tree().quit()
