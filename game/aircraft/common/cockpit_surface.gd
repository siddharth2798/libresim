class_name CockpitSurface
extends RefCounted
## Turns a cockpit StandardMaterial3D into the matching cockpit shader (cockpit_surface.gdshaderinc: camera-relative in
## the cockpit view, anisotropic filtering). The cockpit glbs use only plain features (albedo, roughness, metallic,
## specular, AO, additive emission, alpha with a depth pre-pass, unshaded quads); a material with anything else is left
## as it is (make() returns null). sync() copies what CockpitLighting changes at run time (gauge dimming, legend and
## lamp emission), so the StandardMaterial3D stays the one other code writes to. patch() gives a cockpit ShaderMaterial
## of other code (glass, FCU bars) a copy of its shader with the camera-relative line (cockpit_precise.gdshaderinc).

const LIT := preload("res://aircraft/common/cockpit_lit.gdshader")
const ALPHA := preload("res://aircraft/common/cockpit_alpha.gdshader")
const UNSHADED := preload("res://aircraft/common/cockpit_unshaded.gdshader")
const UNSHADED_ALPHA := preload("res://aircraft/common/cockpit_unshaded_alpha.gdshader")
const PRECISE_INC := "#include \"res://aircraft/common/cockpit_precise.gdshaderinc\"\n"
const PRECISE_LINE := "\tCKPT_PRECISE_MODELVIEW\n"
static var _patched := {}  # Shader -> patched copy, or null when it cannot take the line
const _CHANNEL := [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1),
	Vector4(0.333333, 0.333333, 0.333333, 0)]  # BaseMaterial3D.TextureChannel


## The cockpit shader variant drawing `m` exactly, or null when `m` uses a feature it does not draw.
static func shader_for(m: BaseMaterial3D) -> Shader:
	if m == null or m.next_pass != null or m.normal_enabled or m.rim_enabled or m.clearcoat_enabled or m.anisotropy_enabled \
			or m.heightmap_enabled or m.subsurf_scatter_enabled or m.backlight_enabled or m.refraction_enabled \
			or m.detail_enabled or m.uv1_triplanar or m.uv2_triplanar or m.vertex_color_use_as_albedo \
			or m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or m.use_point_size or m.grow or m.fixed_size \
			or m.no_depth_test or m.disable_receive_shadows or m.proximity_fade_enabled or m.ao_on_uv2 \
			or m.emission_on_uv2 or m.emission_operator != BaseMaterial3D.EMISSION_OP_ADD or not m.texture_repeat \
			or m.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED or m.blend_mode != BaseMaterial3D.BLEND_MODE_MIX \
			or m.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY or m.alpha_antialiasing_mode != BaseMaterial3D.ALPHA_ANTIALIASING_OFF:
		return null
	if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		if m.cull_mode != BaseMaterial3D.CULL_BACK:
			return null
		match m.transparency:
			BaseMaterial3D.TRANSPARENCY_DISABLED:
				return UNSHADED
			BaseMaterial3D.TRANSPARENCY_ALPHA:
				return UNSHADED_ALPHA
		return null
	if m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or m.cull_mode != BaseMaterial3D.CULL_DISABLED \
			or m.diffuse_mode != BaseMaterial3D.DIFFUSE_BURLEY or m.specular_mode != BaseMaterial3D.SPECULAR_SCHLICK_GGX:
		return null
	match m.transparency:
		BaseMaterial3D.TRANSPARENCY_DISABLED:
			return LIT
		BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
			return ALPHA
	return null


## A cockpit ShaderMaterial that draws like `m`, or null (see shader_for). `albedo_tex` replaces m's albedo texture
## (a higher-resolution copy of the same atlas, cockpit.detail_textures).
static func make(m: BaseMaterial3D, albedo_tex: Texture2D = null) -> ShaderMaterial:
	var sh := shader_for(m)
	if sh == null:
		return null
	var s := ShaderMaterial.new()
	s.shader = sh
	s.resource_name = m.resource_name
	s.render_priority = m.render_priority
	s.set_shader_parameter("texture_albedo", albedo_tex if albedo_tex != null else m.albedo_texture)
	s.set_shader_parameter("uv1_scale", m.uv1_scale)
	s.set_shader_parameter("uv1_offset", m.uv1_offset)
	if _lit(sh):
		s.set_shader_parameter("roughness", m.roughness)
		s.set_shader_parameter("texture_roughness", m.roughness_texture)
		s.set_shader_parameter("roughness_texture_channel", _CHANNEL[m.roughness_texture_channel])
		s.set_shader_parameter("metallic", m.metallic)
		s.set_shader_parameter("texture_metallic", m.metallic_texture)
		s.set_shader_parameter("metallic_texture_channel", _CHANNEL[m.metallic_texture_channel])
		s.set_shader_parameter("specular", m.metallic_specular)
		var ao := m.ao_enabled and m.ao_texture != null
		s.set_shader_parameter("texture_ambient_occlusion", m.ao_texture if ao else null)
		s.set_shader_parameter("ao_texture_channel", _CHANNEL[m.ao_texture_channel] if ao else _CHANNEL[0])
		s.set_shader_parameter("ao_light_affect", m.ao_light_affect if ao else 0.0)
	sync(m, s)
	return s


## What CockpitLighting changes at run time, as a value to compare between frames.
static func key(m: BaseMaterial3D) -> Array:
	return [m.albedo_color, m.emission_enabled, m.emission_energy_multiplier, m.emission, m.emission_texture]


## Copy the run-time state (key) of `m` into its cockpit material `s`.
static func sync(m: BaseMaterial3D, s: ShaderMaterial) -> void:
	s.set_shader_parameter("albedo", m.albedo_color)
	if not _lit(s.shader):
		return
	s.set_shader_parameter("emission", m.emission)
	s.set_shader_parameter("texture_emission", m.emission_texture if m.emission_enabled else null)
	s.set_shader_parameter("emission_energy", m.emission_energy_multiplier if m.emission_enabled else 0.0)


static func _lit(sh: Shader) -> bool:
	return sh == LIT or sh == ALPHA


## Gives `sm` a copy of its shader with CKPT_PRECISE_MODELVIEW first in vertex() (the material object stays the same,
## so its owner keeps setting its parameters). False when the shader cannot take it (canvas or sky shader, its own
## vertex transform, or a vertex() that may sit in an #include); the material is then left alone.
static func patch(sm: ShaderMaterial) -> bool:
	var sh := sm.shader
	if sh == null:
		return false
	if sh.code.contains("CKPT_PRECISE_MODELVIEW") or sh.code.contains("cockpit_surface.gdshaderinc"):
		return true
	if not _patched.has(sh):
		_patched[sh] = _patch_code(sh)
	if _patched[sh] == null:
		return false
	sm.shader = _patched[sh]
	return true


static func _patch_code(sh: Shader) -> Shader:
	var code := sh.code
	if sh.get_mode() != Shader.MODE_SPATIAL:
		return null
	for bad in ["skip_vertex_transform", "world_vertex_coords", "POSITION", "MODELVIEW_MATRIX"]:
		if code.contains(bad):
			return null
	var m := RegEx.create_from_string("void\\s+vertex\\s*\\(\\s*\\)\\s*\\{").search(code)
	if m != null:
		code = code.substr(0, m.get_start()) + PRECISE_INC + m.get_string() + "\n" + PRECISE_LINE + code.substr(m.get_end())
	elif code.contains("#include"):
		return null
	else:
		code += "\n" + PRECISE_INC + "void vertex() {\n" + PRECISE_LINE + "}\n"
	var out := Shader.new()
	out.code = code
	return out
