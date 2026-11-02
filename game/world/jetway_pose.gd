class_name JetwayPose
extends RefCounted
## Geometry of the FlightGear generic jetway (world/models/vehicles/jetway.glb) and the poses of its parts.
## Model frame: x from the terminal pivot (origin) along the tunnel, y up, z to the right; metres.
## A pose is {yaw, len, cab_yaw, pitch[, xscale]}: yaw = compass-free ENU angle of the tunnel (atan2(north, east)), len =
## pivot to the cab drum centre, cab_yaw = ENU angle the cab faces (the way the hood points), pitch = tilt about
## the terminal end (raises the cab floor to a door sill). The tunnel sections stretch (scale x), the drum, support
## and cab move rigidly, so in a docked pose the cab is never scaled and the hood ends exactly at the pose's tip.

const TIP_X := 17.01  # hood face
const DRUM_X := 14.33  # centre of the cab-end drum (the cab swings about it)
const FLOOR_Y := 3.78  # cab floor / tunnel floor above the ground
const TUN_X0 := 3.5  # the stretching tunnel sections start here (fixed rotunda ends) ...
const TUN_X1 := 13.57  # ... and end here at the unstretched pose
const MIN_LEN := 8.0  # shortest / longest drum distance a pose may have
const MAX_LEN := 70.0
const MAX_TWIST := deg_to_rad(85.0)  # a docked cab may turn this far off the tunnel direction
const CAB_LEN := TIP_X - DRUM_X


static func angle_diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


const LEGACY_LEN_M := 22.0  # the layout scaled the whole model in X by length / this, clamped:
const LEGACY_MIN := 0.6
const LEGACY_MAX := 1.8


## The rest pose: the layout the game always drew, the whole model (cab too) scaled in X by clamp(len / 22, 0.6, 1.8)
## along the way from `terminal`, so the hood stops short of a long way's end. Every jetway rests like this
## (no aircraft, an aircraft that does not dock, or one that has left); only the docked pose is exact.
## "xscale" is the extra whole-model X scale (absent = 1).
static func rest(terminal: Vector2, cab: Vector2) -> Dictionary:
	var d := cab - terminal
	var yaw := atan2(d.y, d.x)
	return {"yaw": yaw, "len": DRUM_X, "cab_yaw": yaw, "pitch": 0.0, "xscale": clampf(d.length() / LEGACY_LEN_M, LEGACY_MIN, LEGACY_MAX)}


## The pose that puts the hood face at `tip` facing along `cab_dir` (unit vector from the cab toward the aircraft);
## dy = how much higher the door sill is than the cab floor at the rest height. {} when the cab would have to
## turn more than MAX_TWIST or the tunnel leave MIN_LEN..MAX_LEN.
static func docked(terminal: Vector2, tip: Vector2, cab_dir: Vector2, dy: float) -> Dictionary:
	var drum := tip - cab_dir * CAB_LEN
	var d := drum - terminal
	var yaw := atan2(d.y, d.x)
	var cab_yaw := atan2(cab_dir.y, cab_dir.x)
	if d.length() < MIN_LEN or d.length() > MAX_LEN or absf(angle_diff(cab_yaw, yaw)) > MAX_TWIST:
		return {}
	return {"yaw": yaw, "len": d.length(), "cab_yaw": cab_yaw, "pitch": atan2(dy, d.length() + CAB_LEN)}


## Where the hood face of a pose is in the ENU plane, from its pivot.
static func tip_of(terminal: Vector2, pose: Dictionary) -> Vector2:
	var k := float(pose.get("xscale", 1.0))
	var drum := terminal + Vector2.from_angle(pose.yaw) * float(pose.len) * k
	return drum + Vector2.from_angle(pose.cab_yaw) * CAB_LEN * k


static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {"yaw": a.yaw + angle_diff(b.yaw, a.yaw) * t, "len": lerpf(a.len, b.len, t),
		"cab_yaw": a.cab_yaw + angle_diff(b.cab_yaw, a.cab_yaw) * t, "pitch": lerpf(a.pitch, b.pitch, t),
		"xscale": lerpf(float(a.get("xscale", 1.0)), float(b.get("xscale", 1.0)), t)}
