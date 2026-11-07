class_name CameraLook
extends RefCounted
## Mouse-look offset (yaw, pitch) shared by the flight cameras. Cockpit rest pose is a further
## -0.12 rad of pitch applied by CameraRig; it is not part of this offset, so the seated view stays put.
## Stored pitch runs from PITCH_MIN to PITCH_MAX. With the -0.12 bias that is camera pitch
## -1.57 rad (-90 deg, pedestal and the floor under the eye) to +1.50 rad (+86 deg).
## The old symmetric ±1.45 stopped the camera at +76 deg. From the A320 design eye the top of the
## overhead is about +71 deg and slightly aft, so that stop left the panel against the limit.

const SENS := 0.004
const PITCH_MIN := -1.45
const PITCH_MAX := 1.62


static func drag(look: Vector2, relative: Vector2, sens_scale: float) -> Vector2:
	var n := look + Vector2(-relative.x, -relative.y) * SENS * sens_scale
	n.y = clampf(n.y, PITCH_MIN, PITCH_MAX)
	return n


## Stored cockpit offset that centres `dir_local` (aircraft frame; the camera looks along -Z).
static func aim_at(dir_local: Vector3) -> Vector2:
	var pitch := asin(clampf(dir_local.y, -1.0, 1.0)) + 0.12
	return Vector2(atan2(-dir_local.x, -dir_local.z), clampf(pitch, PITCH_MIN, PITCH_MAX))
