class_name GroundVehicles
extends RefCounted
## The parked and working ground vehicles of an airport, built in code (no imported models): one cached
## mesh per kind (body surface + glass surface), shared materials, so a busy apron costs two draw calls per
## vehicle and nothing is loaded from disk. Models face -Z with the origin on the ground at their middle.
## Pieces: vehicle_geo.gd (mesh builder), vehicle_parts.gd (wheels, slabs, lamps...), veh_*.gd (one per
## vehicle), follow_me.gdshader / follow_me_glass.gdshader (paint, rubber, lamps, haze). The follow-me
## car (follow_me_car.gd) is the one that moves and has its own materials.

const KINDS := ["fuel_truck", "gpu", "baggage_tug", "baggage_cart", "apron_bus", "fire_truck", "pushback_tug"]
const NOTES := {"fuel_truck": "refuelling truck", "gpu": "ground power unit", "baggage_tug": "baggage tractor",
	"baggage_cart": "baggage cart", "apron_bus": "apron bus", "fire_truck": "rescue and fire-fighting truck",
	"pushback_tug": "pushback tug"}

static var _meshes := {}
static var _mat: ShaderMaterial
static var _glass: ShaderMaterial
static var _night := 0.0
static var _night_timer := 0.0
static var _t := 0.0


static func has(kind: String) -> bool:
	return kind in KINDS


static func materials() -> void:
	if _mat != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://world/follow_me.gdshader")
	_mat.set_shader_parameter("panel_gaps", 0.0)
	_mat.set_shader_parameter("dirt", 0.55)
	_mat.set_shader_parameter("tail_glow", 0.15)
	_glass = ShaderMaterial.new()
	_glass.shader = preload("res://world/follow_me_glass.gdshader")
	_glass.render_priority = -1


static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	materials()
	var g := VehicleGeo.new()
	var gl := VehicleGeo.new()
	match kind:
		"fuel_truck": VehFuelTruck.build(g, gl)
		"gpu": VehGpu.build(g, gl)
		"baggage_tug": VehBaggage.tug(g, gl)
		"baggage_cart": VehBaggage.cart(g, gl)
		"apron_bus": VehBus.build(g, gl)
		"fire_truck": VehFireTruck.build(g, gl)
		"pushback_tug": VehTug.build(g, gl)
	var m := ArrayMesh.new()
	g.commit(m, _mat)
	gl.commit(m, _glass)
	_meshes[kind] = m
	return m


## A vehicle node: a Node3D holding one MeshInstance3D (the placed footprint comes from its bounds).
## size scales the model uniformly (the pushback tug for an airliner: ground.tug_scale); the cached mesh is shared.
static func make(kind: String, size := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	mi.scale = Vector3.ONE * size
	root.add_child(mi)
	return root


static func triangles(kind: String) -> int:
	return FollowMeShell.triangles(mesh(kind))


## Once per frame (AirportOps): beacons flash, lamps and the paint's night look follow the sun.
static func tick(dt: float) -> void:
	if _mat == null:
		return
	_t += dt
	_night_timer -= dt
	if _night_timer <= 0.0:
		_night_timer = 0.5
		_night = FollowMeLogic.night_level(Props.get_f("environment/sun_elev_deg", 30.0),
			Props.get_f("environment/visibility_m", Props.get_f("weather/visibility_m", 20000.0)))
		_mat.set_shader_parameter("night", _night)
		_mat.set_shader_parameter("head_glow", lerpf(0.0, 0.7, _night))
		_mat.set_shader_parameter("tail_glow", lerpf(0.1, 0.35, _night))
	_mat.set_shader_parameter("amber_l", FollowMeLogic.flash(_t, 0))
	_mat.set_shader_parameter("amber_r", FollowMeLogic.flash(_t, 1))


## Drop the cached meshes and materials (scene teardown, tests): they are static, so the engine
## would otherwise report them as still in use at exit.
static func release() -> void:
	_meshes.clear()
	_mat = null
	_glass = null
