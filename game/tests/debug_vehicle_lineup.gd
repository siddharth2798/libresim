extends Node3D
## Debug: the ground vehicles side by side on a plain ground, with a few close-ups, saved as PNGs.
##   FREESIM_SHOTS=<dir> godot --audio-driver Dummy --path game --windowed res://tests/debug_vehicle_lineup.tscn -- [--old] [--night] [--only=fuel_truck]
## --old shows the previous imported models (world/models/vehicles/*.glb), for before / after pictures.
const KINDS := ["fuel_truck", "gpu", "baggage_tug", "baggage_cart", "apron_bus", "fire_truck", "pushback_tug", "follow_me"]


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var out := OS.get_environment("FREESIM_SHOTS")
	var old := "--old" in OS.get_cmdline_user_args()
	var night := "--night" in OS.get_cmdline_user_args()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9) if not night else Color(0.02, 0.03, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.66, 0.75)
	env.environment.ambient_light_energy = 0.7 if not night else 0.15
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.0 if not night else 0.0
	add_child(sun)
	if night:
		Props.set_v("environment/sun_elev_deg", -20.0)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.5, 0.5, 0.5)
	fm.roughness = 0.9
	floor_.material_override = fm
	add_child(floor_)
	var nodes := {}
	var i := 0
	for k in KINDS:
		var n: Node3D
		if k == "follow_me" and not old:
			n = FollowMeCar.new()
		elif old or not GroundVehicles.has(k):
			var packed: PackedScene = load("res://world/models/vehicles/%s.glb" % k)
			n = packed.instantiate()
			if k in ["apron_bus", "fire_truck", "pushback_tug"]:
				var h := Node3D.new()  # FlightGear models face -X
				n.rotation.y = -PI / 2
				h.add_child(n)
				n = h
		else:
			n = GroundVehicles.make(k)
			print("TRIS %s %d" % [k, GroundVehicles.triangles(k)])
		n.position = Vector3((i % 4) * 22.0, 0, -(i / 4) * 24.0)
		i += 1
		add_child(n)
		nodes[k] = n
	if "follow_me" in nodes and not old:
		print("TRIS follow_me %d" % (FollowMeShell.triangles(FollowMeCar._shell) + 4 * FollowMeShell.triangles(FollowMeCar._wheel)))
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	await get_tree().create_timer(1.5).timeout
	DirAccess.make_dir_recursive_absolute(out)
	var tag := ("old" if old else "new") + ("_night" if night else "")
	var shots := {}
	for k in KINDS:
		if only != "" and k != only:
			continue
		var p: Vector3 = nodes[k].position
		shots[k] = [p + Vector3(9.0, 3.6, -9.0), p + Vector3(0, 1.3, 0)]
		shots[k + "_rear"] = [p + Vector3(-7.0, 3.2, 9.5), p + Vector3(0, 1.3, 0)]
	if only == "":
		shots["all"] = [Vector3(33, 18, 30), Vector3(33, 0.5, -14)]
	for name in shots:
		cam.fov = 60 if name == "all" else 40
		cam.position = shots[name][0]
		cam.look_at(shots[name][1])
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		if name == "all":
			print("RENDER draw calls %d, primitives %d, frame time %.2f ms (8 vehicles)" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
		get_viewport().get_texture().get_image().save_png("%s/lineup_%s_%s.png" % [out, tag, name])
	get_tree().quit()
