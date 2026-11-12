class_name TouchdownDetect
extends RefCounted
## Which wheel spins up on touchdown, from the FDM gear contacts (gear.info). The FDM has no wheel rotation, so
## each tyre's rim speed is kept here: on the ground it rolls at the ground speed, in the air it runs down
## slowly (bearing and air drag, time constant SPIN_TAU). When a tyre meets the runway its rim speed is short
## of the ground speed by the slip; the runway has to spin it up and that slide is the squeal and the smoke.
## So the first touchdown after a flight (wheels stopped) slides at the full ground speed, a wheel back down
## after a short hop is still turning (little slip, no event), a taxi bump is never off long enough, and each
## wheel gives at most one event per touchdown. Only a landing counts: the wheel must have been off the ground for
## MIN_AIR_S and be coming down (sink > MIN_SINK), so a takeoff roll, rotation, liftoff, taxiing, an aircraft
## placed or restarted on the ground, or a flight loaded on the ground never smokes or squeals. A nose wheel only
## counts when it lands sliding sideways (it is light and unbraked, so a straight nose-down is quiet).
## Pure: no nodes, no Props; TouchdownFx feeds it once per physics tick.

const MIN_GS := 12.0  # m/s (~23 kt): slower contacts are taxiing, not landing
const MIN_SLIP := 5.0  # m/s between rim and runway before a tyre is heard and seen to slide
const SPIN_TAU := 8.0  # s: an unbraked tyre in the air runs down to 1/e of its speed in this time
const NOSE_SLIDE := 1.0  # m/s sideways at contact before a nose wheel scrubs
const MIN_AIR_S := 0.5  # s off the ground before a contact can be a touchdown (oleo flicker on a takeoff roll is not)
const MIN_SINK := 0.05  # m/s: the wheel must be coming down onto the runway

var _air := {}  # wheel name -> seconds since it last touched
var _rim := {}  # wheel name -> rim speed (m/s); a wheel never seen on the ground is stopped


## Rim speed (m/s) of a tyre that left the ground turning at `rim` after `airborne_s` seconds in the air.
static func run_down(rim: float, airborne_s: float) -> float:
	return rim * exp(-airborne_s / SPIN_TAU)


## True when a wheel of this role touching with `slip` (m/s, ground speed minus rim speed) at ground speed `gs`,
## sideways tyre speed `vlat` (m/s) after `airborne_s` in the air, has to be spun up by the runway.
## sink: the contact's downward speed (m/s).
static func spins_up(role: String, slip: float, gs: float, vlat: float, airborne_s: float, sink := 1.0) -> bool:
	if gs < MIN_GS or airborne_s < MIN_AIR_S or sink < MIN_SINK:
		return false
	if role == "nose":
		return absf(vlat) >= NOSE_SLIDE
	return Vector2(slip, vlat).length() >= MIN_SLIP


func clear() -> void:
	_air.clear()
	_rim.clear()


## One physics tick. contacts / info: GearGround.contacts and .info; v_ned: the aircraft velocity (NED, m/s).
## Returns the wheels that touched down this tick: [{wheel, role, n, e, sink (m/s, + down), vlat, gs, slip (m/s),
## track (rad, from north), airborne_s}].
func step(contacts: Array, info: Dictionary, v_ned: Vector3, dt: float) -> Array:
	var out: Array = []
	var gs := Vector2(v_ned.x, v_ned.y).length()
	for c in contacts:
		if not c.wheel:
			continue
		var w: Dictionary = info.get(c.name, {})
		if float(w.get("depth", 0.0)) <= 0.0:
			_air[c.name] = float(_air.get(c.name, 0.0)) + dt
			continue
		# first seen on the ground (a ground start, a loaded flight): already rolling; or still on the ground
		var on_before: bool = not _air.has(c.name) or float(_air[c.name]) == 0.0
		var air: float = _air.get(c.name, 0.0)
		_air[c.name] = 0.0
		var slip: float = gs - run_down(float(_rim.get(c.name, 0.0)), air)
		_rim[c.name] = gs  # rolling: the rim runs at the ground speed
		if on_before:
			continue
		var vlat := float(w.get("vlat", 0.0))
		var role := str(c.get("role", "main"))
		if spins_up(role, slip, gs, vlat, air, float(w.get("vz", 0.0))):
			out.append({"wheel": c.name, "role": role, "n": float(w.n), "e": float(w.e), "sink": float(w.get("vz", 0.0)),
				"vlat": vlat, "gs": gs, "slip": maxf(slip, 0.0), "track": atan2(v_ned.y, v_ned.x), "airborne_s": air})
	return out


## ENU (east, north, up) of a gear contact point now, from the FDM state (body -> NED, as GearGround places it).
static func wheel_enu(fd: FDM, wheel: String) -> Vector3:
	for c in fd.gear.contacts:
		if c.name == wheel:
			var p := Vector3(fd.pos_n, fd.pos_e, fd.pos_d) + Basis(fd.q) * fd.mb.body_of(c.pos)
			return Vector3(p.y, p.x, -p.z)
	return Vector3(fd.pos_e, fd.pos_n, -fd.pos_d)
