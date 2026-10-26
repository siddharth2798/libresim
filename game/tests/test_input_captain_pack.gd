extends RefCounted
## Lever calibration (lo / hi), pad matching by name, and the Thrustmaster Captain Pack
## profile (core/input_profiles.gd) on Linux and macOS. No hardware needed.

const TMP := "user://test_captain_pack.json"
const SIDESTICK := {"id": 0, "name": "Thrustmaster TCA Sidestick X Copilot", "guid": "g-stick"}
const QUADRANT := {"id": 1, "name": "Thrustmaster TCA Q-Eng 1&2", "guid": "g-quad"}


func _near(a: float, b: float, tol := 1e-4) -> bool:
	return absf(a - b) <= tol


func test_captain_cal_half_lever() -> String:
	# idle detent at raw -0.4, full at 0.8; the reverse zone below idle reads as idle
	var b := {"range": "half", "deadzone": 0.0, "expo": 0.0, "lo": -0.4, "hi": 0.8}
	for p in [[-1.0, 0.0], [-0.4, 0.0], [0.2, 0.5], [0.8, 1.0], [1.0, 1.0]]:
		if not _near(InputBindings.shape(p[0], b), p[1]):
			return "half cal %f -> %f, want %f" % [p[0], InputBindings.shape(p[0], b), p[1]]
	b.lo = 0.8  # a lever that reads high at idle: lo > hi
	b.hi = -0.4
	if not _near(InputBindings.shape(0.8, b), 0.0) or not _near(InputBindings.shape(-0.4, b), 1.0) \
			or not _near(InputBindings.shape(0.2, b), 0.5):
		return "reversed calibration wrong"
	b.invert = true
	if not _near(InputBindings.shape(0.8, b), 1.0):
		return "invert after calibration wrong"
	return ""


func test_captain_cal_full_and_defaults() -> String:
	var b := {"range": "full", "deadzone": 0.0, "expo": 0.0, "lo": -0.5, "hi": 0.5}
	if not _near(InputBindings.shape(0.5, b), 1.0) or not _near(InputBindings.shape(0.0, b), 0.0) \
			or not _near(InputBindings.shape(-0.9, b), -1.0):
		return "full calibration wrong"
	var plain := {"range": "full", "deadzone": 0.0, "expo": 0.0}
	if not _near(InputBindings.shape(0.3, plain), 0.3):
		return "uncalibrated full changed"
	var t := {"range": "trigger", "deadzone": 0.0, "expo": 0.0}
	if not _near(InputBindings.shape(0.6, t), 0.6) or InputBindings.shape(-0.5, t) != 0.0:
		return "uncalibrated trigger changed"
	var collapsed := {"range": "half", "deadzone": 0.0, "expo": 0.0, "lo": 0.3, "hi": 0.3}
	if not _near(InputBindings.shape(0.0, collapsed), 0.5):
		return "collapsed lo == hi should fall back to the natural range"
	return ""


func test_captain_pick_device() -> String:
	var pads := [SIDESTICK, QUADRANT]
	if InputBindings.pick_device({"name": "sidestick", "device": 5}, pads) != 0:
		return "name match missed the sidestick"
	if InputBindings.pick_device({"name": "Q-ENG"}, pads) != 1:
		return "name match is case-sensitive"
	if InputBindings.pick_device({"name": "q-eng", "guid": "g-stick"}, pads) != 0:
		return "guid should win over name"
	if InputBindings.pick_device({"name": "sidestick", "device": 0}, [QUADRANT]) != -1:
		return "unplugged named pad must not fall back to another pad's index"
	if InputBindings.pick_device({"device": 1}, pads) != 1 or InputBindings.pick_device({"device": 3}, pads) != -1:
		return "index fallback wrong"
	if InputBindings.pick_device({"guid": "gone", "device": 1}, pads) != 1:
		return "missing guid should fall back to the index"
	return ""


func test_captain_profile_per_os() -> String:
	for os_name in ["Linux", "macOS", "Windows"]:
		var d := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, os_name)
		for a in InputBindings.AXES.keys() + InputBindings.BUTTONS:
			if not d.has(a):
				return "%s: missing %s" % [os_name, a]
		for a in ["roll", "pitch", "yaw", "brakes", "flaps_up", "flaps_down"]:
			if d[a].name != "sidestick" or InputBindings.describe(d[a]) == "—":
				return "%s: %s should be on the sidestick" % [os_name, a]
		for a in ["throttle", "mixture"]:
			if d[a].name != "q-eng" or d[a].axis < 0 or d[a].range != "half":
				return "%s: %s should be a half-range quadrant lever" % [os_name, a]
		if d.throttle.lo >= d.throttle.hi or d.mixture.axis == d.throttle.axis:
			return "%s: throttle needs a calibration and its own lever" % os_name
		for a in ["starter", "parking_brake_switch", "magnetos_switch"]:
			if d[a].name != "q-eng" or d[a].button < 0:
				return "%s: %s should be a quadrant switch" % [os_name, a]
		if d.starter.button == d.magnetos_switch.button or d.trim_up.button == d.trim_down.button:
			return "%s: two actions share a button" % os_name
		if d.pitch.get("invert", false):
			return "%s: pitch must not be inverted" % os_name
		if d.brake_left.axis != -1 or d.magnetos_next.button != -1:
			return "%s: unlisted actions should stay unbound" % os_name
		var swapped := [SIDESTICK.merged({"id": 1}, true), QUADRANT.merged({"id": 0}, true)]  # plug-in order must not matter
		if InputBindings.pick_device(d.roll, swapped) != 1 or InputBindings.pick_device(d.throttle, swapped) != 0:
			return "%s: profile did not resolve to the right pads" % os_name
	return ""


func test_captain_profile_os_overrides() -> String:
	var base := InputProfiles.captain_pack("Linux")
	var over := {"macOS": {InputProfiles.CAPTAIN_PACK: {
		"sidestick": {"axes": {"yaw": {"axis": 5}}, "buttons": {"brakes": 7}},
		"quadrant": {"axes": {"mixture": {"axis": 3}}}}}}
	var mac := InputProfiles.captain_pack("macOS", over)
	var lin := InputProfiles.captain_pack("Linux", over)
	if mac.yaw.axis != 5 or mac.brakes.button != 7 or mac.mixture.axis != 3:
		return "macOS override not applied"
	if mac.yaw.deadzone != base.yaw.deadzone or mac.roll.axis != base.roll.axis:
		return "override must only replace the named fields"
	if lin.yaw.axis != base.yaw.axis or lin.brakes.button != base.brakes.button:
		return "macOS override leaked into Linux"
	return ""


func test_captain_profile_roundtrip() -> String:
	var t := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "Linux")
	t.throttle.lo = -0.35
	t.throttle.hi = 0.9
	if not InputBindings.save_to(t, TMP):
		return "save failed"
	var r := InputBindings.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if r.throttle.name != "q-eng" or not _near(r.throttle.lo, -0.35) or not _near(r.throttle.hi, 0.9):
		return "name / calibration lost on save and load"
	if typeof(r.roll.axis) != TYPE_INT or typeof(r.brakes.button) != TYPE_INT:
		return "indices not int after load"
	return ""


func test_captain_detents_and_flaps_lever() -> String:
	var d: Array = InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK].quadrant.axes.flaps_lever.detents
	for p in [[-1.0, 0], [-0.9, 0], [-0.49, 1], [-0.3, 1], [-0.06, 2], [0.1, 2], [0.44, 3], [0.7, 3], [0.75, 4], [1.0, 4], [5.0, 4]]:
		if InputBindings.detent_index(p[0], d) != p[1]:
			return "raw %f -> notch %d, want %d" % [p[0], InputBindings.detent_index(p[0], d), p[1]]
	if InputBindings.detent_index(0.3, []) != 0:
		return "empty detent list should give notch 0"
	var j := JoystickControls.new()
	Props.set_v("controls/flaps", 0)
	j.flap_notch(0)  # first read only records the lever, so the sim's setting is untouched
	Props.set_v("controls/flaps", 2)
	j.flap_notch(0)
	var untouched: int = Props.get_v("controls/flaps")
	j.flap_notch(1)
	var one: int = Props.get_v("controls/flaps")
	j.flap_notch(3)
	var three: int = Props.get_v("controls/flaps")
	Props.set_v("controls/flaps", 0)
	j.free()
	if untouched != 2:
		return "an unchanged lever overwrote the flaps"
	return "" if one == 1 and three == 3 else "lever move did not set flaps: %d, %d" % [one, three]


func test_captain_level_switches() -> String:
	var j := JoystickControls.new()
	Props.set_v("controls/parking_brake", false)
	Props.set_v("controls/magnetos", 3)
	j._level("parking_brake_switch", true)
	var on := Props.get_b("controls/parking_brake")
	j._level("parking_brake_switch", false)
	var off := not Props.get_b("controls/parking_brake")
	j._level("magnetos_switch", false)
	var mag_off: int = Props.get_v("controls/magnetos")
	j._level("magnetos_switch", true)
	var mag_on: int = Props.get_v("controls/magnetos")
	j.free()
	if not on or not off:
		return "parking brake switch does not follow the switch"
	return "" if mag_off == 0 and mag_on == 3 else "magnetos switch: OFF %d, BOTH %d" % [mag_off, mag_on]


func test_captain_throttle_calibrated() -> String:
	var t := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "macOS")
	# lever 1 rests at the idle detent (raw -0.51), reverse is below it, TOGA at +1
	for p in [[-1.0, 0.0], [-0.51, 0.0], [-0.48, 0.0], [1.0, 1.0]]:
		if InputBindings.shape(p[0], t.throttle) != p[1]:
			return "throttle raw %f -> %f, want %f" % [p[0], InputBindings.shape(p[0], t.throttle), p[1]]
	if InputBindings.shape(0.26, t.throttle) < 0.4 or InputBindings.shape(0.26, t.throttle) > 0.6:
		return "throttle mid-travel should be about half: %f" % InputBindings.shape(0.26, t.throttle)
	return ""


func test_captain_lever_ignored_until_it_reports() -> String:
	var j := JoystickControls.new()
	if not j._reported(0, 0, 0.0) == false:
		return "an unreported lever (raw exactly 0) counted as live"
	if not j._reported(0, 0, -0.51):
		return "a moved lever did not count as live"
	if not j._reported(0, 0, 0.0):
		return "a lever that has reported must stay live at 0"
	if j._reported(0, 1, 0.0):
		return "readiness leaked between axes"
	j._on_joy_connection(0, false)  # a re-plug starts again
	var again := j._reported(0, 0, 0.0)
	j.free()
	return "" if not again else "re-plug did not reset lever readiness"


func test_captain_mixture_never_cut_at_rest() -> String:
	var t := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "macOS")
	# the speed brake lever rests at RET (raw -1): that must be full rich, not cutoff
	if not _near(InputBindings.shape(-1.0, t.mixture), 1.0):
		return "mixture at the lever's rest end is %f, want 1 (rich)" % InputBindings.shape(-1.0, t.mixture)
	if InputBindings.shape(1.0, t.mixture) != 0.0:
		return "pulling the lever fully back should lean to cutoff"
	if t.mixture.axis == 1:
		return "mixture is bound to throttle lever 2 (its idle detent would cut the engine)"
	return ""
