class_name GroundVehicles
extends RefCounted
## The parked and working ground vehicles of an airport, built in code (no imported models): one cached
## mesh per kind (body surface + glass surface, with automatic LODs), shared materials, plus a small ground
## decal (contact shadow, tyre blobs, headlamp pool). Models face -Z with the origin on the ground at their
## middle. Each vehicle gets a seed (fleet number, dirt, beacon phase) and a working flag (beacon turning,
## headlamps at night) as instance uniforms, so every vehicle of a kind still shares one mesh and material.
## Pieces: vehicle_geo.gd (mesh builder), vehicle_parts.gd / vehicle_trim.gd (wheels, slabs, lamps...),
## veh_*.gd (one per vehicle), vehicle.gdshader (+ vehicle_surface.gdshaderinc), follow_me_glass.gdshader,
## vehicle_ground.gd(shader); night light points: vehicle_lamps.gd; driving (wheels): vehicle_motion.gd.
## The follow-me car (follow_me_car.gd) has its own builder and materials.

const KINDS := ["fuel_truck", "hydrant_dispenser", "gpu", "baggage_tug", "baggage_cart", "apron_bus", "fire_truck", "pushback_tug"]
const NOTES := {"fuel_truck": "refuelling truck", "hydrant_dispenser": "hydrant dispenser", "gpu": "ground power unit",
	"baggage_tug": "baggage tractor", "baggage_cart": "baggage cart", "apron_bus": "apron bus",
	"fire_truck": "rescue and fire-fighting truck", "pushback_tug": "pushback tug"}
const WORKING := 0.4  # share of the parked vehicles that are working (beacon, lamps)
const LOD_BIAS := 1.0

static var _meshes := {}
static var _grounds := {}
static var _lamps := {}  # kind -> VehicleGeo.lamps
static var _wheels := {}  # kind -> VehicleGeo.wheels
static var _mat: ShaderMaterial
static var _glass: ShaderMaterial
static var _ground_mat: ShaderMaterial
static var _night := 0.0
static var _night_timer := 0.0


static func has(kind: String) -> bool:
	return kind in KINDS


static func materials() -> void:
	if _mat != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://world/vehicle.gdshader")
	_mat.set_shader_parameter("dirt", 0.6)
	_glass = ShaderMaterial.new()
	_glass.shader = preload("res://world/follow_me_glass.gdshader")
	_glass.render_priority = -1
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://world/vehicle_ground.gdshader")
	_ground_mat.render_priority = -2


static func _build(kind: String) -> void:
	materials()
	var g := VehicleGeo.new()
	var gl := VehicleGeo.new()
	match kind:
		"fuel_truck": VehFuelTruck.build(g, gl)
		"hydrant_dispenser": VehHydrant.build(g, gl)
		"gpu": VehGpu.build(g, gl)
		"baggage_tug": VehBaggage.tug(g, gl)
		"baggage_cart": VehBaggage.cart(g, gl)
		"apron_bus": VehBus.build(g, gl)
		"fire_truck": VehFireTruck.build(g, gl)
		"pushback_tug": VehTug.build(g, gl)
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, g.to_arrays(), [], {}, _mat, "body", g.format())
	if not gl.pos.is_empty():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, gl.to_arrays(), [], {}, _glass, "glass", gl.format())
	im.generate_lods(25.0, 60.0, [])
	var m := im.get_mesh()
	_meshes[kind] = m
	_lamps[kind] = g.lamps
	_wheels[kind] = g.wheels
	_grounds[kind] = VehicleGround.build(m.get_aabb(), g.wheels, g.lamps, _ground_mat)


static func mesh(kind: String) -> ArrayMesh:
	if not _meshes.has(kind):
		_build(kind)
	return _meshes[kind]


static func ground_mesh(kind: String) -> ArrayMesh:
	mesh(kind)
	return _grounds[kind]


## Lamps of a kind in its model frame: [["head" | "tail" | "beacon", position, side], ...].
static func lamps(kind: String) -> Array:
	mesh(kind)
	return _lamps[kind]


## Wheels of a kind: [[centre, radius, width, steers], ...].
static func wheels(kind: String) -> Array:
	mesh(kind)
	return _wheels[kind]


## Seed of a vehicle placed at world (east, north): stable for a stand, different between stands.
static func seed_at(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)


## A vehicle node: a Node3D holding the body MeshInstance3D ("Body", its bounds are the footprint) and the
## ground decal ("Ground", meta no_solid). size scales the model uniformly (the pushback tug for an
## airliner: ground.tug_scale); the cached meshes are shared. seed 0..1 picks fleet number, dirt and
## beacon phase; working: beacon turning, headlamps at night. moving: a VehicleMotion root that rolls
## and steers the wheels as the node is moved.
static func make(kind: String, size := 1.0, seed := 0.5, working := false, moving := false) -> Node3D:
	var root: Node3D = VehicleMotion.new() if moving else Node3D.new()
	root.name = kind
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh(kind)
	mi.scale = Vector3.ONE * size
	mi.lod_bias = LOD_BIAS
	mi.visibility_range_end = 4000.0 * size
	mi.set_instance_shader_parameter("seed", seed)
	mi.set_instance_shader_parameter("lamps", 1.0 if working else 0.0)
	root.add_child(mi)
	var gd := MeshInstance3D.new()
	gd.name = "Ground"
	gd.mesh = _grounds[kind]
	gd.scale = Vector3.ONE * size
	gd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gd.visibility_range_end = 450.0
	gd.set_instance_shader_parameter("lamps", 1.0 if working else 0.0)
	gd.set_meta("no_solid", true)
	root.add_child(gd)
	if moving:  # it carries its own light points (omnidirectional: they do not turn with it)
		(root as VehicleMotion).setup(mi, wheels(kind), size)
		if working:
			var lp := VehicleLamps.new()
			lp.add(kind, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3.ZERO), seed, false)
			lp.attach(root)
	return root


static func triangles(kind: String) -> int:
	return FollowMeShell.triangles(mesh(kind))


static func night() -> float:
	return _night


## Once per frame (AirportOps): lamps and the paint's night look follow the sun (beacons turn in the shader).
static func tick(dt: float) -> void:
	if _mat == null:
		return
	_night_timer -= dt
	if _night_timer <= 0.0:
		_night_timer = 0.5
		_night = FollowMeLogic.night_level(Props.get_f("environment/sun_elev_deg", 30.0),
			Props.get_f("environment/visibility_m", Props.get_f("weather/visibility_m", 20000.0)))
		_mat.set_shader_parameter("night", _night)
		_mat.set_shader_parameter("head_glow", lerpf(0.0, 1.0, _night))
		_mat.set_shader_parameter("tail_glow", lerpf(0.1, 0.35, _night))
		VehicleLamps.set_night(_night)


## Drop the cached meshes and materials (scene teardown, tests): they are static, so the engine
## would otherwise report them as still in use at exit.
static func release() -> void:
	_meshes.clear()
	_grounds.clear()
	_lamps.clear()
	_wheels.clear()
	_mat = null
	_glass = null
	_ground_mat = null
	VehicleLamps.release()
