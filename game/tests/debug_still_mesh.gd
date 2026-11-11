extends Node3D
## Debug: the smallest scene that can show frame-to-frame flicker (docs/FLICKER-PLAN.md phase 2): a sky, one sun,
## one glb with its own StandardMaterials and a camera that never moves. No project shaders, autoload effects or
## post passes. Saves N consecutive frames; tools/flicker_metric.py tells whether anything changed between them.
##   godot --path game --resolution 800x450 [--rendering-method mobile] res://tests/debug_still_mesh.tscn \
##     --audio-driver Dummy -- --out=<dir> [--glb=res://world/models/vehicles/jetway.glb] [--frames=12] [--unshaded]
##     [--nosun] [--msaa=0|2|4] [--fxaa=0|1]
## A still camera must give identical frames: any change is renderer instability, independent of this project.

var _out := ""
var _glb := "res://world/models/vehicles/jetway.glb"
var _frames := 12
var _unshaded := false
var _nosun := false
var _msaa := 0
var _fxaa := 1
var _t := 0.0
var _n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": _out = kv[1]
			"glb": _glb = kv[1]
			"frames": _frames = int(kv[1])
			"unshaded": _unshaded = true
			"nosun": _nosun = true
			"msaa": _msaa = int(kv[1])
			"fxaa": _fxaa = int(kv[1])
	DirAccess.make_dir_recursive_absolute(_out)
	var vp := get_viewport()
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}.get(_msaa, Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _fxaa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = 1.0
	vp.use_taa = false
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if not _nosun:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
		sun.shadow_enabled = false
		add_child(sun)
	var model: Node3D = (load(_glb) as PackedScene).instantiate()
	add_child(model)
	if _unshaded:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 0.35, 0.4)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = m
	var ground := MeshInstance3D.new()  # a flat plane under it, like an apron
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.55, 0.56)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 160000.0
	cam.fov = 60.0
	add_child(cam)
	cam.look_at_from_position(Vector3(30.0, 6.0, 22.0), Vector3(10.0, 4.0, 0.0))
	cam.current = true


func _process(dt: float) -> void:
	_t += dt
	if _t < 3.0:
		return
	get_viewport().get_texture().get_image().save_png(_out.path_join("burst_%02d.png" % _n))
	_n += 1
	if _n >= _frames:
		print("STILL DONE %s" % RenderingServer.get_current_rendering_method())
		get_tree().quit()
