class_name CaptainIdentify
extends RefCounted
## Identify mode of the Captain Pack map: press any button or move any axis of the pack and report which pad number it was, so the panel can
## select the matching marker (ui/menu/captain_map_panel.gd). Pure over readers (`read_axis(pad, axis) -> float`, `read_button(pad,
## button) -> bool`), so tests need no hardware. An axis counts when it has left the value it had when Identify started by AXIS_MOVE
## and is reported once per excursion (again after it came back near the start); a button when it goes down.

const AXES := 10  # Godot's JOY_AXIS_MAX
const BUTTONS := 40  # the Controls page's MAX_BUTTONS
const AXIS_MOVE := 0.3
const AXIS_BACK := 0.12

var _base := {}  # "device:axis" -> value when the mode started
var _out := {}  # "device:axis" -> true while it is away from the start and already reported
var _down := {}  # "device:button" -> was down at the last poll


## Remember the resting state of the pads (devices: device name -> pad id).
func start(devices: Dictionary, read_axis: Callable, read_button: Callable) -> void:
	_base.clear()
	_out.clear()
	_down.clear()
	for d in devices:
		for ax in AXES:
			_base["%s:%d" % [d, ax]] = float(read_axis.call(devices[d], ax))
		for bt in BUTTONS:
			_down["%s:%d" % [d, bt]] = bool(read_button.call(devices[d], bt))


## New events since the last call: [{"device", "kind": "axis" | "button", "idx"}].
func poll(devices: Dictionary, read_axis: Callable, read_button: Callable) -> Array:
	var out := []
	for d in devices:
		for ax in AXES:
			var k := "%s:%d" % [d, ax]
			var dv := absf(float(read_axis.call(devices[d], ax)) - _base.get(k, 0.0))
			if dv > AXIS_MOVE and not _out.get(k, false):
				_out[k] = true
				out.append({"device": d, "kind": "axis", "idx": ax})
			elif dv < AXIS_BACK:
				_out[k] = false
		for bt in BUTTONS:
			var kb := "%s:%d" % [d, bt]
			var now := bool(read_button.call(devices[d], bt))
			if now and not _down.get(kb, false):
				out.append({"device": d, "kind": "button", "idx": bt})
			_down[kb] = now
	return out


## Why a pad number is deliberately not on the map ("" when it is not listed): map.json `unmapped`.
static func unmapped_reason(device: String, kind: String, idx: int) -> String:
	if kind != "button":
		return ""
	for u in CaptainMap.data().get("devices", {}).get(device, {}).get("unmapped", []):
		if u.get("buttons", []).any(func(b): return int(b) == idx):  # JSON numbers are floats, `in` would not match
			return str(u.get("why", ""))
	return ""
