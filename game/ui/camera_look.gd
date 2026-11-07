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
const FOV_MIN := 12.0
const FOV_MAX := 95.0


## Wheel, trackpad scroll, or pinch. A mouse wheel click is a button. A trackpad or Magic Mouse
## scroll has a gesture phase, so macOS sends a pan and no wheel button. Pan delta.y is the
## negated scroll delta: negative is the same direction as wheel up.
static func is_zoom(e: InputEvent) -> bool:
	if e is InputEventMagnifyGesture:
		return e.factor > 0.0
	if e is InputEventPanGesture:
		return absf(e.delta.y) > 0.01
	return e is InputEventMouseButton and e.pressed \
			and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]


## Narrower field of view is zoomed in. One wheel notch, or about 12 points of scroll, is one step.
static func zoom_fov(fov: float, e: InputEvent) -> float:
	if e is InputEventMagnifyGesture:
		return clampf(fov / e.factor, FOV_MIN, FOV_MAX)
	if e is InputEventPanGesture:
		return _steps(fov, -e.delta.y / 12.0)
	if e is InputEventMouseButton:
		return _steps(fov, 1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
	return fov


static func _steps(fov: float, steps: float) -> float:
	steps = clampf(steps, -2.5, 2.5)
	if absf(steps) < 0.001:
		return fov
	var f := pow(0.85, steps) if steps > 0.0 else pow(1.18, -steps)
	return clampf(fov * f, FOV_MIN, FOV_MAX)


static func drag(look: Vector2, relative: Vector2, sens_scale: float) -> Vector2:
	var n := look + Vector2(-relative.x, -relative.y) * SENS * sens_scale
	n.y = clampf(n.y, PITCH_MIN, PITCH_MAX)
	return n


## Stored cockpit offset that centres `dir_local` (aircraft frame; the camera looks along -Z).
static func aim_at(dir_local: Vector3) -> Vector2:
	var pitch := asin(clampf(dir_local.y, -1.0, 1.0)) + 0.12
	return Vector2(atan2(-dir_local.x, -dir_local.z), clampf(pitch, PITCH_MIN, PITCH_MAX))
