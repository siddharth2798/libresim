class_name EngineWash
extends GroundEmitter
## Wash of one engine over the ground (GroundFx feeds it every frame). A propeller at high power, standing or slow
## (run-up, the start of a takeoff roll), blows a fine mist back along wet ground; a jet at high thrust only stirs a
## lighter, lower sheet of it. On dry grass or dirt the same wash raises dust instead (the particle colour switches).
## Strength from the unit's thrust against its full static thrust: a jet's configured thrust_n, or for a propeller
## the thrust that drives a 36 m/s slipstream through its disc (momentum theory, ~2.3 kN for the C172's 1.9 m prop).

const SLIPSTREAM := 36.0  # m/s: full-power slipstream of a light-aircraft propeller
const MAX_HUB_AGL := 6.0  # m: higher (airborne) and the wash no longer reaches the ground
const RHO := 1.225

var unit: PowerUnit
var jet := false
var ref_thrust := 1.0  # N: full static thrust
var disc_r := 0.9  # m: propeller radius (or a jet's sheet half width)


func _init() -> void:
	super("wash")


func setup(u: PowerUnit) -> void:
	unit = u
	jet = not (u.thruster is Propeller)
	ref_thrust = thrust_ref(u)
	disc_r = 1.2 if jet else maxf(u.thruster.diameter * 0.5, 0.5)


## Full static thrust (N) of a power unit (see the class note).
static func thrust_ref(u: PowerUnit) -> float:
	if u.engine is EngineTurbine:
		return maxf((u.engine as EngineTurbine).thrust_sl, 1.0)
	var r := maxf(u.thruster.diameter * 0.5, 0.3)
	return 0.5 * RHO * PI * r * r * SLIPSTREAM * SLIPSTREAM


## Wash strength 0..1 from thrust (N) against the full static thrust: nothing at idle, full well before take-off power.
static func wash_k(thrust: float, ref: float) -> float:
	return smoothstep(0.2, 0.7, thrust / maxf(ref, 1.0))


## [rate 0..1, dust?] of the wash for strength k, surface wetness 0..1, ground speed (m/s) and surface. Fades out as
## the aircraft speeds up (the wash then lands far behind, spread thin). A jet's mist is half as thick.
static func wash_rate(k: float, wet: float, gs: float, paved: bool, is_jet := false) -> Array:
	var slow := 1.0 - smoothstep(8.0, 25.0, gs)
	var water := k * smoothstep(0.1, 0.6, wet) * slow * (0.5 if is_jet else 1.0)
	var dust := 0.0 if paved else k * (1.0 - smoothstep(0.1, 0.35, wet)) * slow * 0.8
	return [dust, true] if dust > water else [water, false]


## One frame. fd: the FDM; wet 0..1; paved: the ground under the engine; drift: wind push (render frame, m/s^2).
func update(fd: FDM, wet: float, paved: bool, drift: Vector3) -> void:
	if unit == null or capacity <= 0:
		set_rate(0.0)
		return
	var b := Basis(fd.q)
	var hub := Vector3(fd.pos_n, fd.pos_e, fd.pos_d) + b * fd.mb.body_of(unit.pos)  # NED
	var aft := -(b * unit.thrust_dir)
	var ah := Vector2(aft.x, aft.y).normalized()  # horizontal, NED (north, east)
	var g: float = fd.ground_height.call(hub.x, hub.y)
	var gs := Vector2(fd.velocity_ned().x, fd.velocity_ned().y).length()
	var r := wash_rate(wash_k(unit.thruster.thrust, ref_thrust), wet, gs, paved, jet) if -hub.z - g < MAX_HUB_AGL else [0.0, false]
	set_rate(r[0])
	if r[0] <= 0.0:
		return
	var back := 7.0 if jet else 2.5  # m behind the hub: just aft of the disc
	var src := FloatingOrigin.to_render_d(hub.y + ah.y * back, hub.x + ah.x * back, g + 0.15)
	var dir := Vector3(ah.y, 0.0, -ah.x)  # render frame (x east, z south)
	var v := fd.velocity_ned()
	place(src, Vector3(v.y, -v.z, -v.x))
	proc.color = GroundFxLook.DUST if r[1] else GroundFxLook.WATER
	proc.emission_box_extents = Vector3(disc_r * 0.8, 0.05, disc_r * 0.8)
	proc.direction = (dir + Vector3.UP * (0.12 if jet else 0.25)).normalized()
	var push := sqrt(2.0 * maxf(unit.thruster.thrust, 0.0) / (RHO * PI * disc_r * disc_r)) if not jet else 40.0
	proc.initial_velocity_min = clampf(push, 0.0, 40.0) * 0.25
	proc.initial_velocity_max = clampf(push, 0.0, 40.0) * 0.45
	proc.gravity = Vector3(drift.x, 0.2, drift.z)
