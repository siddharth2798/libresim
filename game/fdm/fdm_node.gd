class_name FdmNode
extends Node
## Runs the FDM at the physics rate (120 Hz) with SUBSTEPS sub-steps, reads pilot
## controls from Props ("controls/*") and publishes state to Props ("fdm/*",
## "engine/*"). Rendering reads interpolated pose via render_transform().

const SUBSTEPS := 2

@export var terrain_path: NodePath
@export var trees_path: NodePath

var fdm: FDM
var paused := false
var _prev_pos := Vector3.ZERO  # ENU at previous physics tick
var _prev_q := Quaternion.IDENTITY
var _terrain: TerrainQuadtree


func _ready() -> void:
	fdm = FDM.new()
	_terrain = get_node_or_null(terrain_path)
	if _terrain:
		fdm.ground_height = func(n: float, e: float) -> float: return _terrain.height_at(e, n)
		fdm.surface = func(n: float, e: float) -> int: return _terrain.cache.landclass_at(e, n)
	var trees := get_node_or_null(trees_path) as Trees
	if trees:
		fdm.obstacle_top = func(n: float, e: float) -> float: return trees.tree_top_at(e, n)
	_defaults()


func _defaults() -> void:
	for k in ["pitch", "roll", "yaw", "pitch_trim", "brake_left", "brake_right"]:
		Props.set_v("controls/" + k, 0.0)
	Props.set_v("controls/throttle", 0.0)
	Props.set_v("controls/mixture", 1.0)
	Props.set_v("controls/flaps", 0)
	Props.set_v("controls/magnetos", 3)
	Props.set_v("controls/starter", false)


## ENU position of the CG (east, north, up).
func position_enu() -> Vector3:
	return Vector3(fdm.pos_e, fdm.pos_n, -fdm.pos_d)


func place_on_ground(east: float, north: float, heading_deg: float) -> void:
	fdm.damage.reset()
	fdm.gear = GearGround.new(fdm.cfg)  # repaired
	fdm.engine.failed = false
	fdm.set_on_ground(north, east, deg_to_rad(heading_deg))
	_snap()


func place_airborne(east: float, north: float, alt: float, heading_deg: float, kias: float) -> void:
	fdm.damage.reset()
	fdm.gear = GearGround.new(fdm.cfg)
	fdm.engine.failed = false
	fdm.set_airborne(north, east, alt, deg_to_rad(heading_deg), kias * 0.514444)
	fdm.prop.rpm = 2300.0
	fdm.trim_level(kias * 0.514444)
	Props.set_v("controls/throttle", fdm.engine.throttle)
	Props.set_v("controls/pitch_trim", fdm.fcs.pitch_trim)
	_snap()


func _snap() -> void:
	_prev_pos = position_enu()
	_prev_q = fdm.q


func _physics_process(delta: float) -> void:
	if paused or fdm.damage.crashed:
		return
	_prev_pos = position_enu()
	_prev_q = fdm.q
	_read_controls()
	var dt := delta / SUBSTEPS
	for i in SUBSTEPS:
		fdm.step(dt)
	_publish()


func _read_controls() -> void:
	var c := fdm.fcs
	c.pitch = Props.get_f("controls/pitch")
	c.roll = Props.get_f("controls/roll")
	c.yaw = Props.get_f("controls/yaw")
	c.pitch_trim = Props.get_f("controls/pitch_trim")
	c.flap_cmd = Props.get_v("controls/flaps", 0)
	fdm.gear.brake_left = Props.get_f("controls/brake_left")
	fdm.gear.brake_right = Props.get_f("controls/brake_right")
	var e := fdm.engine
	e.throttle = Props.get_f("controls/throttle")
	e.mixture = Props.get_f("controls/mixture", 1.0)
	e.magnetos = Props.get_v("controls/magnetos", 3)
	e.starter = Props.get_b("controls/starter") and Props.get_b("systems/electrical/starter_ok", true)
	e.failed = Props.get_b("failures/engine")
	c.flaps_powered = Props.get_b("systems/electrical/flaps_powered", true)
	fdm.feed_left = Props.get_f("fuel/feed_left", 0.5)
	fdm.feed_right = Props.get_f("fuel/feed_right", 0.5)
	fdm.fuel_available = Props.get_b("fuel/available", true)
	fdm.leak_left_kgs = Props.get_f("fuel/leak_left_kgs")
	if Props.has("environment/wind_ned"):
		fdm.wind_ned = Props.get_v("environment/wind_ned")
	if Props.has("environment/qnh_pa"):
		fdm.atmo.qnh_pa = Props.get_f("environment/qnh_pa")
		fdm.atmo.delta_t = Props.get_f("environment/delta_t")


func _publish() -> void:
	var f := fdm
	var e := f.euler()
	var v_ned := f.velocity_ned()
	Props.set_v("fdm/position_enu", position_enu())
	Props.set_v("fdm/roll_rad", e.x)
	Props.set_v("fdm/pitch_rad", e.y)
	Props.set_v("fdm/heading_rad", e.z)
	Props.set_v("fdm/body_rates", f.w_b)
	Props.set_v("fdm/tas_mps", f.vt)
	Props.set_v("fdm/cas_mps", f.cas)
	Props.set_v("fdm/groundspeed_mps", Vector2(v_ned.x, v_ned.y).length())
	Props.set_v("fdm/track_rad", fposmod(atan2(v_ned.y, v_ned.x), TAU))
	Props.set_v("fdm/vs_mps", -v_ned.z)
	Props.set_v("fdm/alt_m", f.altitude())
	Props.set_v("fdm/agl_m", f.agl)
	Props.set_v("fdm/alpha_rad", f.alpha)
	Props.set_v("fdm/beta_rad", f.beta)
	Props.set_v("fdm/load_factor", f.load_factor)
	Props.set_v("fdm/accel_body", f.accel_b)
	Props.set_v("fdm/wow", f.gear.wow)
	Props.set_v("fdm/stall_warning", f.alpha > f.aero.alpha_max * 0.85 and not f.gear.wow)
	Props.set_v("fdm/flap_deg", f.fcs.flap_deg)
	Props.set_v("fdm/mass_kg", f.mb.mass)
	Props.set_v("atmosphere/pressure_pa", f.atmo.pressure)
	Props.set_v("atmosphere/temperature_k", f.atmo.temperature)
	Props.set_v("atmosphere/density", f.atmo.density)
	Props.set_v("engine/rpm", f.prop.rpm)
	Props.set_v("engine/running", f.engine.running)
	Props.set_v("engine/map_pa", f.engine.map_pa)
	Props.set_v("engine/fuel_flow_kgs", f.engine.fuel_flow_kgs)
	Props.set_v("engine/egt_k", f.engine.egt_k)
	Props.set_v("engine/cht_k", f.engine.cht_k)
	Props.set_v("engine/oil_temp_k", f.engine.oil_temp_k)
	Props.set_v("engine/oil_press_pa", f.engine.oil_press_pa)
	Props.set_v("engine/power_w", f.engine.power_w)
	Props.set_v("engine/thrust_n", f.prop.thrust)
	Props.set_v("fuel/total_kg", f.mb.fuel_kg())
	var d := f.damage
	Props.set_v("damage/crashed", d.crashed)
	Props.set_v("damage/reason", d.crash_reason)
	Props.set_v("damage/events", d.events)
	Props.set_v("damage/structure", d.structure_damaged)
	Props.set_v("damage/last_touchdown", d.last_touchdown)
	Props.set_v("fuel/left_kg", f.mb.tanks[0].contents_kg)
	Props.set_v("fuel/right_kg", f.mb.tanks[1].contents_kg)
	Props.set_v("systems/electrical/flap_motor_running", f.fcs.flap_motor_running)


## Pose interpolated between physics ticks, in render space.
func render_transform() -> Transform3D:
	var a := Engine.get_physics_interpolation_fraction()
	var p := _prev_pos.lerp(position_enu(), a)
	var q := _prev_q.slerp(fdm.q, a)
	return Transform3D(ned_to_render_basis(q), FloatingOrigin.to_render(p))


## Body->NED quaternion to a Godot basis whose -Z is the nose, +Y the canopy, +X the right wing.
static func ned_to_render_basis(q: Quaternion) -> Basis:
	var r := Basis(q)  # columns: body x (nose), y (right), z (down) in NED
	var to_r := func(v: Vector3) -> Vector3: return Vector3(v.y, -v.z, -v.x)  # NED -> render (E, U, -N)
	var nose: Vector3 = to_r.call(r.x)
	var right: Vector3 = to_r.call(r.y)
	var down: Vector3 = to_r.call(r.z)
	return Basis(right, -down, -nose)
