extends RefCounted
## Lever calibration (lo / hi), pad matching by name, and the Thrustmaster Captain Pack
## profile (core/input_profiles.gd) on Linux and macOS. No hardware needed.

const TMP := "user://test_captain_pack.json"
const FX := preload("res://tests/generic_fixtures.gd")
const SIDESTICK := {"id": 0, "name": "Thrustmaster TCA Sidestick X Copilot", "guid": "g-stick"}
const QUADRANT := {"id": 1, "name": "Thrustmaster TCA Q-Eng 1&2", "guid": "g-quad"}
const JET_GROUPS := ["throttle", "trim", "flaps", "brakes", "parking_brake", "thrust_levers", "reverse",
	"speedbrake", "engine_master", "engine_mode"]


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
		for a in ["throttle", "mixture", "speedbrake"]:
			if d[a].name != "q-eng" or d[a].axis < 0 or d[a].range != "half":
				return "%s: %s should be a half-range quadrant lever" % [os_name, a]
		if absf(d.throttle.lo - d.throttle.hi) < 0.5 or d.mixture.axis == d.throttle.axis or d.throttle_2.axis == d.throttle.axis:
			return "%s: each thrust lever needs a calibration and its own axis" % os_name
		if d.throttle.lo <= d.throttle.hi or d.throttle.rev <= d.throttle.lo or d.throttle_2.name != "q-eng":
			return "%s: the quadrant levers read falling when pushed forward, reverse is behind idle" % os_name
		for a in ["starter", "parking_brake_switch", "magnetos_switch", "engine_master_1_switch", "engine_master_2_switch"]:
			if d[a].name != "q-eng" or d[a].button < 0:
				return "%s: %s should be a quadrant switch" % [os_name, a]
		if d.starter.button == d.magnetos_switch.button or d.trim_up.button == d.trim_down.button:
			return "%s: two actions share a button" % os_name
		if d.flaps_lever.name != "q-eng" or d.flaps_lever.axis < 0 or d.flaps_lever.detents.size() != 5:
			return "%s: the flaps lever needs five notches" % os_name
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
	t.flaps_lever.detents = [-1.0, 0.0, 1.0]
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
	if r.flaps_lever.detents != [-1.0, 0.0, 1.0] or r.parking_brake_switch.button != t.parking_brake_switch.button:
		return "flaps lever notches / switch lost on save and load"
	return ""


func test_captain_detents_and_flaps_lever() -> String:
	var d: Array = InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK].quadrant.axes.flaps_lever.detents
	for p in [[-1.0, 0], [-0.9, 0], [-0.456, 1], [-0.3, 1], [-0.051, 2], [0.1, 2], [0.47, 3], [0.7, 3], [0.75, 4], [1.0, 4], [5.0, 4]]:
		if InputBindings.detent_index(p[0], d) != p[1]:
			return "raw %f -> notch %d, want %d" % [p[0], InputBindings.detent_index(p[0], d), p[1]]
	if InputBindings.detent_index(0.3, []) != 0:
		return "empty detent list should give notch 0"
	var j := JoystickControls.new()
	var c172 := AircraftControls.default_set()
	var old = Props.get_v("fdm/flap_detents", 4)
	Props.set_v("fdm/flap_detents", 4)  # the C172: flaps 0..3, FULL stays at 3
	Props.set_v("controls/flaps", 0)
	j.flap_notch(0, c172)  # first read only records the lever, so the sim's setting is untouched
	Props.set_v("controls/flaps", 2)
	j.flap_notch(0, c172)
	var untouched: int = Props.get_v("controls/flaps")
	j.flap_notch(1, c172)
	var one: int = Props.get_v("controls/flaps")
	j.flap_notch(3, c172)
	var three: int = Props.get_v("controls/flaps")
	j.flap_notch(4, c172)
	var full_c172: int = Props.get_v("controls/flaps")
	Props.set_v("fdm/flap_detents", 5)  # an airliner with a FULL notch
	j.flap_notch(3, c172)
	j.flap_notch(4, c172)
	var full_jet: int = Props.get_v("controls/flaps")
	Props.set_v("controls/flaps", 0)
	Props.set_v("fdm/flap_detents", old)
	j.free()
	if untouched != 2:
		return "an unchanged lever overwrote the flaps"
	if one != 1 or three != 3:
		return "lever move did not set flaps: %d, %d" % [one, three]
	return "" if full_c172 == 3 and full_jet == 4 else "FULL notch: C172 %d (want 3), jet %d (want 4)" % [full_c172, full_jet]


func test_captain_level_switches() -> String:
	Props.set_v("controls/parking_brake", false)
	Props.set_v("controls/magnetos", 3)
	Props.set_v("controls/engine_master_1", false)
	ControlSteps.level("parking_brake_switch", true)
	var on := Props.get_b("controls/parking_brake")
	ControlSteps.level("parking_brake_switch", false)
	var off := not Props.get_b("controls/parking_brake")
	ControlSteps.level("magnetos_switch", false)
	var mag_off: int = Props.get_v("controls/magnetos")
	ControlSteps.level("magnetos_switch", true)
	var mag_on: int = Props.get_v("controls/magnetos")
	ControlSteps.level("engine_master_1_switch", true)
	var master := Props.get_b("controls/engine_master_1")
	Props.set_v("controls/engine_master_1", false)
	if not on or not off:
		return "parking brake switch does not follow the switch"
	if mag_off != 0 or mag_on != 3:
		return "magnetos switch: OFF %d, BOTH %d" % [mag_off, mag_on]
	if not master:
		return "engine master switch did not set the master"
	for a in ControlActions.LEVELS:
		if not InputBindings.BUTTONS.has(a) or ControlSteps.handles(a):
			return "%s must be a button that is not a press action" % a
	return ""


func test_captain_throttle_calibrated() -> String:
	var t := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "macOS")
	# the C172 takes the lever as a plain throttle: idle at raw +0.48, TOGA at -1.0, forward = more, reverse zone = idle
	for p in [[0.48, 0.0], [0.47, 0.0], [0.7, 0.0], [1.0, 0.0], [-1.0, 1.0], [-0.26, 0.5]]:
		var v := InputBindings.shape(p[0], t.throttle)
		if absf(v - p[1]) > 0.02:
			return "C172 throttle raw %f -> %f, want %f" % [p[0], v, p[1]]
	if InputBindings.shape(0.0, t.throttle) < InputBindings.shape(0.3, t.throttle):
		return "C172 throttle is backwards: pushing forward must give more"
	var t2: Dictionary = t.throttle_2
	if InputBindings.shape(0.47, t2) != 0.0 or InputBindings.shape(-1.0, t2) != 1.0:
		return "lever 2 idle / TOGA wrong"
	return ""


func test_captain_throttle_with_a_reverse_range() -> String:
	# a plain reverse-range lever: idle at raw +0.48 (with play), reverse behind it towards raw +1.0
	var t := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "macOS")
	var lo := float(t.throttle.lo)
	var rev := float(t.throttle.rev)
	for p in [[0.48, 0.0], [0.5, 0.0], [lo + LeverDetents.IDLE_BAND, 0.0], [0.0, 0.0], [1.0, -1.0]]:
		var pos := LeverDetents.calibrated_pos(p[0], 0.0, lo, rev)
		if not _near(pos, p[1]):
			return "reverse lever raw %f -> %f, want %f" % [p[0], pos, p[1]]
	var half := LeverDetents.calibrated_pos(0.765, 0.0, lo, rev)
	if half > -0.4 or half < -0.6:
		return "halfway into the reverse travel should be about half reverse: %f" % half
	# the old orientation (lever reads falling towards reverse) still works
	if not _near(LeverDetents.calibrated_pos(-1.0, 0.0, -0.4, -1.0), -1.0) or LeverDetents.calibrated_pos(-0.42, 0.7, -0.4) != 0.7:
		return "falling-towards-reverse orientation broken"
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
	# the same lever is the speedbrake on an airliner: RET = retracted
	if t.speedbrake.axis != t.mixture.axis or InputBindings.shape(-1.0, t.speedbrake) != 0.0 \
			or not _near(InputBindings.shape(1.0, t.speedbrake), 1.0):
		return "speedbrake should be the same lever, retracted at RET"
	return ""


func test_captain_actions_follow_the_aircraft() -> String:
	var c172 := AircraftControls.default_set()
	var jet := AircraftControls.for_def(AircraftDef.make("jet", {"controls": {"actions": JET_GROUPS}}, "res://aircraft/c172", FX.turbine_config()))
	for a in ["flaps_lever", "mixture", "parking_brake_switch", "magnetos_switch", "starter"]:
		if not c172.offers(a):
			return "C172 should offer %s" % a
	for a in ["speedbrake", "engine_master_1_switch", "engine_master_2_switch", "throttle_2", "gear_switch", "engine_mode_ign",
			"autobrake_hi"]:
		if c172.offers(a):
			return "C172 must not offer %s" % a
	for a in ["flaps_lever", "speedbrake", "parking_brake_switch", "engine_master_1_switch", "engine_master_2_switch"]:
		if not jet.offers(a):
			return "airliner should offer %s" % a
	for a in ["mixture", "magnetos_switch", "starter"]:
		if jet.offers(a):
			return "airliner must not offer %s" % a
	# the one quadrant lever never drives two controls on the same aircraft
	var d := InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "macOS")
	for c in [c172, jet]:
		var seen := {}
		for a in c.axes():
			if int(d[a].axis) >= 0:
				var k := "%s:%d" % [d[a].name, d[a].axis]
				if seen.has(k):
					return "%s and %s share an axis on one aircraft" % [seen[k], a]
				seen[k] = a
		seen.clear()
		for a in c.buttons():
			if int(d[a].button) >= 0:
				var k := "%s:%d" % [d[a].name, d[a].button]
				if seen.has(k):
					return "%s and %s share a button on one aircraft" % [seen[k], a]
				seen[k] = a
	return ""
