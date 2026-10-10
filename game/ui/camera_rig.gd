class_name CameraRig
extends Camera3D
## Flight cameras, cycled with C: cockpit (pilot eyepoint), chase (behind,
## smoothed), orbit (right-mouse drag to rotate, wheel to zoom).
## In cockpit view, right-mouse drag looks around; V re-centres the view.

enum Mode { COCKPIT, CHASE, ORBIT }

var aircraft: C172Model
var mode := Mode.CHASE
var _look := Vector2.ZERO  # yaw, pitch offsets (cockpit / orbit)
var _dist := 18.0
var _chase_pos := Vector3.ZERO
var _eye := Vector3.ZERO


func setup(model: C172Model) -> void:
	aircraft = model
	var e: Array = model.fdm_node.fdm.cfg.metrics.eyepoint_m
	_eye = model._s(Vector3(e[0], e[1], e[2]))
	near = 0.1
	far = 160000.0
	FloatingOrigin.shifted.connect(func(d: Vector3): _chase_pos += d)


func _unhandled_input(e: InputEvent) -> void:
	if mode == Mode.COCKPIT and e is InputEventMouseButton and e.button_index != MOUSE_BUTTON_RIGHT:
		if aircraft.cockpit.forward_mouse(e, self):
			get_viewport().set_input_as_handled()
			return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_C:
			mode = (mode + 1) % 3 as Mode
			_look = Vector2.ZERO
		elif e.keycode == KEY_V:
			_look = Vector2.ZERO
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look += Vector2(-e.relative.x, -e.relative.y) * 0.004
		_look.y = clampf(_look.y, -1.4, 1.4)
	elif e is InputEventMouseButton and e.pressed and mode == Mode.ORBIT:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist / 1.15, 6.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.15, 400.0)


func _process(dt: float) -> void:
	if aircraft == null:
		return
	var t := aircraft.transform
	match mode:
		Mode.COCKPIT:
			fov = 70.0
			var b := t.basis * Basis.from_euler(Vector3(_look.y - 0.08, _look.x, 0.0))
			global_transform = Transform3D(b, t * _eye)
		Mode.CHASE:
			fov = 60.0
			var back := t.basis.z
			back.y = 0.0
			back = back.normalized() if back.length() > 0.1 else Vector3.BACK
			var target := t.origin + back * 16.0 + Vector3.UP * 4.0
			_chase_pos = _chase_pos.lerp(target, clampf(dt * 4.0, 0.0, 1.0))
			if _chase_pos.distance_to(target) > 60.0:
				_chase_pos = target
			look_at_from_position(_chase_pos, t.origin + Vector3.UP * 1.0)
		Mode.ORBIT:
			fov = 55.0
			var dir := Basis.from_euler(Vector3(_look.y - 0.25, _look.x + PI, 0.0)) * Vector3.FORWARD
			look_at_from_position(t.origin - dir * _dist, t.origin)
