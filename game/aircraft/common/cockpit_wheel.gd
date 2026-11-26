class_name CockpitWheel
extends RefCounted
## The mouse wheel (or a trackpad scroll) over a cockpit knob turns it, in cockpit view: one detent per wheel notch,
## up = more, with the same detent, range, wrap and ALT 100 / 1000 rules as dragging that knob (CockpitKnob.value_after;
## a knob with `when_on` works on its other fields, as in CockpitKnob.active). CameraRig asks first; when the pointer is
## not on a knob (or is over a glass display or a menu) nothing happens here and the wheel zooms as before. A pinch always zooms.
## Trackpad scroll adds up: PAN_PER_STEP points of scroll (what the zoom counts as one step) is one detent.

const PAN_PER_STEP := 12.0
const MAX_STEPS := 3  # detents one scroll event can turn (a flick)

static var _acc := 0.0  # trackpad scroll not yet worth a detent


## Detents the event is worth (+ = up = more): a wheel notch is 1, scroll accumulates, anything else 0.
static func detents(e: InputEvent) -> int:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return 1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -1
	if e is InputEventPanGesture:
		_acc += -e.delta.y / PAN_PER_STEP
		var n := clampi(int(_acc), -MAX_STEPS, MAX_STEPS)
		_acc = clampf(_acc - float(int(_acc)), -1.0, 1.0)
		return n
	return 0


## The knob under the ray, {} when the closest control there is not a knob.
static func knob_at(items: Array, from: Vector3, dir: Vector3) -> Dictionary:
	var it := CockpitPick.lookup(items, from, dir)
	return it if not it.is_empty() and CockpitPick.kind(it) == "knob" else {}


## Move `item` (a knob) `n` detents; the value written is the one a drag of n detents writes.
static func step(item: Dictionary, n: int) -> void:
	var a := CockpitKnob.active(item)
	if n != 0 and str(a.get("drive", "")) != "":
		Props.set_v(str(a.drive), CockpitKnob.value_after(a, CockpitKnob.current(a), n))


## A wheel / scroll event in cockpit view: true (and the event handled) when it was over a knob.
static func turn(e: InputEvent, cam: Camera3D, cockpit: Cockpit) -> bool:
	if cockpit == null or cockpit.levers == null or not cam.is_inside_tree():
		return false
	if not (e is InputEventPanGesture or (e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN])):
		return false
	var at: Vector2 = e.position
	if cockpit.hits_glass(cam, at) or CockpitPick.gui_blocks(cam.get_viewport()):
		return false
	var it := knob_at(cockpit.lever_items(), cam.project_ray_origin(at), cam.project_ray_normal(at))
	if it.is_empty():
		_acc = 0.0
		return false
	step(it, detents(e))
	cam.get_viewport().set_input_as_handled()
	return true
