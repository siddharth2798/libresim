class_name MaterialFinish
extends Node
## A320 shading on the materials the glbs already have. Roughness, metal, clearcoat, baked AO and
## panel normals go on the StandardMaterial3D. The livery pass only replaces albedo
## (PaintPipeline.override duplicates the material, then restamp() writes the numbers and the maps
## again). Names that are not in table() keep their roughness. wheel_mat is shared with the C172:
## restamp() does not touch it.

const PANE := preload("res://aircraft/common/glass.gdshader")
const RAIN := preload("res://aircraft/common/windshield_rain.gdshader")
const WEATHER := preload("res://aircraft/common/weathering.gdshader")
const CABIN_COLOR := Color(1.0, 0.68, 0.40)
const CABIN_GLOW_MAX := 0.45  # emission energy at full night, airborne or engines running
const PARKED_DIM := 0.35      # cabin glow scale on the ground with every engine stopped
const AO_AFFECT := 0.15       # cavity shade without flattening sunlit paint
const _MODEL := "res://aircraft/a320/models/"

static var _weather: ShaderMaterial


## Material name -> {roughness, metallic, clearcoat?, clearcoat_roughness?}. Empty for every other aircraft.
static func table(aircraft_id: String) -> Dictionary:
	if aircraft_id != "a320":
		return {}
	return {
		"a320_fuselage": {"roughness": 0.48, "metallic": 0.0, "clearcoat": 0.22, "clearcoat_roughness": 0.4},
		"a320_engine": {"roughness": 0.52, "metallic": 0.04},
		"a320_gear": {"roughness": 0.55, "metallic": 0.05},
		"wheel_mat": {"roughness": 0.9, "metallic": 0.0},
		# 0.05 metallic: a faint reflection on the shared glass (windscreen and cabin windows).
		"a320_glass": {"roughness": 0.08, "metallic": 0.05},
		"a320_fd_leather": {"roughness": 0.65, "metallic": 0.0},
		"a320_fd_glare": {"roughness": 0.7, "metallic": 0.0},
	}


## Panel legend materials. Not windows (a320_screen stays a display).
static func legend_names() -> Array:
	return ["a320_fd_buttons", "a320_fcu", "a320_radio"]


## 0 in daylight (sun elevation >= 5 deg, LightLogic.night_factor), up to 1 when the sun is down.
## On the ground with the engines stopped the cabin is dimmer (PARKED_DIM).
static func cabin_glow(sun_elev_deg: float, on_ground: bool, engines_on: bool) -> float:
	var night := LightLogic.night_factor(sun_elev_deg)
	if night <= 0.0:
		return 0.0
	if on_ground and not engines_on:
		return night * PARKED_DIM
	return night


## Small backlight for legend textures. 0 in daylight and with the bus unpowered. No dome light.
static func legend_energy(night: float, dim: float, powered: bool) -> float:
	if night <= 0.0 or not powered:
		return 0.0
	return night * (0.10 + 0.22 * clampf(dim, 0.0, 1.0))


## ao / normal paths for the A320 only. Interior is one AO file, not a per-name row.
static func _chart(exterior: bool) -> Dictionary:
	if not exterior:
		return {"ao": _MODEL + "interior_ao.png"}
	return {
		"a320_fuselage": {"ao": _MODEL + "exterior_ao.png", "normal": _MODEL + "exterior_panels.png", "scale": 0.5},
		"a320_engine": {"ao": _MODEL + "exterior_ao.png", "normal": _MODEL + "exterior_engine_panels.png", "scale": 0.35},
		"a320_gear": {"ao": _MODEL + "exterior_ao.png"},
		"a320_plain_333": {"ao": _MODEL + "exterior_ao.png"},
	}


## AO on UV2 and panel normals on UV1. `tex` stands in for the files (tests). A missing png is skipped.
## exterior false: interior_ao on every material except glass, screens and wheel_mat. No roughness change.
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
	if not spec.has("scale"):
		return
	var nrm: Texture2D = tex if tex != null else _load_tex(str(spec.get("normal", "")))
	if nrm == null:
		return
	mat.normal_enabled = true
	mat.normal_texture = nrm
	mat.normal_scale = float(spec.scale)


static func _load_tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## After an albedo swap: roughness / metal / clearcoat, then AO and normals again.
## Skips wheel_mat. Does not clear albedo. A missing map png is left unset.
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


## Walk the glb once. exterior: fuselage stain, cabin glass, rain, AO and panel normals.
## interior (exterior false): see-through windscreen, leather and glareshield roughness, interior AO
## on every opaque material (CockpitLighting's legend duplicate keeps that AO).
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
	var sun := LightLogic.sun_elev_now()
	var ground := Props.get_b("fdm/wow", true)
	var n := clampi(int(Props.get_f("engine/count", 2.0)), 1, 8)
	var on := false
	for i in n:
		if Props.get_b("engines/%d/running" % (i + 1)):
			on = true
			break
	return cabin_glow(sun, ground, on)


## Flight only (AircraftModel). Updates cabin-window emission and the stain frame.
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
	var list: Array = def.section("exhausts").get("list", [])
	var n := 0
	for e in list:
		if n >= 4 or not (e is Dictionary):
			continue
		var p: Array = e.get("pos", [])
		if p.size() < 3:
			continue
		var raw: Array = e.get("dir", [1.0, 0.0, 0.0])
		var dir := Vector3(1, 0, 0)
		if raw.size() >= 3:
			dir = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
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
