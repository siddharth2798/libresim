extends RefCounted
## Lever calibration (lo / hi), pad matching by name, and the Thrustmaster Captain Pack
## profile (core/input_profiles.gd) on Linux and macOS. No hardware needed.

const TMP := "user://test_captain_pack.json"
const SIDESTICK := {"id": 0, "name": "Thrustmaster TCA Sidestick Airbus Edition", "guid": "g-stick"}
const QUADRANT := {"id": 1, "name": "TCA Quadrant Airbus Edition", "guid": "g-quad"}


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
	if InputBindings.pick_device({"name": "QUADRANT"}, pads) != 1:
		return "name match is case-sensitive"
	if InputBindings.pick_device({"name": "quadrant", "guid": "g-stick"}, pads) != 0:
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
			if d[a].name != "quadrant" or d[a].axis < 0 or d[a].range != "half":
				return "%s: %s should be a half-range quadrant lever" % [os_name, a]
		if d.pitch.get("invert", false):
			return "%s: pitch must not be inverted" % os_name
		if d.brake_left.axis != -1 or d.starter.button != -1:
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
	if r.throttle.name != "quadrant" or not _near(r.throttle.lo, -0.35) or not _near(r.throttle.hi, 0.9):
		return "name / calibration lost on save and load"
	if typeof(r.roll.axis) != TYPE_INT or typeof(r.brakes.button) != TYPE_INT:
		return "indices not int after load"
	return ""
