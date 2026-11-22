extends Node3D
## Debug: does the GPU add float32 jitter between a camera and a mesh that share the exact same global transform?
## A checker quad 0.6 m ahead of the camera, both moving like a cruising airliner at --alt metres. Saves frames.
##   godot --path game --audio-driver Dummy res://tests/debug_gpu_precision.tscn -- --alt=10678 --shots=<abs dir> [--share=0]
## --share=0 gives the quad its own world transform (camera * offset, rounded on the CPU like a cockpit node).
## --fix draws it with cockpit_unshaded.gdshader (camera-relative, CockpitPrecision's globals set here by hand).
## Finding (2026-11-22): at --alt=10678 even identical camera and quad transforms jitter 2-4 px at fov 15 (the GPU's
## float32 VIEW * MODEL); --fix holds it still.
var cam := Camera3D.new()
var quad := MeshInstance3D.new()
var _alt := 10678.0
var _shots := ""
var _share := true
var _fix := false
var _n := 0
var _lq := Transform3D(Basis.from_euler(Vector3(0.2, 0.1, 0.0)), Vector3(0.05, 0.3, -0.55))  # quad in the "aircraft" frame
var _lc := Transform3D(Basis.from_euler(Vector3(0.5, 0.0, 0.0)), Vector3(0.0, 0.1, 0.0))  # camera in the "aircraft" frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--alt="):
			_alt = float(a.substr(6))
		elif a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a == "--share=0":
			_share = false
		elif a == "--fix":
			_fix = true
	DirAccess.make_dir_recursive_absolute(_shots)
	cam.fov = 15.0
	cam.near = 0.05
	add_child(cam)
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.09)
	q.center_offset = Vector3(0, 0, -0.6) if _share and not _fix else Vector3.ZERO
	var img := Image.create(256, 144, false, Image.FORMAT_RGB8)
	for y in 144:
		for x in 256:
			img.set_pixel(x, y, Color.WHITE if ((x / 16 + y / 16) % 2) == 0 else Color.BLACK)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = ImageTexture.create_from_image(img)
	q.material = m
	if _fix:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://aircraft/common/cockpit_unshaded.gdshader")
		sm.set_shader_parameter("texture_albedo", m.albedo_texture)
		RenderingServer.global_shader_parameter_set("ckpt_on", 1.0)
		q.material = sm
	quad.mesh = q
	add_child(quad)


func _process(_dt: float) -> void:
	var t := _n / 60.0
	var pos := Vector3(1234.5678 + t * 230.0, _alt + sin(t * 3.0) * 2.0, -2345.678 + t * 17.0)
	var b := Basis.from_euler(Vector3(0.6 + 0.01 * sin(t * 7.0), 0.3 + 0.01 * cos(t * 5.0), 0.02 * sin(t * 4.0)))
	var a := Transform3D(b, pos)
	if _fix or not _share:
		cam.global_transform = a * _lc
		quad.global_transform = a * _lq * Transform3D(Basis(), Vector3(0, 0, 0))
		if _fix:
			quad.set_instance_shader_parameter("ckpt_origin", Vector4(_lq.origin.x, _lq.origin.y, _lq.origin.z, 1.0))
			RenderingServer.global_shader_parameter_set("ckpt_view", Projection(_lc.affine_inverse()))
			RenderingServer.global_shader_parameter_set("ckpt_cam", cam.global_transform.origin)
	else:
		cam.global_transform = a
		quad.global_transform = a
	_n += 1
	if _n > 30 and _n <= 30 + 60:
		get_viewport().get_texture().get_image().save_png(_shots.path_join("f%03d.png" % _n))
	if _n > 95:
		get_tree().quit()
