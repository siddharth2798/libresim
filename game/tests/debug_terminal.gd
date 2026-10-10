extends Node3D
## Debug: standalone render of a landmark terminal model (works for airports outside
## the mapped terrain, e.g. Kochi). Saves <out>/term_<ICAO>_<view>.png and quits.
## godot --path game res://tests/debug_terminal.tscn -- --icao=VABB --out=<dir> [--night]

var _icao := "VABB"
var _out := "/tmp"
var _night := false
var _cam := Camera3D.new()
var _meta := {}
var _shots: Array = []
var _i := 0
var _t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"icao": _icao = kv[1].to_upper()
			"out": _out = kv[1]
			"night": _night = true
	var dir := Paths.data("terminals")
	_meta = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(_icao + "_model.json")))
	var o: Array = _meta.origin
	FloatingOrigin.set_origin(Vector2(o[0], o[1]))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.sky = sky
	env.environment.background_mode = Environment.BG_SKY
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment.ambient_light_energy = 0.15 if _night else 1.0
	env.environment.background_energy_multiplier = 0.05 if _night else 1.0
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.shadow_enabled = true
	sun.light_energy = 0.0 if _night else 1.2
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.34, 0.33)
	ground.material_override = gm
	ground.position.y = float(o[2]) - 0.05
	add_child(ground)
	var t := Terminals.new()
	add_child(t)
	add_child(_cam)
	_cam.far = 20000.0
	for f in _meta.get("focus", []):  # per landmark: two obliques and an apron-level view
		var at := Vector3(f[0], 0.0, -f[1])
		var r := maxf(float(f[2]), 120.0)
		for k in 2:
			var a := deg_to_rad(35.0 + 180.0 * k)
			_shots.append([at, at + Vector3(sin(a), 0.0, cos(a)) * r * 0.75 + Vector3(0, r * 0.35, 0), "f%d_obl%d" % [_shots.size() / 3, k]])
		_shots.append([at, at + Vector3(sin(2.2), 0.0, cos(2.2)) * r * 0.6 + Vector3(0, 6.0, 0), "f%d_ground" % [_shots.size() / 3]])
	Props.set_v("environment/sun_elev_deg", -10.0 if _night else 40.0)


func _process(dt: float) -> void:
	_t += dt
	if _t < 2.0 + _i * 0.5:
		return
	if _i >= _shots.size():
		get_tree().quit()
		return
	var h := float(_meta.origin[2])
	_cam.position = _shots[_i][1] + Vector3(0, h, 0)
	_cam.look_at(_shots[_i][0] + Vector3(0, h + 12.0, 0))
	if _t > 2.3 + _i * 0.5:
		get_viewport().get_texture().get_image().save_png(_out.path_join("term_%s_%s%s.png" % [_icao, _shots[_i][2], "_night" if _night else ""]))
		_i += 1
