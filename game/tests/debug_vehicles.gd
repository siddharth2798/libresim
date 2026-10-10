extends Node3D
## Debug: line up the vehicle models (front should face the camera's left = -X here? see labels)
func _ready():
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.6, 0.7, 0.8); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color(0.6,0.6,0.6); add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	var names := ["pushback_tug", "fire_truck", "apron_bus", "fuel_truck"]
	for i in names.size():
		var m: Node3D = load("res://world/models/vehicles/%s.glb" % names[i]).instantiate()
		m.position = Vector3(i * 13.0 - 20.0, 0, 0)
		if names[i] == "fuel_truck": m.rotation.y = PI / 2  # own model: front -Z -> show it pointing -X for comparison
		add_child(m)
		var l := Label3D.new(); l.text = names[i]; l.position = m.position + Vector3(0, 6, 0); l.font_size = 96; l.pixel_size = 0.02; add_child(l)
		var arrow := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.3, 0.3, 6); arrow.mesh = bm; arrow.position = m.position + Vector3(-6, 0.2, 3); arrow.rotation.y = PI / 2  # points along -X; add_child(arrow)
	var cam := Camera3D.new(); cam.position = Vector3(0, 6, 30); cam.look_at_from_position(cam.position, Vector3(0, 1.5, 0)); add_child(cam)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-1000/-home-siddharth-Documents-tech-projects-free-sim/f135e359-9884-4ff2-83d4-f05bf2eb11b5/scratchpad/veh.png")
	get_tree().quit()
