extends Node
## Cockpit zoom. A mouse wheel is a button. A trackpad scroll is a pan and sends no wheel event.


func test_trackpad_scroll_and_pinch_zoom_the_cockpit() -> String:
	var cam := CameraRig.new()
	cam.mode = CameraRig.Mode.COCKPIT
	cam._fov_goal = 70.0
	var up := InputEventPanGesture.new()
	up.delta = Vector2(0, -12)
	cam._unhandled_input(up)
	if cam._fov_goal > 60.0:
		return "scroll up should narrow the field, got %.1f" % cam._fov_goal
	var wide := cam._fov_goal
	var down := InputEventPanGesture.new()
	down.delta = Vector2(0, 12)
	cam._unhandled_input(down)
	if cam._fov_goal <= wide:
		return "scroll down should widen it, %.1f from %.1f" % [cam._fov_goal, wide]
	var before := cam._fov_goal
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.4
	cam._unhandled_input(pinch)
	if cam._fov_goal >= before - 0.5:
		return "pinch apart should zoom in, %.1f from %.1f" % [cam._fov_goal, before]
	cam._fov_goal = 70.0
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	cam._unhandled_input(wheel)
	if absf(cam._fov_goal - 59.5) > 0.05:
		return "wheel up should be 59.5, got %.2f" % cam._fov_goal
	cam.free()
	return ""
