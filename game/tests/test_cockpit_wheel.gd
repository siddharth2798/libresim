extends "res://tests/fcu_panel_base.gd"
## The mouse wheel over a 3D cockpit knob (aircraft/common/cockpit_wheel.gd, CameraRig): one detent per notch, up = more, with
## the drag's rules (ALT 100 / 1000 selector, heading wrap, range); the view does not zoom. Over anything else (empty panel, a
## pushbutton, the sky) the wheel zooms as before. A pinch always zooms. A real CameraRig looks at the A320 interior from the seat.

var _root: Node3D
var _lv: CockpitLevers
var _cam: CameraRig


func teardown() -> void:
	super.teardown()
	if _cam != null:
		var model := _cam.aircraft
		var cockpit := model.cockpit
		_cam.aircraft = null
		_cam.free()
		_cam = null
		cockpit.free()  # the stand-ins were never in the tree
		model.free()
	if _root != null:
		_root.free()
		_root = null


func _rig() -> void:
	_begin()
	_root = Node3D.new()
	add_child(_root)
	var glb: Node3D = (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()
	_root.add_child(glb)
	_lv = CockpitLevers.new()
	_root.add_child(_lv)
	_lv.build(glb, AircraftDef.load_def("a320").section("cockpit").levers)
	_cam = CameraRig.new()
	_root.add_child(_cam)
	_cam.mode = CameraRig.Mode.COCKPIT
	_cam.aircraft = AircraftModel.new()  # only its cockpit is used here
	_cam.aircraft.cockpit = Cockpit.new()
	_cam.aircraft.cockpit.levers = _lv
	_cam._fov_goal = 70.0
	_cam._fov_cockpit = 70.0


func _lever(name: String) -> Dictionary:
	for it in _lv._items:
		if str((it.node as Node).name) == "pivot_" + name:
			return it
	return {}


## Look from the seat at the middle of control `name`; the pointer at the middle of the screen is then on it.
func _look_at(name: String) -> Vector2:
	var it := _lever(name)
	var meshes := CockpitPickHit.owned_meshes(it.node)
	var at := (it.node as Node3D).global_position
	if not meshes.is_empty():
		var box := AABB()
		for i in meshes.size():
			var mi := meshes[i] as MeshInstance3D
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if i == 0 else box.merge(b)
		at = box.get_center()
	_cam.look_at_from_position(Vector3(-16.25, 0.52, 0.5 if at.z > -0.1 else -0.5), at)
	return get_viewport().get_visible_rect().size * 0.5


func _notch(at: Vector2, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = at
	_cam._unhandled_input(e)


func test_the_wheel_turns_the_knob_under_the_pointer_and_does_not_zoom() -> String:
	_rig()
	Props.set_v("controls/fcu/hdg_deg", 90.0)
	var at := _look_at("hdg_sel")
	_notch(at, true)
	_notch(at, true)
	_notch(at, true)
	if Props.get_f("controls/fcu/hdg_deg") != 93.0:
		return "three notches up from 90 should read 93, got %s" % Props.get_f("controls/fcu/hdg_deg")
	_notch(at, false)
	if Props.get_f("controls/fcu/hdg_deg") != 92.0:
		return "a notch down should read 92, got %s" % Props.get_f("controls/fcu/hdg_deg")
	if _cam._fov_goal != 70.0:
		return "the view zoomed (%s) while the wheel turned a knob" % _cam._fov_goal
	Props.set_v("controls/fcu/hdg_deg", 359.0)
	_notch(at, true)
	return "" if Props.get_f("controls/fcu/hdg_deg") == 0.0 else "heading should wrap 359 -> 0, got %s" % Props.get_f("controls/fcu/hdg_deg")


func test_the_wheel_follows_each_knobs_own_step_range_and_the_alt_selector() -> String:
	_rig()
	Props.set_v("controls/fcu/alt_inc_1000", false)
	Props.set_v("controls/fcu/alt_ft", 10000.0)
	var alt := _look_at("alt_sel")
	_notch(alt, true)
	if Props.get_f("controls/fcu/alt_ft") != 10100.0:
		return "ALT, 100 selector: %s" % Props.get_f("controls/fcu/alt_ft")
	Props.set_v("controls/fcu/alt_inc_1000", true)
	_notch(alt, true)
	if Props.get_f("controls/fcu/alt_ft") != 11000.0:
		return "ALT, 1000 selector from 10100 should land on 11000, got %s" % Props.get_f("controls/fcu/alt_ft")
	_notch(alt, false)
	if Props.get_f("controls/fcu/alt_ft") != 10000.0:
		return "ALT, 1000 selector down: %s" % Props.get_f("controls/fcu/alt_ft")
	Props.set_v("controls/fcu/vs_fpm", 0.0)
	_notch(_look_at("vs_sel"), false)
	if Props.get_f("controls/fcu/vs_fpm") != -100.0:
		return "V/S down one detent: %s" % Props.get_f("controls/fcu/vs_fpm")
	Props.set_v("controls/fcu/spd_mach", false)
	Props.set_v("controls/fcu/spd_kt", 250.0)
	_notch(_look_at("spd_sel"), true)
	if Props.get_f("controls/fcu/spd_kt") != 251.0:
		return "SPD up one detent: %s" % Props.get_f("controls/fcu/spd_kt")
	Props.set_v("controls/fcu/spd_kt", 399.0)
	_notch(_look_at("spd_sel"), true)
	return "" if Props.get_f("controls/fcu/spd_kt") == 399.0 else "SPD stops at its top: %s" % Props.get_f("controls/fcu/spd_kt")


func test_the_wheel_over_anything_but_a_knob_zooms_as_before() -> String:
	_rig()
	Props.set_v("controls/fcu/hdg_deg", 90.0)
	Props.set_v("controls/fcu/ap1", false)
	_notch(_look_at("ap1"), true)  # a pushbutton: the wheel does not press it
	if Props.get_b("controls/fcu/ap1") or _cam._fov_goal >= 70.0:
		return "wheel over AP1: pressed %s, fov goal %s (should zoom in)" % [Props.get_b("controls/fcu/ap1"), _cam._fov_goal]
	_cam._fov_goal = 70.0
	_cam.look_at_from_position(Vector3(-16.25, 0.52, 0.5), Vector3(-16.25, 0.52, 40.0))  # the ceiling far above every control
	_notch(get_viewport().get_visible_rect().size * 0.5, true)
	if _cam._fov_goal >= 70.0:
		return "wheel over empty space should zoom, fov goal %s" % _cam._fov_goal
	_notch(get_viewport().get_visible_rect().size * 0.5, false)
	if Props.get_f("controls/fcu/hdg_deg") != 90.0:
		return "no knob was under the pointer but the heading moved"
	_cam._fov_goal = 70.0
	var pinch := InputEventMagnifyGesture.new()  # a pinch over a knob still zooms
	pinch.factor = 1.4
	pinch.position = _look_at("hdg_sel")
	_cam._unhandled_input(pinch)
	return "" if _cam._fov_goal < 70.0 and Props.get_f("controls/fcu/hdg_deg") == 90.0 else "pinch over a knob: fov %s heading %s" % [_cam._fov_goal, Props.get_f("controls/fcu/hdg_deg")]


func test_trackpad_scroll_over_a_knob_adds_up_to_detents() -> String:
	_rig()
	Props.set_v("controls/fcu/hdg_deg", 90.0)
	var at := _look_at("hdg_sel")
	CockpitWheel._acc = 0.0
	for d in [-6.0, -6.0, -12.0, 12.0]:  # up half, up half (one detent: 91), up one (92), down one (91)
		var pan := InputEventPanGesture.new()
		pan.position = at
		pan.delta = Vector2(0, d)
		_cam._unhandled_input(pan)
	if Props.get_f("controls/fcu/hdg_deg") != 91.0:
		return "scroll over HDG should net +1 detent, got %s" % Props.get_f("controls/fcu/hdg_deg")
	return "" if _cam._fov_goal == 70.0 else "scroll over a knob zoomed the view: %s" % _cam._fov_goal


func test_the_pointer_over_a_menu_keeps_the_wheel_for_the_menu() -> String:
	_rig()
	Props.set_v("controls/fcu/hdg_deg", 90.0)
	Props.set_v("ui/pause_open", true)
	var at := _look_at("hdg_sel")
	_notch(at, true)
	Props.set_v("ui/pause_open", false)
	return "" if Props.get_f("controls/fcu/hdg_deg") == 90.0 else "the pause screen was open and the knob turned"
