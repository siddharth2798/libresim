class_name FollowMeLogic
extends RefCounted
## The follow-me car's dimensions and the pure maths behind its look: beacon flash pattern,
## brake-light state, wheel spin, steering angle, body pitch / roll, ground tilt. No nodes.
## Vehicle frame: x right, y up, -z forward. Compass heading increases to the right.

const WHEEL_R := 0.37
const AXLE_F := -1.55  # z of the front axle
const AXLE_R := 1.45
const TRACK_HALF := 0.80
const WHEELBASE := AXLE_R - AXLE_F
const ARCH_R := 0.50  # wheel arch radius
const ROLL_PIVOT := Vector3(0.0, 0.45, 0.0)  # body pitches and rolls about this point
const FLASH_PERIOD := 1.2  # s: each side double-flashes once per period, the sides alternate


## Roof beacon intensity 0..1 at time t for side 0 (left) or 1 (right): two 70 ms flashes 90 ms apart,
## then the other side takes over.
static func flash(t: float, side: int) -> float:
	var p := fposmod(t - 0.5 * FLASH_PERIOD * side, FLASH_PERIOD)
	return _pulse(p, 0.0, 0.07) + _pulse(p, 0.16, 0.23)


static func _pulse(p: float, a: float, b: float) -> float:
	return smoothstep(a - 0.002, a + 0.012, p) * (1.0 - smoothstep(b - 0.004, b + 0.012, p))


## Brake lights: on while stopped, or braking harder than about 0.5 m/s2; once on they stay on until
## the deceleration falls below 0.15 m/s2.
static func brake_on(accel: float, speed: float, was_on: bool) -> bool:
	if speed < 0.25 or accel < -0.5:
		return true
	return was_on and accel < -0.15


## Wheel rolling angle (rad, 0..TAU, grows going forward) after dt at ground speed v.
static func spin(angle: float, v: float, radius: float, dt: float) -> float:
	return fposmod(angle + v * dt / radius, TAU)


## Front wheel angle (rad, positive = turning right) from the heading rate (rad/s, compass: right
## turn positive): the bicycle model, limited to a pickup's lock.
static func steer_angle(v: float, yaw_rate: float) -> float:
	return clampf(atan(WHEELBASE * yaw_rate / maxf(absf(v), 1.0)), -0.6, 0.6)


## Signed shortest angle from `from` to `to` (rad).
static func angle_diff(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


## `cur` turned toward `target` by at most max_rate * dt.
static func turn_toward(cur: float, target: float, max_rate: float, dt: float) -> float:
	var d := angle_diff(cur, target)
	return cur + clampf(d, -max_rate * dt, max_rate * dt)


## Body pitch (nose up positive) and roll (right side up positive) the suspension settles to under a
## forward acceleration and a rightward lateral acceleration (m/s2): squat, dive, lean out of a turn.
static func body_targets(accel: float, lateral: float) -> Vector2:
	return Vector2(clampf(0.010 * accel, -0.035, 0.035), clampf(0.012 * lateral, -0.045, 0.045))


## One step of a damped spring (omega rad/s, damping ratio zeta): x = value, v = rate. Returns (x, v).
static func spring_step(x: float, v: float, target: float, omega: float, zeta: float, dt: float) -> Vector2:
	v += (omega * omega * (target - x) - 2.0 * zeta * omega * v) * dt
	return Vector2(x + v * dt, v)


## Ground tilt from the heights under the front axle, rear axle, left and right wheels:
## (pitch nose-up, roll right-up), rad.
static func ground_tilt(h_front: float, h_rear: float, h_left: float, h_right: float) -> Vector2:
	return Vector2(atan2(h_front - h_rear, WHEELBASE), atan2(h_right - h_left, 2.0 * TRACK_HALF))


## Lamp levels from the sun elevation (deg) and the visibility: 0 by day, 1 at night. Same rule as
## the aerodrome lights (RunwayLights.levels "beacon").
static func night_level(sun_deg: float, vis_m: float) -> float:
	return float(RunwayLights.levels(sun_deg, vis_m).beacon)
