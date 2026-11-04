class_name JetwayPose
extends RefCounted
## Geometry of the FlightGear generic jetway (world/models/vehicles/jetway.glb) and the poses of its parts.
## Model frame: x along the tunnel, y up, z to the right; metres. The rig's origin (the rotunda node of the
## jet-bridge network, tools/jetway_net.py) is the rotunda column at model x = PIVOT_X: the tunnel turns and
## tilts about it, the rotunda itself (Rotunda1: column, room and the fixed stub reaching STUB_X behind it) stays put.
## A pose is {yaw, len, cab_yaw, pitch}: yaw = compass-free ENU angle of the tunnel (atan2(north, east)), len =
## rotunda column to the cab drum centre, cab_yaw = ENU angle the cab faces (the way the hood points), pitch = tilt
## about the rotunda (raises the cab floor to a door sill). The tunnel sections stretch (scale x); the drum, support
## and cab move rigidly and are never scaled, so the hood ends exactly at the pose's tip.

const TIP_X := 17.01  # hood face
const DRUM_X := 14.33  # centre of the cab-end drum (the cab swings about it)
const PIVOT_X := 2.04  # the rotunda column (Rotunda1's column is 1.68..2.40)
const STUB_X := -5.24  # Rotunda1's fixed stub ends here (7.28 m behind the column: tools/jetway_net.py STUB_M)
const FLOOR_Y := 3.78  # cab floor / tunnel floor above the ground
const TOP_Y := 6.67  # tunnel roof (top of the support girder)
const TUN_X0 := 3.5  # the stretching tunnel sections start here (fixed rotunda ends) ...
const TUN_X1 := 13.57  # ... and end here at the unstretched pose
const SUPPORT_X := 11.65  # the wheel support (Support, SupportGirder) hangs here at the unstretched pose
const MIN_LEN := 8.0  # shortest / longest drum distance a pose may have
const MAX_LEN := 70.0
const MAX_TWIST := deg_to_rad(85.0)  # a docked cab may turn this far off the tunnel direction
const CAB_LEN := TIP_X - DRUM_X
const LEN0 := DRUM_X - PIVOT_X  # drum distance of the unstretched model
const REST_BACK_M := 5.0  # at rest the hood stops this far short of the cab end OSM draws (clear of the taxilane behind)


static func angle_diff(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)


## The rest pose: straight along the movable bridge, the hood REST_BACK_M short of the drawn cab end (no aircraft,
## an aircraft that does not dock, or one that has left).
static func rest(rot: Vector2, cab: Vector2) -> Dictionary:
	var d := cab - rot
	var yaw := atan2(d.y, d.x)
	return {"yaw": yaw, "len": clampf(d.length() - CAB_LEN - REST_BACK_M, MIN_LEN, MAX_LEN), "cab_yaw": yaw, "pitch": 0.0}


## The pose that puts the hood face at `tip` facing along `cab_dir` (unit vector from the cab toward the aircraft);
## dy = how much higher the door sill is than the cab floor at the rest height. {} when the cab would have to
## turn more than MAX_TWIST or the tunnel leave MIN_LEN..MAX_LEN.
static func docked(rot: Vector2, tip: Vector2, cab_dir: Vector2, dy: float) -> Dictionary:
	var drum := tip - cab_dir * CAB_LEN
	var d := drum - rot
	var yaw := atan2(d.y, d.x)
	var cab_yaw := atan2(cab_dir.y, cab_dir.x)
	if d.length() < MIN_LEN or d.length() > MAX_LEN or absf(angle_diff(cab_yaw, yaw)) > MAX_TWIST:
		return {}
	return {"yaw": yaw, "len": d.length(), "cab_yaw": cab_yaw, "pitch": atan2(dy, d.length() + CAB_LEN)}


## Where the hood face of a pose is in the ENU plane, from the rotunda (pitch ignored: a few cm).
static func tip_of(rot: Vector2, pose: Dictionary) -> Vector2:
	var drum := rot + Vector2.from_angle(pose.yaw) * float(pose.len)
	return drum + Vector2.from_angle(pose.cab_yaw) * CAB_LEN


static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {"yaw": a.yaw + angle_diff(b.yaw, a.yaw) * t, "len": lerpf(a.len, b.len, t),
		"cab_yaw": a.cab_yaw + angle_diff(b.cab_yaw, a.cab_yaw) * t, "pitch": lerpf(a.pitch, b.pitch, t)}
