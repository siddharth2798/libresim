extends Node
## Debug: A320 exterior / flight-deck models (aircraft/a320/models/*.glb, tools/blender/convert_a320*.py).
## Loads both glbs without an AircraftDef or the FDM, checks every pivot named in the draft
## aircraft/a320/model_sections.json exists, counts triangles, drives the pivots the way AircraftModel will
## (value * sign, optional piecewise "map" in degrees) and saves PNGs.
##   godot --path game res://tests/debug_a320_model.tscn --audio-driver Dummy -- --out=<dir> [--views=a,b] [--pose=down|clean|spoil]
## Views: front rear side top wing gear engine tail cockpit pfd overhead pedestal. Frame: model frame x aft, y right,
## z up (structural metres) -> Godot local (y, z, x), i.e. exactly AircraftModel.fg_transform with origin_m = 0.

const SECTIONS := "res://aircraft/a320/model_sections.json"
const GROUND_Z := -4.357  # config.json gear contact (LEFT_MLG) z

var ext: Node3D
var inter: Node3D
var cam: Camera3D
var sections := {}
var _pivots := {}
var _out := "user://"
var _views: PackedStringArray = []
var _pose := "clean"


func fg(p: Vector3) -> Vector3:
	return Vector3(p.y, p.z, p.x)


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--views="): _views = a.substr(8).split(",")
		elif a.begins_with("--pose="): _pose = a.substr(7)
	if _views.is_empty():
		_views = PackedStringArray(["front", "rear", "side", "top", "wing", "gear", "engine", "tail", "cockpit", "pfd", "overhead", "pedestal"])
	DirAccess.make_dir_recursive_absolute(_out)
	sections = JSON.parse_string(FileAccess.get_file_as_string(SECTIONS))
	_world()
	ext = (load("res://aircraft/a320/models/exterior.glb") as PackedScene).instantiate()
	ext.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	add_child(ext)
	AircraftModel.fix_glass(ext, false)
	AircraftModel.lift_tyres(ext)
	var il := ResourceLoader.exists("res://aircraft/a320/models/interior.glb")
	if il:
		inter = (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()
		inter.transform = ext.transform
		add_child(inter)
		AircraftModel.fix_glass(inter)
	report()
	pose(_pose)
	cam = Camera3D.new()
	cam.far = 400.0
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	for v in _views:
		await shoot(v)
	get_tree().quit()


func report() -> void:
	var miss := []
	for k in sections.model.surfaces:
		var n := ext.find_child("pivot_" + k, true, false) as Node3D
		if n == null:
			miss.append(k)
		else:
			_pivots[k] = [n, n.transform.basis]
	for p in sections.model.get("propellers", []):
		if ext.find_child("pivot_" + str(p.pivot), true, false) == null:
			miss.append(str(p.pivot))
	print("PIVOTS ", sections.model.surfaces.size(), " missing ", miss)
	print("TRIS exterior ", tris(ext), " interior ", tris(inter) if inter else 0)
	print("MATS exterior ", mats(ext), " interior ", mats(inter) if inter else 0)


func tris(n: Node) -> int:
	var t := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			t += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t


func mats(n: Node) -> int:
	var d := {}
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			d[m.surface_get_material(s)] = true
	return d.size()


## value for a drive name in a named pose
func drive_value(drive: String) -> float:
	var down := _pose == "down"
	match drive:
		"aileron": return 0.4 if _pose == "ctrl" else 0.0
		"elevator": return 0.4 if _pose == "ctrl" else 0.0
		"rudder": return 0.4 if _pose == "ctrl" else 0.0
		"flap_deg": return 35.0 if down else 0.0
		"slat_deg": return 27.0 if down or _pose == "ctrl" else 0.0
		"gear_pos": return 1.0 if _pose != "gearup" else 0.0
		"reverser": return 1.0 if _pose == "rev" else 0.0
		"stabilizer_deg": return -8.0 if _pose == "ctrl" else 0.0
		"nose_steer_deg": return 40.0 if _pose == "ctrl" else 0.0
	if drive.begins_with("spoiler_"):
		return 50.0 if _pose == "spoil" else 0.0
	return 0.0


func pose(name: String) -> void:
	_pose = name
	for k in _pivots:
		var s: Dictionary = sections.model.surfaces[k]
		var v := drive_value(str(s.drive))
		var drive := str(s.drive)
		var a := v * float(s.sign)
		if s.has("map"):
			a = deg_to_rad(_interp(s.map, v)) * float(s.sign)
		elif drive.ends_with("_deg"):
			a = deg_to_rad(v) * float(s.sign)
		_pivots[k][0].transform.basis = _pivots[k][1] * Basis(Vector3.RIGHT, a)


func _interp(map: Array, x: float) -> float:
	if x <= float(map[0][0]):
		return float(map[0][1])
	for i in range(1, map.size()):
		if x <= float(map[i][0]):
			var t: float = (x - float(map[i - 1][0])) / (float(map[i][0]) - float(map[i - 1][0]))
			return lerpf(float(map[i - 1][1]), float(map[i][1]), t)
	return float(map[map.size() - 1][1])


func _world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.27, 0.28, 0.29)
	ground.material_override = gm
	ground.position = Vector3(0, GROUND_Z, 0)
	add_child(ground)


func eye() -> Vector3:
	var e: Array = sections.cockpit.eye
	return Vector3(e[0], e[1], e[2])


func look(from_fg: Vector3, to_fg: Vector3, fov := 50.0) -> void:
	cam.position = fg(from_fg)
	cam.look_at(fg(to_fg), Vector3.UP)
	cam.fov = fov


func shoot(view: String) -> void:
	var interior := false
	match view:
		"front": look(Vector3(-45, -22, 3), Vector3(0, 0, -1), 45)
		"rear": look(Vector3(48, 20, 5), Vector3(0, 0, 0), 45)
		"side": look(Vector3(0, -60, 0), Vector3(0, 0, 0), 38)
		"top": look(Vector3(0, 0.1, 70), Vector3(0, 0, 0), 38)
		"wing": look(Vector3(8, -20, 3), Vector3(0, -9, -0.5), 55)
		"gear": look(Vector3(-6, -11, -1.5), Vector3(-1.5, -3.9, -3.0), 60)
		"nose": look(Vector3(-20, -5, -2.5), Vector3(-13.6, 0, -3.0), 55)
		"engine": look(Vector3(-13, -9, -1), Vector3(-6.5, -5.6, -2.3), 50)
		"tail": look(Vector3(28, -12, 5), Vector3(16, 0, 3), 50)
		"cockpit": interior = true; look(eye(), Vector3(-30, eye().y, eye().z - 3), 75)
		"pfd": interior = true; look(eye(), Vector3(-17.05, -0.57, 0.13), 30)
		"overhead": interior = true; look(eye(), Vector3(-16.1, 0.0, 1.0), 70)
		"pedestal": interior = true; look(eye(), Vector3(-16.4, 0.0, -0.2), 70)
	ext.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	var path := "%s/a320_%s_%s.png" % [_out, _pose, view]
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
