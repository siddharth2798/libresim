extends Node
## Tool: renders the start-screen picture of every installed aircraft (or the ids given) from its own
## exterior model into res://aircraft/<id>/preview.jpg (AircraftDef "preview", ui/menu/aircraft_page.gd).
##   godot --path game --resolution 1680x350 --windowed --audio-driver Dummy res://tests/render_aircraft_previews.tscn [-- --ids=c172,a320]
## Frame of the glb: x aft, y right, z up (AircraftModel.fg_transform basis). Needs a window (the GPU renders it).

const SIZE := Vector2i(1680, 350)
const AZIMUTH_DEG := 38.0  # camera to the front-left of the nose
const ELEVATION_DEG := 11.0
const DISTANCE := 1.1  # camera distance in bounding-sphere radii (the aircraft is flat: the sphere is mostly empty)


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	get_window().size = SIZE
	var ids: Array = AircraftDef.list_ids()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids = a.substr(6).split(",")
	for id in ids:
		await _render(AircraftDef.load_def(id))
	get_tree().quit()


func _render(def: AircraftDef) -> void:
	var root := Node3D.new()
	add_child(root)
	var model := (load(def.path("exterior")) as PackedScene).instantiate() as Node3D
	model.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	root.add_child(model)
	AircraftModel.fix_glass(model, false)
	AircraftModel.lift_tyres(model)
	var box := _bounds(model)
	var centre := box.get_center()
	var radius := box.size.length() * 0.5

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 40.0, radius * 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.52, 0.53, 0.54)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(centre.x, box.position.y, centre.z)
	root.add_child(ground)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.32, 0.54, 0.86)
	sky.sky_horizon_color = Color(0.74, 0.84, 0.93)
	sky.ground_horizon_color = Color(0.74, 0.84, 0.93)
	sky.ground_bottom_color = Color(0.52, 0.53, 0.54)
	var s := Sky.new()
	s.sky_material = sky
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.far = radius * 200.0
	root.add_child(cam)
	var az := deg_to_rad(AZIMUTH_DEG)
	var el := deg_to_rad(ELEVATION_DEG)
	# nose is at -x of the model frame, i.e. toward render -z after the basis; the model's own front is Godot +x
	var dir := Vector3(cos(el) * cos(az), sin(el), -cos(el) * sin(az))
	cam.global_position = centre + dir * radius * DISTANCE
	cam.look_at(centre + Vector3(0, -radius * 0.03, 0))
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var out := ProjectSettings.globalize_path(def.dir + "/preview.jpg")
	var err := img.save_jpg(out, 0.88)
	print("PREVIEW %s -> %s (%s) %dx%d" % [def.id, out, error_string(err), img.get_width(), img.get_height()])
	root.queue_free()
	await get_tree().process_frame


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
