class_name JetwayNight
extends RefCounted
## Night look of the jetways: lit tunnel windows, the cab door's lamp and glow, and the apron floodlights' spill on the
## skin (jetway.gdshader on the full model, jetway_standin.gdshader on the far stand-in box, jetway_door_glow.gdshader
## round the cab door). All of it is emission driven by the global night_level (NightSky; the level that switches the apron
## floodlights on), so by day nothing is added, there is no per-frame script work, and it behaves the same on Mobile,
## Forward+ and Compatibility. The maths of the shaders is mirrored here (spill, window) so the tests can check it.

const SHADER := preload("res://world/jetway.gdshader")
const GLOW_SHADER := preload("res://world/jetway_door_glow.gdshader")
const GLOW_TEX := preload("res://world/models/vehicles/jetway_glow.png")
const WARM := Color(1.0, 0.8, 0.52)  # the shaders' warm uniform: sodium / warm LED, as the apron lamps
const WINDOW_TUNNELS := ["Tunnel2", "Tunnel3", "Tunnel4"]  # the sections with a row of windows
const GLOW_NAME := "DoorGlow"
const DOOR_GLOW_M := 4.5  # size of the glow quad at the cab door
const WIN_PITCH := 1.7  # metres between windows along the tunnel (the shaders' WIN_PITCH, WIN_ON)
const WIN_ON := 0.62

static var _mats := {}  # [albedo texture rid, windows] -> ShaderMaterial
static var _glow_mat: ShaderMaterial


## Give the model's meshes the night-capable material (the glb's own material is kept as meta "jw_src" for
## JetwayStandin's colour). Call before the model's parts are moved around.
static func apply(model: Node) -> void:
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0 or mi.material_override != null:
			continue
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
		if src == null or src.albedo_texture == null:
			continue
		mi.set_meta("jw_src", src)
		mi.material_override = material(src, str(mi.name) in WINDOW_TUNNELS)


## One shared material per atlas and window setting (all jetways of a scene share them).
static func material(src: BaseMaterial3D, windows: bool) -> ShaderMaterial:
	var key := [src.albedo_texture.get_rid(), windows]
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("glow_tex", GLOW_TEX)
		m.set_shader_parameter("roughness", src.roughness)
		m.set_shader_parameter("windows", windows)
		_mats[key] = m
	return _mats[key]


## The glow round the cab door: a camera-facing quad at the middle of the hood (which holds the door), added to it.
static func door_glow(hood: Node3D) -> void:
	var mi := hood as MeshInstance3D
	if mi == null:
		return
	if _glow_mat == null:
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = GLOW_SHADER
	var q := MeshInstance3D.new()
	q.name = GLOW_NAME
	q.set_meta("no_solid", true)  # not a body (OpsSolids)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * DOOR_GLOW_M
	q.mesh = quad
	q.material_override = _glow_mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := mi.get_aabb()
	q.position = Vector3(box.end.x + 0.3, box.get_center().y, box.get_center().z)  # just beyond the hood face, at the door
	q.extra_cull_margin = DOOR_GLOW_M
	hood.add_child(q)


## The floodlight spill on a surface whose world normal has height component ny (-1 facing down .. 1 facing up), 0..1
## (jetway.gdshader's spill): the underside catches the light bounced up from the lit apron, the sides some, the roof least.
static func spill(ny: float) -> float:
	var y := clampf(ny, -1.0, 1.0)
	return 0.9 * maxf(-y, 0.0) + 0.45 * (1.0 - absf(y)) + 0.15 * maxf(y, 0.0)


## Lit share (0..1) of a window row at this distance along the tunnel (metres, on the stretched tunnel): windows of
## WIN_ON of each WIN_PITCH, soft at their ends (jetway.gdshader's wx).
static func window_x(metres: float) -> float:
	var f := fposmod(metres / WIN_PITCH, 1.0)
	return smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(WIN_ON - 0.08, WIN_ON, f))


## Emission of a jetway window at this night level: nothing by day, rising with the night (windows are the brightest part).
static func window_emission(night_level: float, metres: float) -> float:
	return clampf(night_level, 0.0, 1.0) * window_x(metres)
