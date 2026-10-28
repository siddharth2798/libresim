class_name FdmNode
extends Node
## Runs the FDM at the physics rate (120 Hz) with SUBSTEPS sub-steps, reads pilot
## controls from Props ("controls/*") and publishes state to Props ("fdm/*",
## "engine/*"). Rendering reads interpolated pose via render_transform().

const SUBSTEPS := 2
const SMOOTHING_TAU := {"off": 0.0, "light": 0.05, "strong": 0.12}  # s, UserOptions control_smoothing
const AUTO_COORD := 0.5  # rudder per unit aileron (FlightGear auto-coordination-factor)

@export var terrain_path: NodePath
@export var trees_path: NodePath
@export var buildings_path: NodePath

var fdm: FDM
var paused := false
var replaying := false  # replay (systems/replay.gd) drives the state; physics holds
var _prev_pos := PackedFloat64Array([0.0, 0.0, 0.0])  # ENU at previous tick (64-bit: Vector3 is float32)
var _prev_q := Quaternion.IDENTITY
var _terrain: TerrainQuadtree
var _blds: Buildings
var _input_snap := true  # next control read jumps straight to the inputs (no smoothing)


func _ready() -> void:
	fdm = FDM.new()
	_terrain = get_node_or_null(terrain_path)
	if _terrain:
		fdm.ground_height = func(n: float, e: float) -> float: return _terrain.height_at(e, n)
		fdm.surface = func(n: float, e: float) -> int: return _terrain.cache.landclass_at(e, n)
	var trees := get_node_or_null(trees_path) as Trees
	_blds = get_node_or_null(buildings_path) as Buildings
	var blds := _blds
	# every solid near a point: shared registry (terminals, vehicles, ...), OSM buildings, trees
	fdm.obstacles = func(e: float, n: float, r: float, lo: float, _hi: float) -> Array:
		var out: Array = []
		ObstacleRegistry.near(e, n, r, out)
		if blds:
			blds.near(e, n, r, out)
		if trees:
			trees.near(e, n, r, lo, out)
		return out
	fdm.in_corridor = ObstacleRegistry.in_corridor
	_defaults()
	if fdm.cfg.has("apu"):
		var apu := Apu.new()
		apu.fdm = fdm
		apu.model = ApuModel.new(fdm.cfg.apu)
		add_child(apu)


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
	if _blds:
		_blds.place_aircraft(east, north)
	fdm.damage.reset()
	fdm.gear = Gears.make(fdm.cfg)  # repaired
	for u in fdm.units:
		u.engine.failed = false
	fdm.set_on_ground(north, east, deg_to_rad(heading_deg))
	_snap()


## Trimmed level flight at kias through the air mass (wind_ned: NED m/s at that height),
## in the current weather (weather/qnh_hpa, weather/temp_c), so the start is in trim.
func place_airborne(east: float, north: float, alt: float, heading_deg: float, kias: float, wind_ned := Vector3.ZERO) -> void:
	if _blds:
		_blds.place_aircraft(east, north)
	fdm.damage.reset()
	fdm.gear = Gears.make(fdm.cfg)
	if "gear_pos" in fdm.gear and not Props.get_v("controls/gear", 1):  # retractable gear, lever up: start with it retracted
		fdm.gear.gear_pos = 0.0
		fdm.gear.gear_cmd = 0
	for u in fdm.units:
		u.engine.failed = false
	fdm.atmo.qnh_pa = Props.get_f("weather/qnh_hpa", 1013.25) * 100.0
	fdm.atmo.delta_t = Props.get_f("weather/temp_c", 15.0) - 15.0
	fdm.wind_ned = wind_ned
	fdm.set_airborne(north, east, alt, deg_to_rad(heading_deg), kias * 0.514444)
	for u in fdm.units:
		u.warm_start(true)
	fdm.trim_level_cas(kias * 0.514444)
	Props.set_v("controls/throttle", fdm.engine.throttle)
	Props.set_v("controls/pitch_trim", fdm.fcs.pitch_trim)
	FdmAirlinerProps.after_trim(fdm)
	_snap()


func _snap() -> void:
	_prev_pos = PackedFloat64Array([fdm.pos_e, fdm.pos_n, -fdm.pos_d])
	_prev_q = fdm.q
	_input_snap = true


func _physics_process(delta: float) -> void:
	if paused or replaying or fdm.damage.crashed:
		return
	_prev_pos = PackedFloat64Array([fdm.pos_e, fdm.pos_n, -fdm.pos_d])
	_prev_q = fdm.q
	if _blds:  # building collision follows the aircraft (and where it is heading), not the camera
		var v := fdm.velocity_ned()
		_blds.focus_aircraft(fdm.pos_e, fdm.pos_n, v.y, v.x)
	_read_controls(delta)
	var dt := delta / SUBSTEPS
	for i in SUBSTEPS:
		fdm.step(dt)
	_publish()


func _read_controls(dt: float) -> void:
	var c := fdm.fcs
	# Pilot inputs arrive at frame rate (keyboard ramps, joystick noise, mouse jitter):
	# a first-order low-pass at the physics rate smooths the steps before the FCS.
	var tau: float = SMOOTHING_TAU.get(UserOptions.get_v("control_smoothing"), 0.05)
	var k := 1.0 if _input_snap or tau <= 0.0 else 1.0 - exp(-dt / tau)
	_input_snap = false
	var roll := Props.get_f("controls/roll")
	var yaw := Props.get_f("controls/yaw")
	if UserOptions.get_v("auto_coordination") and not c is AirlinerControls:  # FlightGear-style: rudder follows aileron
		yaw = clampf(yaw + AUTO_COORD * roll, -1.0, 1.0)
	c.pitch = lerpf(c.pitch, Props.get_f("controls/pitch"), k)
	c.roll = lerpf(c.roll, roll, k)
	c.yaw = lerpf(c.yaw, yaw, k)
	if not Props.get_b("failures/trim"):  # jammed trim stays where it was
		c.pitch_trim = Props.get_f("controls/pitch_trim")
	c.flap_cmd = Props.get_v("controls/flaps", 0)
	fdm.gear.brake_left = 0.0 if Props.get_b("failures/brake_left") else Props.get_f("controls/brake_left")
	fdm.gear.brake_right = 0.0 if Props.get_b("failures/brake_right") else Props.get_f("controls/brake_right")
	var mags: int = Props.get_v("controls/magnetos", 3)  # bit 1 = L, bit 2 = R
	if Props.get_b("failures/mag_left"):
		mags &= ~1
	if Props.get_b("failures/mag_right"):
		mags &= ~2
	var starter_ok := Props.get_b("systems/electrical/starter_ok", true)
	for i in fdm.units.size():
		var e := fdm.units[i].engine
		e.throttle = Props.get_f("ap/cmd/lever_%d" % (i + 1)) if Props.get_b("ap/athr_active") else _engine_f("throttle", i, 0.0)  # autothrust (systems/autoflight.gd) takes the levers
		e.mixture = _engine_f("mixture", i, 1.0)
		e.magnetos = mags
		e.starter = _engine_b("starter", i) and starter_ok
		var n := "" if i == 0 else "_%d" % (i + 1)  # engine 1: failures/engine; engine 2: failures/engine_2
		e.failed = Props.get_b("failures/engine" + n) or fdm.damage.struck.has(i)
		e.partial = Props.get_b("failures/engine_partial" + n)
	FdmAirlinerProps.read(fdm)
	c.flaps_powered = Props.get_b("systems/electrical/flaps_powered", true) and not Props.get_b("failures/flaps")
	var feed = Props.get_v("fuel/feed", null)  # per tank, from the fuel system
	var leak = Props.get_v("fuel/leak_kgs", null)
	for i in fdm.tank_feed.size():
		if feed is Array and i < feed.size():
			fdm.tank_feed[i] = float(feed[i])
		if leak is Array and i < leak.size():
			fdm.tank_leak_kgs[i] = float(leak[i])
	fdm.fuel_available = Props.get_b("fuel/available", true)
	if Props.has("environment/wind_ned"):
		fdm.wind_ned = Props.get_v("environment/wind_ned")
	if Props.has("environment/qnh_pa"):
		fdm.atmo.qnh_pa = Props.get_f("environment/qnh_pa")
		fdm.atmo.delta_t = Props.get_f("environment/delta_t")


## Lever of engine i: controls/<name> for engine 1 (and for any engine without its own),
## controls/<name>_<i+1> to move engines separately.
func _engine_f(name: String, i: int, default: float) -> float:
	var own := "controls/%s_%d" % [name, i + 1]
	return Props.get_f(own if i > 0 and Props.has(own) else "controls/" + name, default)


func _engine_b(name: String, i: int) -> bool:
	var own := "controls/%s_%d" % [name, i + 1]
	return Props.get_b(own if i > 0 and Props.has(own) else "controls/" + name)


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
	Props.set_v("fdm/flap_detents", f.fcs.flap_detents())
	Props.set_v("fdm/mass_kg", f.mb.mass)
	Props.set_v("atmosphere/pressure_pa", f.atmo.pressure)
	Props.set_v("atmosphere/temperature_k", f.atmo.temperature)
	Props.set_v("atmosphere/density", f.atmo.density)
	Props.set_v("engine/count", f.units.size())
	Props.set_v("engine/rpm", f.prop.rpm)
	Props.set_v("engine/running", f.engine.running)
	Props.set_v("engine/map_pa", f.engine.map_pa)
	var flow := 0.0
	for i in f.units.size():
		var u := f.units[i]
		flow += u.engine.fuel_flow_kgs
		var b := "engines/%d/" % (i + 1)  # every engine, 1-based
		Props.set_v(b + "rpm", u.thruster.rpm)
		Props.set_v(b + "running", u.engine.running)
		Props.set_v(b + "thrust_n", u.thruster.thrust)
		Props.set_v(b + "fuel_flow_kgs", u.engine.fuel_flow_kgs)
		Props.set_v(b + "egt_k", u.engine.egt_k)
		Props.set_v(b + "oil_press_pa", u.engine.oil_press_pa)
		Props.set_v(b + "oil_temp_k", u.engine.oil_temp_k)
	Props.set_v("engine/fuel_flow_kgs", flow)  # all engines
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
	Props.set_v("fuel/left_kg", f.mb.side_kg("left"))
	Props.set_v("fuel/right_kg", f.mb.side_kg("right"))
	Props.set_v("fuel/tank_kg", f.mb.tanks.map(func(t): return t.contents_kg))
	Props.set_v("systems/electrical/flap_motor_running", f.fcs.flap_motor_running)
	FdmAirlinerProps.publish(f)


## Pose interpolated between physics ticks, in render space.
func render_transform() -> Transform3D:
	var a := Engine.get_physics_interpolation_fraction()
	# interpolate and shift to render space in 64-bit; a float32 Vector3 of ENU
	# would quantise to 6 cm ~1000 km from the world origin (visible jitter)
	var e := lerpf(_prev_pos[0], fdm.pos_e, a)
	var n := lerpf(_prev_pos[1], fdm.pos_n, a)
	var u := lerpf(_prev_pos[2], -fdm.pos_d, a)
	var q := _prev_q.slerp(fdm.q, a)
	return Transform3D(ned_to_render_basis(q), FloatingOrigin.to_render_d(e, n, u))


## Body->NED quaternion to a Godot basis whose -Z is the nose, +Y the canopy, +X the right wing.
static func ned_to_render_basis(q: Quaternion) -> Basis:
	var r := Basis(q)  # columns: body x (nose), y (right), z (down) in NED
	var to_r := func(v: Vector3) -> Vector3: return Vector3(v.y, -v.z, -v.x)  # NED -> render (E, U, -N)
	var nose: Vector3 = to_r.call(r.x)
	var right: Vector3 = to_r.call(r.y)
	var down: Vector3 = to_r.call(r.z)
	return Basis(right, -down, -nose)
