extends Node
## Debug: look at the jetway cab end of the nearest jetbridge and measure frame-to-frame flicker.
##   godot --audio-driver Dummy --path game res://tests/debug_jetway.tscn -- --airport=VABB --stand [--dist=25 --yaw=0 --h=4 --hide=Hood,Entrance --uni --noshadow --dump] --shots=<dir>
## Saves N consecutive frames of a static camera and prints the mean abs pixel difference of the cab region.
var f: Node
var t := 0.0
var _shots := ""
var _yaw := 0.0
var _jit := 0.0  # camera moves this many metres per frame along the jetway's z
var _off := Vector3(8, 1, 10)  # camera offset from the cab end in jetway-local axes
var _hide: PackedStringArray = []
var _uni := false
var _noshadow := false
var _dump := false
var _jw: Node3D
var _frames: Array[Image] = []
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): _shots = a.substr(8)
		elif a.begins_with("--off="):
			var v := a.substr(6).split(",")
			_off = Vector3(float(v[0]), float(v[1]), float(v[2]))
		elif a.begins_with("--hide="): _hide = a.substr(7).split(",")
		elif a.begins_with("--jit="): _jit = float(a.substr(6))
		elif a == "--uni": _uni = true
		elif a == "--noshadow": _noshadow = true
		elif a == "--dump": _dump = true
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _find_jetway() -> Node3D:
	var best: Node3D
	var bd := INF
	for hood in f.get_node("AirportOps").find_children("Hood", "MeshInstance3D", true, false):
		var d: float = (hood.global_position - f.get_node("Camera").global_position).length()
		if d < bd:
			bd = d
			best = hood.get_parent() as Node3D
	return best


func _cab_pos() -> Vector3:
	return _jw.to_global(Vector3(16.5 * _jw.scale.x, 4.8, 0.0))  # approx cab end, local


func _process(dt: float) -> void:
	t += dt
	if t > 3.0 and _jw == null:
		_jw = _find_jetway()
		if _jw == null:
			print("NO JETWAY"); get_tree().quit(); return
		print("JETWAY ", _jw.get_path(), " pos ", _jw.global_position, " scale ", _jw.scale)
		if _dump:
			for m in _jw.find_children("*", "MeshInstance3D", true, false):
				var mi := m as MeshInstance3D
				var s := ""
				for i in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(i) as BaseMaterial3D
					s += " [%s tr=%d cull=%d alb=%s]" % [mat.resource_name, mat.transparency, mat.cull_mode, mat.albedo_color] if mat else " [none]"
				print("MESH ", mi.name, " aabb ", mi.get_aabb(), " shadow=", mi.cast_shadow, s)
		for n in _hide:
			for m in _jw.find_children(n, "MeshInstance3D", true, false):
				m.visible = false
		if _uni:
			_jw.scale = Vector3.ONE
		if _noshadow:
			for m in _jw.find_children("*", "MeshInstance3D", true, false):
				(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cam = Camera3D.new()
		_cam.near = 0.05
		_cam.far = 160000.0
		add_child(_cam)
		_cam.make_current()
	if _jw and t > 5.0:
		var c := _cab_pos()
		var cam3 := _cam
		cam3.global_position = _jw.to_global(Vector3(16.5 * _jw.scale.x, 4.8, 0.0) + _off)
		cam3.global_position += _jw.global_transform.basis.z * _jit * _frames.size()
		cam3.look_at(c)
		if t > 6.0:
			_frames.append(get_viewport().get_texture().get_image())
			if _frames.size() >= 8:
				_report(cam3.unproject_position(c))
				get_tree().quit()


func _report(p: Vector2) -> void:
	var r := Rect2i(Vector2i(p) - Vector2i(150, 100), Vector2i(300, 200)).intersection(Rect2i(Vector2i.ZERO, _frames[0].get_size()))
	var tot := 0.0
	for i in range(1, _frames.size()):
		var s := 0.0
		for y in range(r.position.y, r.end.y, 2):
			for x in range(r.position.x, r.end.x, 2):
				var a := _frames[i - 1].get_pixel(x, y)
				var b := _frames[i].get_pixel(x, y)
				s += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		tot += s / (r.size.x * r.size.y / 4.0)
	print("FLICKER %.5f" % (tot / (_frames.size() - 1)))
	if _shots != "":
		for i in _frames.size():
			_frames[i].save_png(_shots.path_join("f%d.png" % i))
