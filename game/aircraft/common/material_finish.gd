class_name MaterialFinish
extends Node
## A320 roughness, metal, clearcoat, AO and panel normals. wheel_mat is shared with the C172.

const PANE := preload("res://aircraft/common/glass.gdshader")
const RAIN := preload("res://aircraft/common/windshield_rain.gdshader")
const WEATHER := preload("res://aircraft/common/weathering.gdshader")
const CABIN_COLOR := Color(1.0, 0.68, 0.40)
const CABIN_GLOW_MAX := 0.45
const PARKED_DIM := 0.35
const AO_AFFECT := 0.15
const _MODEL := "res://aircraft/a320/models/"

static var _weather: ShaderMaterial

static func table(aircraft_id: String) -> Dictionary:
	if aircraft_id != "a320":
		return {}
	return {
		"a320_fuselage": {"roughness": 0.48, "metallic": 0.0, "clearcoat": 0.22, "clearcoat_roughness": 0.4},
		"a320_engine": {"roughness": 0.36, "metallic": 0.02, "clearcoat": 0.16, "clearcoat_roughness": 0.45},
		"a320_inlet": {"roughness": 0.14, "metallic": 1.0},
		"a320_spinner": {"roughness": 0.3, "metallic": 0.8},
		"a320_gear": {"roughness": 0.55, "metallic": 0.05},
		"wheel_mat": {"roughness": 0.9, "metallic": 0.0},
		"a320_glass": {"roughness": 0.08, "metallic": 0.05},
		"a320_fd_leather": {"roughness": 0.65, "metallic": 0.0},
		"a320_fd_glare": {"roughness": 0.7, "metallic": 0.0},
	}

static func legend_names() -> Array:
	return ["a320_fd_buttons", "a320_fcu", "a320_radio"]

static func cabin_glow(sun_elev_deg: float, on_ground: bool, engines_on: bool) -> float:
	var night := LightLogic.night_factor(sun_elev_deg)
	if night <= 0.0:
		return 0.0
	if on_ground and not engines_on:
		return night * PARKED_DIM
	return night

static func legend_energy(night: float, dim: float, powered: bool) -> float:
	if night <= 0.0 or not powered:
		return 0.0
	return night * (0.10 + 0.22 * clampf(dim, 0.0, 1.0))

static func _chart(exterior: bool) -> Dictionary:
	if not exterior:
		return {"ao": _MODEL + "interior_ao.png", "stem": "interior"}
	return {
		"a320_fuselage": {"ao": _MODEL + "exterior_ao.png", "normal": _MODEL + "exterior_panels.png", "scale": 0.65, "stem": "exterior_panels"},
		"a320_engine": {"ao": _MODEL + "exterior_ao.png", "normal": _MODEL + "exterior_engine_panels.png", "scale": 0.55, "stem": "exterior_engine_panels"},
		"a320_gear": {"ao": _MODEL + "exterior_ao.png", "stem": "exterior_gear"},
		"a320_plain_333": {"ao": _MODEL + "exterior_ao.png"},
	}

static func bind_maps(mat: BaseMaterial3D, tex: Texture2D = null, exterior: bool = true) -> void:
	if mat == null or mat.resource_name == "wheel_mat":
		return
	var spec: Dictionary = {}
	if exterior:
		spec = _chart(true).get(mat.resource_name, {})
		if spec.is_empty():
			return
	elif mat.resource_name == "" or mat.resource_name == "a320_glass" or mat.resource_name == "a320_screen":
		return
	else:
		spec = _chart(false)
	var ao: Texture2D = tex if tex != null else _load_tex(str(spec.get("ao", "")))
	if ao != null:
		mat.ao_texture = ao
		mat.ao_enabled = true
		mat.ao_light_affect = AO_AFFECT
	_bind_scalar_maps(mat, str(spec.get("stem", "")))
	if not spec.has("scale"):
		return
	var nrm: Texture2D = tex if tex != null else _load_tex(str(spec.get("normal", "")))
	if nrm == null:
		return
	mat.normal_enabled = true
	mat.normal_texture = nrm
	mat.normal_scale = float(spec.scale)

static func _bind_scalar_maps(mat: BaseMaterial3D, stem: String) -> void:
	if stem == "":
		return
	var rough := _load_tex(_MODEL + stem + "_roughness.png")
	var met := _load_tex(_MODEL + stem + "_metal.png")
	if rough != null:
		mat.roughness_texture = rough
	if met != null:
		mat.metallic_texture = met

static func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

static func restamp(mat: BaseMaterial3D) -> void:
	if mat == null or mat.resource_name == "wheel_mat":
		return
	var spec: Dictionary = table("a320").get(mat.resource_name, {})
	if not spec.is_empty():
		_write(mat, spec)
	bind_maps(mat)

static func _wants(name: String, spec: Dictionary, exterior: bool) -> bool:
	if name == "":
		return false
	if spec.has(name) or (exterior and _chart(true).has(name)):
		return true
	return not exterior and name != "a320_glass" and name != "a320_screen" and name != "wheel_mat"

static func stamp_surfaces(root: Node, aircraft_id: String, exterior: bool) -> void:
	var spec := table(aircraft_id)
	if spec.is_empty() or root == null:
		return
	var made := {}
	var pane: ShaderMaterial
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mesh_mat := mesh.surface_get_material(i)
			var src_name := mesh_mat.resource_name if mesh_mat != null else ""
			if exterior and str(mi.name).begins_with("FanLCFM56"):
				if not made.has("a320_fan"):
					made["a320_fan"] = _fan_blade(mi as MeshInstance3D, i)
				(mi as MeshInstance3D).set_surface_override_material(i, made["a320_fan"])
				continue
			if not _wants(src_name, spec, exterior):
				continue
			var inst := mi as MeshInstance3D
			if src_name == "a320_glass" and not exterior:
				if pane == null:
					pane = _pane(spec[src_name])
				inst.set_surface_override_material(i, pane)
				continue
			if made.has(src_name):
				inst.set_surface_override_material(i, made[src_name])
				continue
			var active := inst.get_active_material(i)
			var base: BaseMaterial3D = null
			if active is BaseMaterial3D:
				base = active
			elif mesh_mat is BaseMaterial3D:
				base = mesh_mat
			if base == null:
				continue
			var d := base.duplicate() as BaseMaterial3D
			d.resource_name = src_name
			if spec.has(src_name):
				_write(d, spec[src_name])
			bind_maps(d, null, exterior)
			if exterior and src_name == "a320_fuselage":
				d.next_pass = _weather_mat()
			elif exterior and src_name == "a320_glass":
				_cabin_glass(d)
			made[src_name] = d
			inst.set_surface_override_material(i, d)

static func _fan_blade(mi: MeshInstance3D, i: int) -> BaseMaterial3D:
	var active := mi.get_active_material(i)
	var base := active as BaseMaterial3D
	if base == null and mi.mesh != null:
		base = mi.mesh.surface_get_material(i) as BaseMaterial3D
	if base == null:
		base = StandardMaterial3D.new()
	var d := base.duplicate() as BaseMaterial3D
	d.resource_name = "a320_fan"
	_write(d, {"roughness": 0.4, "metallic": 0.72})
	d.normal_enabled = false
	d.albedo_color = Color(0.42, 0.43, 0.45)
	return d

static func _write(mat: BaseMaterial3D, spec: Dictionary) -> void:
	mat.roughness = float(spec.roughness)
	mat.metallic = float(spec.metallic)
	if spec.has("clearcoat"):
		mat.clearcoat_enabled = true
		mat.clearcoat = float(spec.clearcoat)
		mat.clearcoat_roughness = float(spec.clearcoat_roughness)

static func _pane(spec: Dictionary) -> ShaderMaterial:
	var sh := ShaderMaterial.new()
	sh.shader = PANE
	sh.set_shader_parameter("pane_roughness", float(spec.roughness))
	sh.set_shader_parameter("pane_metallic", float(spec.metallic))
	return sh

static func _cabin_glass(mat: BaseMaterial3D) -> void:
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission = CABIN_COLOR
	mat.emission_enabled = false
	mat.emission_energy_multiplier = 0.0
	if mat.next_pass == null:
		var drops := ShaderMaterial.new()
		drops.shader = RAIN
		mat.next_pass = drops

static func _weather_mat() -> ShaderMaterial:
	if _weather == null:
		_weather = ShaderMaterial.new()
		_weather.shader = WEATHER
		_weather.set_shader_parameter("amount", 0.0)
	return _weather

static func _glow_now() -> float:
	var on := false
	var n := clampi(int(Props.get_f("engine/count", 2.0)), 1, 8)
	for i in n:
		on = on or Props.get_b("engines/%d/running" % (i + 1))
	return cabin_glow(LightLogic.sun_elev_now(), Props.get_b("fdm/wow", true), on)

func follow(glb: Node, cg: Vector3, def: AircraftDef) -> void:
	_glb = glb
	_cg = cg
	_model = get_parent() as Node3D
	if _weather != null:
		_bind_exhaust(def)
		_weather.set_shader_parameter("cg", cg)
		_weather.set_shader_parameter("amount", 1.0)
		_push_frame()
	_paint_glass(_glow_now() * CABIN_GLOW_MAX)

func _process(_dt: float) -> void:
	var e := _glow_now() * CABIN_GLOW_MAX
	if not is_equal_approx(e, _glow):
		_glow = e
		_paint_glass(e)
	if _weather != null and _model != null:
		_push_frame()

func _exit_tree() -> void:
	if _weather != null:
		_weather.set_shader_parameter("amount", 0.0)

func _push_frame() -> void:
	if _model == null or _weather == null:
		return
	_weather.set_shader_parameter("aircraft_inv", _model.global_transform.affine_inverse())

func _bind_exhaust(def: AircraftDef) -> void:
	var n := 0
	for e in def.section("exhausts").get("list", []):
		if n >= 4 or not (e is Dictionary):
			continue
		var p: Array = e.get("pos", [])
		if p.size() < 3:
			continue
		var raw: Array = e.get("dir", [1.0, 0.0, 0.0])
		var dir := Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw.size() >= 3 else Vector3(1, 0, 0)
		if dir.length_squared() < 1e-8:
			dir = Vector3(1, 0, 0)
		_weather.set_shader_parameter("nozzle%d" % n, Vector3(float(p[0]), float(p[1]), float(p[2])))
		_weather.set_shader_parameter("dir%d" % n, dir)
		n += 1
	_weather.set_shader_parameter("nozzle_count", float(n))

func _paint_glass(energy: float) -> void:
	if _glb == null:
		return
	for mi in _glb.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var mesh_mat := mesh.surface_get_material(i)
			if mesh_mat == null or mesh_mat.resource_name != "a320_glass":
				continue
			var live := (mi as MeshInstance3D).get_active_material(i) as StandardMaterial3D
			if live == null:
				continue
			live.emission = CABIN_COLOR
			live.emission_enabled = energy > 0.001
			live.emission_energy_multiplier = energy

var _glb: Node
var _model: Node3D
var _cg := Vector3.ZERO
var _glow := -1.0
