class_name CameraRig
extends Camera3D
## All flight cameras. C / Shift+C cycle, or 1-8 jump directly:
##  1 cockpit (pilot eye; right-drag look, wheel zoom, V re-centre)
##  2 chase   3 orbit (right-drag rotate, wheel distance)
##  4 free    (detached: WASD move, Q/E down/up, right-drag look, Shift fast, wheel speed)
##  5 tower   (nearest airport, auto zoom)   6 wing   7 tail   8 fly-by
## The camera follows the aircraft's interpolated render transform.

enum Mode { COCKPIT, CHASE, ORBIT, FREE, TOWER, WING, TAIL, FLYBY }
const NAMES := ["Cockpit", "Chase", "Orbit", "Free camera", "Tower", "Wing", "Tail", "Fly-by"]

var aircraft: C172Model
var airports: Array = []  # [{icao, enu Vector3}] for the tower view
var mode := Mode.CHASE
var _look := Vector2.ZERO
var _dist := 18.0
var _fov_cockpit := 70.0
## Cockpit focus zoom (Ctrl+click an item / wheel toward the cursor): eased targets and the
## view to return to on a second Ctrl+click.
var _look_goal := Vector2.ZERO
var _fov_goal := 70.0
var _focus_back := []  # [look, fov] while focused
var _chase_pos := Vector3.ZERO
var _eye := Vector3.ZERO
var _free_enu := Vector3.ZERO
var _free_speed := 40.0
var _flyby_enu := Vector3.ZERO
var _label: Label
var _label_t := 0.0


func setup(model: C172Model) -> void:
	aircraft = model
	_eye = model.cockpit.eye
	near = 0.05
	far = 160000.0
	FloatingOrigin.shifted.connect(func(d: Vector3): _chase_pos += d)
	var clouds := CloudLayer.new()
	clouds.name = "CloudLayer"
	add_child(clouds)
	var data = Paths.load_json("airports.json")
	if data:
		for a in data:
			airports.append({"icao": a.icao if a.icao != "" else a.ident, "enu": Vector3(a.x, a.y, a.elev_m)})
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_stylebox_override("normal", Notifications.card_style(Notifications.COLORS[0]))
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(Notifications.centered(_label, Control.PRESET_BOTTOM_WIDE, -76))  # brief pill above the hint line


func set_mode(m: int) -> void:
	mode = posmod(m, NAMES.size()) as Mode
	_look = Vector2.ZERO
	if mode == Mode.FREE:
		_free_enu = FloatingOrigin.to_world(global_position)
		var r := global_transform.basis.get_euler()
		_look = Vector2(r.y, r.x)
	elif mode == Mode.FLYBY:
		_place_flyby(FloatingOrigin.to_world(aircraft.global_position))
	_look_goal = _look  # focus-zoom targets follow the new view
	_fov_goal = _fov_cockpit
	_focus_back = []
	Props.set_v("view/free_cam", mode == Mode.FREE)
	Props.set_v("view/mode", NAMES[mode])
	_label.text = "%s view" % String(NAMES[mode]).capitalize()
	_label_t = 2.5


func _place_flyby(w: Vector3) -> void:
	var v: Vector3 = aircraft.fdm_node.fdm.velocity_ned()
	var ahead := Vector3(v.y, v.x, 0.0).normalized() * 250.0 if v.length() > 5.0 else Vector3(0, 60, 0)
	_flyby_enu = w + ahead + Vector3(25.0, 0.0, 6.0)


func _unhandled_input(e: InputEvent) -> void:
	if mode == Mode.COCKPIT and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.ctrl_pressed:
		_focus_toggle(e.position)
		get_viewport().set_input_as_handled()
		return
	if mode == Mode.COCKPIT and e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		if aircraft.cockpit.forward_mouse(e, self):
			get_viewport().set_input_as_handled()
			return
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_C:
			set_mode(mode + (-1 if e.shift_pressed else 1))
		elif e.keycode >= KEY_1 and e.keycode <= KEY_8 and not e.ctrl_pressed and not get_viewport().is_input_handled():
			set_mode(e.keycode - KEY_1)
		elif e.keycode == KEY_V:
			_look = Vector2.ZERO
			_fov_cockpit = 70.0
			_look_goal = _look
			_fov_goal = _fov_cockpit
			_focus_back = []
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_look += Vector2(-e.relative.x, -e.relative.y) * 0.004 * (_fov_cockpit / 70.0 if mode == Mode.COCKPIT else 1.0)
		_look.y = clampf(_look.y, -1.45, 1.45)
		_look_goal = _look
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var up: bool = e.button_index == MOUSE_BUTTON_WHEEL_UP
		match mode:
			Mode.COCKPIT:  # zoom toward whatever is under the cursor
				_fov_goal = clampf(_fov_goal * (0.85 if up else 1.18), 12.0, 95.0)
				if up:
					_look_goal = _look_goal.lerp(_look_at_screen(e.position), 0.25)
			Mode.ORBIT: _dist = clampf(_dist / 1.15 if up else _dist * 1.15, 6.0, 600.0)
			Mode.FREE: _free_speed = clampf(_free_speed * (1.25 if up else 0.8), 2.0, 3000.0)


func _process(dt: float) -> void:
	if aircraft == null:
		return
	_label_t -= dt
	_label.visible = _label_t > 0.0
	var t := aircraft.transform
	var w := FloatingOrigin.to_world(t.origin)
	match mode:
		Mode.COCKPIT:
			var k := 1.0 - exp(-10.0 * dt)  # ease toward the focus targets
			_fov_cockpit = lerpf(_fov_cockpit, _fov_goal, k)
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				_look = _look.lerp(_look_goal, k)
			fov = _fov_cockpit
			global_transform = Transform3D(t.basis * Basis.from_euler(Vector3(_look.y - 0.12, _look.x, 0.0)), t * _eye)
		Mode.CHASE:
			fov = 60.0
			var back := t.basis.z
			back.y = 0.0
			back = back.normalized() if back.length() > 0.1 else Vector3.BACK
			var target := t.origin + back * 16.0 + Vector3.UP * 4.0
			_chase_pos = _chase_pos.lerp(target, 1.0 - exp(-4.0 * dt))  # frame-rate independent follow
			if _chase_pos.distance_to(target) > 60.0:
				_chase_pos = target
			look_at_from_position(_chase_pos, t.origin + Vector3.UP)
		Mode.ORBIT:
			fov = 55.0
			var dir := Basis.from_euler(Vector3(_look.y - 0.25, _look.x + PI, 0.0)) * Vector3.FORWARD
			look_at_from_position(t.origin - dir * _dist, t.origin)
		Mode.FREE:
			fov = 65.0
			_free_fly(dt)
		Mode.TOWER:
			var p := FloatingOrigin.to_render(_nearest_tower(w))
			var d := p.distance_to(t.origin)
			fov = clampf(rad_to_deg(2.0 * atan(30.0 / maxf(d, 1.0))), 1.5, 60.0)  # keep ~60 m framed
			look_at_from_position(p, t.origin)
		Mode.WING:
			fov = 75.0
			global_transform = Transform3D(t.basis * Basis.from_euler(Vector3(-0.15 + _look.y, 0.35 + _look.x, 0.0)), t * Vector3(-5.6, 0.9, 1.6))
		Mode.TAIL:
			fov = 70.0
			global_transform = Transform3D(t.basis * Basis.from_euler(Vector3(-0.08 + _look.y, _look.x, 0.0)), t * Vector3(0.0, 2.4, 6.8))
		Mode.FLYBY:
			fov = 45.0
			var p2 := FloatingOrigin.to_render(_flyby_enu)
			if p2.distance_to(t.origin) > 450.0:
				_place_flyby(w)
				p2 = FloatingOrigin.to_render(_flyby_enu)
			look_at_from_position(p2, t.origin)


func _free_fly(dt: float) -> void:
	var b := Basis.from_euler(Vector3(_look.y, _look.x, 0.0))
	var mv := Vector3(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var d := b * mv.limit_length(1.0) * _free_speed * dt * (5.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_free_enu += Vector3(d.x, -d.z, d.y)
	var tq: TerrainQuadtree = aircraft.fdm_node._terrain
	if tq:
		_free_enu.z = maxf(_free_enu.z, tq.height_at(_free_enu.x, _free_enu.y) + 1.5)
	global_transform = Transform3D(b, FloatingOrigin.to_render(_free_enu))


func _nearest_tower(w: Vector3) -> Vector3:
	var best := Vector3(w.x + 300.0, w.y, w.z)
	var bd := INF
	for a in airports:
		var d: float = Vector2(a.enu.x, a.enu.y).distance_to(Vector2(w.x, w.y))
		if d < bd:
			bd = d
			best = a.enu + Vector3(150.0, 150.0, 30.0)  # ~200 m off the airport reference point, 30 m up
	return best


## Cockpit look angles (yaw, pitch incl. the default -0.12 tilt) that put screen point p centre.
func _look_at_screen(p: Vector2) -> Vector2:
	var d: Vector3 = aircraft.transform.basis.inverse() * project_ray_normal(p)
	return Vector2(atan2(-d.x, -d.z), clampf(asin(clampf(d.y, -1.0, 1.0)) + 0.12, -1.45, 1.45))


## Ctrl+click: zoom in on the item under the cursor; Ctrl+click again returns to the old view.
func _focus_toggle(p: Vector2) -> void:
	if _focus_back.is_empty():
		_focus_back = [_look_goal, _fov_goal]
		_look_goal = _look_at_screen(p)
		_fov_goal = 18.0
	else:
		_look_goal = _focus_back[0]
		_fov_goal = _focus_back[1]
		_focus_back = []
