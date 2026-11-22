extends Node
## The cockpit stays rigid to the eye at cruise altitude (CockpitPrecision, CockpitSurface, cockpit_precise.gdshaderinc)
## and its placards are sharp (4096 px legend atlas, anisotropic filtering). Before the fix every cockpit part was drawn
## from ~11 km render-space numbers and jittered by up to ~0.1 deg a frame (tests/debug_overhead_shake.tscn measures it
## in the real game: 2-9 px a frame on the zoomed overhead at FL350 before, 0 px after).

var _built: Array = []


func teardown() -> void:
	for n in _built:
		if is_instance_valid(n):
			n.free()
	_built.clear()


func _model(id: String) -> AircraftModel:
	var was: String = Session.setup.aircraft
	Session.setup.aircraft = id  # the cockpit reads the panel of the current aircraft
	var n := FdmNode.new()
	n.fdm = FDM.new(AircraftDef.load_def(id))
	var m := AircraftModel.new()
	add_child(m)
	m.build(n)
	Session.setup.aircraft = was
	_built.append_array([m, n])
	return m


func _precision(m: AircraftModel) -> CockpitPrecision:
	var p := m.cockpit.find_children("*", "CockpitPrecision", true, false)[0] as CockpitPrecision
	p.scan()  # normally deferred to the end of the build frame
	return p


static func _precise(mat: Material) -> bool:
	return mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
			and ((mat as ShaderMaterial).shader.code.contains("CKPT_PRECISE_MODELVIEW") \
			or (mat as ShaderMaterial).shader.code.contains("cockpit_surface.gdshaderinc"))


## Every visible surface of every cockpit mesh draws camera-relative and knows its aircraft-local origin.
func _all_precise(m: AircraftModel) -> String:
	_precision(m)
	var meshes := m.cockpit.find_children("*", "MeshInstance3D", true, false)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			if not _precise(mi.get_active_material(i)):
				return "%s surface %d (%s) is drawn from render-space numbers" % [mi.name, i, mi.get_active_material(i)]
		var o = mi.get_instance_shader_parameter("ckpt_origin")
		if not o is Vector4 or (o as Vector4).w != 1.0:
			return "%s has no aircraft-local origin" % mi.name
	return "" if meshes.size() > 20 else "only %d cockpit meshes" % meshes.size()


func test_every_a320_cockpit_surface_is_camera_relative() -> String:
	return _all_precise(_model("a320"))


func test_every_c172_cockpit_surface_is_camera_relative() -> String:
	return _all_precise(_model("c172"))


## N ticks of turbulent cruise at FL350 (render y 10.7 km): the overhead's eye-frame position the shader draws comes
## from aircraft-local numbers only, so it is the same as with the aircraft at the render origin; the engine's
## float32 world path that drew it before is off by up to a millimetre.
func test_overhead_rigid_to_the_eye_in_turbulent_cruise() -> String:
	var m := _model("a320")
	_precision(m)
	var sw := m.cockpit.interior.find_child("pivot_beacon_lt", true, false) as Node3D
	var mi := sw.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var got = mi.get_instance_shader_parameter("ckpt_origin")
	if not got is Vector4 or (got as Vector4).w != 1.0:
		return "the overhead switch has no aircraft-local origin: it is drawn from render-space numbers"
	var o4: Vector4 = got
	var origin := Vector3(o4.x, o4.y, o4.z)
	var chain := Transform3D.IDENTITY
	var p: Node = mi
	while p != m:
		chain = (p as Node3D).transform * chain
		p = p.get_parent()
	if origin.distance_to(chain.origin) > 1e-6:
		return "ckpt_origin %s is not the mesh's aircraft-local origin %s" % [origin, chain.origin]
	var cp := m.cockpit.find_children("*", "CockpitPrecision", true, false)[0] as CockpitPrecision
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seat := Vector2.ZERO
	var look := CameraLook.aim_at(m.cockpit.eye.direction_to(origin))
	var worst_old := 0.0
	for tick in 240:
		var t := tick / 120.0
		seat = CameraMotion.seat_step(seat.x, seat.y, 1.0 + rng.randf_range(-0.4, 0.4), 1.0 / 120.0)  # turbulent g
		var local := CameraMotion.cockpit_eye(m.cockpit.eye, look, seat.x, 70.0)
		var att := Basis.from_euler(Vector3(0.03 * sin(t * 9.0) + rng.randf_range(-0.01, 0.01), 4.71 + 0.02 * sin(t * 5.0),
			0.05 * sin(t * 7.0)))
		m.transform = Transform3D(att, Vector3(-4321.37 + 230.0 * t, 10678.4 + rng.randf_range(-1.0, 1.0), 2468.13))
		cp._process(1.0 / 120.0)
		var now: Vector4 = mi.get_instance_shader_parameter("ckpt_origin")
		if now != o4:
			return "tick %d: the overhead's origin changed in flight (%s -> %s)" % [tick, o4, now]
		var drawn := local.affine_inverse() * Vector3(now.x, now.y, now.z)  # CKPT_PRECISE_MODELVIEW: ckpt_view * ckpt_origin
		var exact := local.affine_inverse() * chain.origin  # aircraft frame only: independent of where the aircraft is
		if drawn != exact:
			return "tick %d: the overhead moved against the eye by %.6f m" % [tick, drawn.distance_to(exact)]
		var old := (m.global_transform * local).affine_inverse() * mi.global_transform.origin  # the engine's render-space path
		worst_old = maxf(worst_old, old.distance_to(exact))
	if worst_old < 1e-4:
		return "the float32 world path should be off by > 0.1 mm at 10.7 km (got %.5f m): the test lost its point" % worst_old
	return ""


## A lever that moves (pushbutton, switch) refreshes the origin of the meshes it carries in the same frame.
func test_a_moved_lever_refreshes_its_origin() -> String:
	var m := _model("a320")
	var cp := _precision(m)
	var pv := m.cockpit.interior.find_child("pivot_bat1", true, false) as Node3D
	var mi := pv.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var got = mi.get_instance_shader_parameter("ckpt_origin")
	if not got is Vector4 or (got as Vector4).w != 1.0:
		return "the BAT 1 button has no aircraft-local origin"
	var before: Vector4 = got
	pv.position += Vector3(0.0, 0.0, 0.01)
	cp._process(0.0)
	var after: Vector4 = mi.get_instance_shader_parameter("ckpt_origin")
	var moved := Vector3(after.x - before.x, after.y - before.y, after.z - before.z).length()
	return "" if absf(moved - 0.01) < 1e-4 else "the lamp's origin moved %.4f m with a 0.01 m press" % moved


## The converted material draws what the StandardMaterial3D did, follows CockpitLighting's changes, and is left
## alone when it uses a feature the cockpit shader does not draw.
func test_surface_conversion_keeps_the_material() -> String:
	var std := StandardMaterial3D.new()
	std.resource_name = "panel"
	std.albedo_color = Color(0.5, 0.6, 0.7)
	std.roughness = 0.42
	std.metallic = 0.2
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	var s := CockpitSurface.make(std)
	if s == null or s.shader != CockpitSurface.LIT:
		return "a plain lit panel should become cockpit_lit"
	if not is_equal_approx(float(s.get_shader_parameter("roughness")), 0.42) or s.get_shader_parameter("albedo") != std.albedo_color:
		return "parameters not copied"
	std.emission_enabled = true
	std.emission_energy_multiplier = 0.3
	CockpitSurface.sync(std, s)
	if not is_equal_approx(float(s.get_shader_parameter("emission_energy")), 0.3):
		return "legend emission not followed"
	std.emission_enabled = false
	CockpitSurface.sync(std, s)
	if float(s.get_shader_parameter("emission_energy")) != 0.0:
		return "emission off should draw no emission"
	var quad := StandardMaterial3D.new()
	quad.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if CockpitSurface.shader_for(quad) != CockpitSurface.UNSHADED_ALPHA:
		return "an unshaded overlay quad should become cockpit_unshaded_alpha"
	var bumpy := std.duplicate() as StandardMaterial3D
	bumpy.normal_enabled = true
	return "" if CockpitSurface.make(bumpy) == null else "a normal-mapped material must be left as it is"


## Other code's cockpit shaders get the camera-relative line in a copy of their shader; the material object stays.
func test_shader_patch_adds_the_line_and_keeps_the_material() -> String:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nuniform float lit = 0.0;\nvoid fragment() {\n\tALBEDO = vec3(lit);\n}\n"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("lit", 1.0)
	if not CockpitSurface.patch(sm) or not sm.shader.code.contains("CKPT_PRECISE_MODELVIEW") or sm.shader == sh:
		return "a fragment-only shader should get a vertex() with the line"
	if float(sm.get_shader_parameter("lit")) != 1.0:
		return "the owner's parameters must survive"
	var own := Shader.new()
	own.code = "shader_type spatial;\nrender_mode skip_vertex_transform;\nvoid vertex() {\n\tVERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;\n}\n"
	var om := ShaderMaterial.new()
	om.shader = own
	return "" if not CockpitSurface.patch(om) and om.shader == own else "a shader with its own vertex transform must be left alone"


## Placard text: the legend overlay is 4096 px (VRAM-compressed, mipmapped) on every preset but Low, and every
## cockpit sampler filters anisotropically (the overhead is seen at a grazing angle).
func test_placard_text_is_sharp() -> String:
	var def := AircraftDef.load_def("a320")
	var rel := str(def.section("cockpit").get("detail_textures", {}).get("a320_fd_glare", ""))
	var path := def.dir + "/" + rel
	if rel == "" or not ResourceLoader.exists(path):
		return "no 4096 px legend atlas in cockpit.detail_textures"
	var imp := FileAccess.get_file_as_string(path + ".import")
	if not imp.contains("compress/mode=2") or not imp.contains("mipmaps/generate=true"):
		return "the legend atlas must be VRAM-compressed with mipmaps"
	var code := FileAccess.get_file_as_string("res://aircraft/common/cockpit_surface.gdshaderinc")
	if code.contains("filter_linear_mipmap,") or not code.contains("texture_albedo : source_color, filter_linear_mipmap_anisotropic"):
		return "cockpit samplers must filter anisotropically"
	var was: String = Graphics.preset
	Graphics.preset = "medium"
	var m := _model("a320")
	var cp := _precision(m)
	Graphics.preset = "low"
	var low := CockpitPrecision._detail(def)
	Graphics.preset = was
	var size := Vector2.ZERO
	for row in cp._mats:
		if str(row[0].resource_name) == "a320_fd_glare":
			size = ((row[1] as ShaderMaterial).get_shader_parameter("texture_albedo") as Texture2D).get_size()
	if size.x < 4096.0:
		return "medium draws the legends from a %s atlas, want 4096" % size
	return "" if low.is_empty() else "the low preset must keep the 2048 px atlas (GPU memory)"


## Zoomed in, the seat dip shrinks with the field of view; at the normal 70 deg it is whole.
func test_seat_dip_follows_zoom() -> String:
	var eye := Vector3(0.0, 1.0, 0.0)
	var full := CameraMotion.cockpit_eye(eye, Vector2.ZERO, 0.01, 70.0).origin.y - 1.0
	var zoom := CameraMotion.cockpit_eye(eye, Vector2.ZERO, 0.01, 15.0).origin.y - 1.0
	if not is_equal_approx(full, 0.01):
		return "the dip at 70 deg should be whole, got %.4f" % full
	return "" if absf(zoom - 0.01 * 15.0 / 70.0) < 1e-6 else "the dip at 15 deg should be 15/70 of it, got %.4f" % zoom
