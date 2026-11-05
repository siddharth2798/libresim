extends RefCounted
## The Thrustmaster Captain Pack profile on the A320 (core/input_profiles.gd, aircraft/a320/aircraft.json): thrust
## levers through the sim's detents, flaps notch table (FULL reachable), speed brake notches, gear lever, engine
## mode selector, auto brake dial, ENG masters; and that the C172 is not affected. No hardware needed: switches are
## lever positions through the pure mapping functions (switches: test_input_captain_switches.gd).

const FX := preload("res://tests/captain_fixtures.gd")
const NOTCH_NAMES := ["0", "1", "2", "3", "FULL"]


func _near(a: float, b: float, tol := 1e-3) -> bool:
	return absf(a - b) <= tol


## The A320 lever position of raw axis value `raw` on action `action` (as JoystickControls._levers computes it).
func _pos(t: Dictionary, action: String, raw: float, ctl: AircraftControls) -> float:
	var lv := ctl.levers
	var v := InputBindings.shape(raw, t[action])
	return LeverDetents.snap(LeverDetents.from_binding(t[action], raw, v, lv.detents, lv.reverse_frac), lv.detents)


func _det(ctl: AircraftControls, name: String) -> float:
	return float(LeverDetents.detent_pos(ctl.levers.detents, name))


func test_a320_offers_and_no_clashes() -> String:
	var c := FX.a320()
	var t := FX.table()
	for a in ["throttle", "throttle_2", "speedbrake", "flaps_lever", "parking_brake_switch", "gear_switch", "engine_master_1_switch",
			"engine_master_2_switch", "engine_mode_crank", "engine_mode_ign", "autobrake_btv", "autobrake_low", "autobrake_2",
			"autobrake_3", "autobrake_hi"]:
		if not c.offers(a):
			return "A320 should offer %s" % a
		if int(t[a].get("axis", t[a].get("button", -1))) < 0:
			return "%s is not bound in the profile" % a
	for a in ["mixture", "starter", "magnetos_switch"]:
		if c.offers(a):
			return "A320 must not offer %s" % a
	var seen := {}
	for a in c.axes():
		if int(t[a].axis) >= 0:
			var k := "%s:%d" % [t[a].name, t[a].axis]
			if seen.has(k):
				return "%s and %s share an axis on the A320" % [seen[k], a]
			seen[k] = a
	seen.clear()
	for a in c.buttons():
		if int(t[a].button) >= 0:
			var k := "%s:%d" % [t[a].name, t[a].button]
			if seen.has(k):
				return "%s and %s share a button on the A320" % [seen[k], a]
			seen[k] = a
	var c172 := AircraftControls.default_set()
	for a in ["throttle_2", "gear_switch", "engine_mode_crank", "autobrake_2", "speedbrake"]:
		if c172.offers(a):
			return "C172 must not offer %s" % a
	return ""


func test_a320_thrust_lever_detents_coincide() -> String:
	var c := FX.a320()
	var t := FX.table()
	var cl := _det(c, "CL")
	var flx := _det(c, "FLX/MCT")
	# [action, raw, wanted position, what]: both levers, the measured clicks and some play around them
	var cases := [
		["throttle", 0.48, 0.0, "L1 idle"], ["throttle", 0.476, 0.0, "L1 idle low play"], ["throttle", 0.488, 0.0, "L1 idle high play"], ["throttle", 0.445, 0.0, "L1 idle, rested slightly forward (live check 2026-11-05)"],
		["throttle", -0.01, cl, "L1 CL"], ["throttle", 0.02, cl, "L1 CL play"], ["throttle", -0.035, cl, "L1 CL play"],
		["throttle", -0.485, flx, "L1 FLX/MCT"], ["throttle", -0.505, flx, "L1 FLX/MCT play"], ["throttle", -0.465, flx, "L1 FLX/MCT play"],
		["throttle", -1.0, 1.0, "L1 TOGA"],
		["throttle_2", 0.47, 0.0, "L2 idle"], ["throttle_2", 0.457, 0.0, "L2 idle low play"], ["throttle_2", 0.484, 0.0, "L2 idle high play"],
		["throttle_2", -0.02, cl, "L2 CL"], ["throttle_2", -0.047, cl, "L2 CL play"], ["throttle_2", -0.48, flx, "L2 FLX/MCT"],
		["throttle_2", -0.466, flx, "L2 FLX/MCT play"], ["throttle_2", -1.0, 1.0, "L2 TOGA"]]
	for k in cases:
		var p := _pos(t, k[0], k[1], c)
		if not _near(p, k[2]):
			return "%s: raw %.3f -> lever %.3f, want %.3f" % [k[3], k[1], p, k[2]]
	# between the clicks the lever moves smoothly and forward is more
	var last := -1.0
	for raw in [0.4, 0.3, 0.2, 0.1, -0.1, -0.2, -0.3, -0.4, -0.6, -0.8, -0.95]:
		var p := _pos(t, "throttle", raw, c)
		if p < last or p > 1.0:
			return "lever 1 not monotonic at raw %.2f" % raw
		last = p
	return ""


func test_a320_reverse_zone() -> String:
	var c := FX.a320()
	var t := FX.table()
	for a in ["throttle", "throttle_2"]:
		if _pos(t, a, 0.52, c) != 0.0:
			return "%s: just behind idle (idle play) must not be reverse" % a
		if not _near(_pos(t, a, 1.0, c), -1.0):
			return "%s: lever fully back should be REV MAX" % a
		var mid := _pos(t, a, 0.76, c)
		if mid > -0.3 or mid < -0.7:
			return "%s: halfway back should be about half reverse: %f" % [a, mid]
	# written to the sim: lever 1 TOGA + lever 2 reverse, then lever 1 reverse
	var lv := c.levers
	lv.write_pos(0, 1.0)
	lv.write_pos(1, _pos(t, "throttle_2", 1.0, c))
	var ok := _near(Props.get_f("controls/throttle_1"), 1.0) and _near(Props.get_f("controls/throttle_2"), 0.0) \
		and _near(Props.get_f("controls/reverse_2"), 1.0) and _near(Props.get_f("controls/reverse_1"), 0.0)
	lv.write_pos(0, -1.0)
	var rev1 := _near(Props.get_f("controls/reverse_1"), 1.0) and _near(Props.get_f("controls/throttle_1"), 0.0)
	lv.write_pos(0, 0.0)
	lv.write_pos(1, 0.0)
	return "" if ok and rev1 else "lever positions did not reach throttle_n / reverse_n"


func test_c172_throttle_not_backwards() -> String:
	var t := FX.table()
	var c172 := AircraftControls.default_set()
	var lv := c172.levers
	var last := -1.0
	for raw in [0.48, 0.2, -0.2, -0.6, -1.0]:
		var v := InputBindings.shape(raw, t.throttle)
		var p := LeverDetents.from_binding(t.throttle, raw, v, lv.detents, lv.reverse_frac)
		if p < last - 1e-6:
			return "C172 throttle decreases while pushing forward at raw %.2f" % raw
		last = p
	var idle := LeverDetents.from_binding(t.throttle, 0.48, InputBindings.shape(0.48, t.throttle), lv.detents, lv.reverse_frac)
	var rev := LeverDetents.from_binding(t.throttle, 1.0, InputBindings.shape(1.0, t.throttle), lv.detents, lv.reverse_frac)
	return "" if idle == 0.0 and rev == 0.0 and _near(last, 1.0) else "C172 throttle: idle %f, reverse zone %f, TOGA %f" % [idle, rev, last]


func test_a320_flaps_lever_reaches_full() -> String:
	var c := FX.a320()
	var t := FX.table()
	var names: Array = []
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/config.json"))
	for d in cfg.controls.flaps.detents:
		names.append(str(d.lever))
	if names != ["0", "1", "1+F", "2", "3", "FULL"] or c.flap_notches.size() != t.flaps_lever.detents.size():
		return "sim flap settings / notch table changed: %s %s" % [names, c.flap_notches]
	for i in 5:
		if names[c.flap_notches[i]] != ("1" if i == 1 else NOTCH_NAMES[i]):
			return "notch %d -> %s, want %s" % [i, names[c.flap_notches[i]], NOTCH_NAMES[i]]
	if names[int(c.flap_ground["1"])] != "1+F":
		return "lever 1 on the ground should be 1+F"
	var old_det = Props.get_v("fdm/flap_detents", 4)
	var old_wow := Props.get_b("fdm/wow")
	Props.set_v("fdm/flap_detents", 6)
	var got := []
	for wow in [false, true]:
		Props.set_v("fdm/wow", wow)
		var j := JoystickControls.new()
		j.flap_notch(0, c)  # the first read only records the lever
		var row := []
		for i in [1, 2, 3, 4, 0]:
			j.flap_notch(i, c)
			row.append(int(Props.get_v("controls/flaps")))
		got.append(row)
		j.free()
	Props.set_v("fdm/flap_detents", old_det)
	Props.set_v("fdm/wow", old_wow)
	Props.set_v("controls/flaps", 0)
	if got[0] != [1, 3, 4, 5, 0] or got[1] != [2, 3, 4, 5, 0]:
		return "notches 1 2 3 FULL 0 -> settings %s (air) / %s (ground), want [1,3,4,5,0] / [2,3,4,5,0]" % [got[0], got[1]]
	return ""


func test_a320_speedbrake_notches() -> String:
	var t := FX.table()
	var b: Dictionary = t.speedbrake
	for p in [[-1.0, 0.0], [-0.9, 0.0], [-0.523, 0.25], [-0.031, 0.5], [0.465, 0.75], [0.7, 0.75], [1.0, 1.0]]:
		var v := InputBindings.notched(b, p[0], InputBindings.shape(p[0], b))
		if not _near(v, p[1]):
			return "speed brake raw %.3f -> %.2f, want %.2f" % [p[0], v, p[1]]
	# the same lever is the C172 mixture: analog, RET = rich, no notches
	var m: Dictionary = t.mixture
	if InputBindings.notched(m, -0.523, 0.7) != 0.7 or not _near(InputBindings.shape(-1.0, m), 1.0) or InputBindings.shape(1.0, m) != 0.0:
		return "C172 mixture on the speed brake lever changed"
	if not _near(InputBindings.shape(-0.523, m), 0.76, 0.02):
		return "mixture at the second stop: %f" % InputBindings.shape(-0.523, m)
	return ""


## Lever 2 rests at idle until its axis has reported (macOS sends no initial report): moving lever 1 first must not
## drag lever 2 along (live check 2026-11-05), and once lever 2 reports it is independent; with no lever-2 axis at all
## the throttle axis still moves every lever.
func test_unreported_lever_2_does_not_copy_lever_1() -> String:
	var c := FX.a320()
	c.seed_props()
	var j := FX.joystick(c)
	j.fake_axes = {"throttle": -1.0, "throttle_2": null}  # lever 1 at TOGA, lever 2 has not reported
	j._levers(c)
	if not _near(c.levers.pos(0), 1.0) or not _near(c.levers.pos(1), 0.0):
		return "lever 1 TOGA with lever 2 unreported gave %.3f / %.3f, want 1 / 0" % [c.levers.pos(0), c.levers.pos(1)]
	j.fake_axes = {"throttle": 0.47, "throttle_2": -1.0}  # lever 1 back at idle, lever 2 now at TOGA
	j._levers(c)
	if not _near(c.levers.pos(0), 0.0) or not _near(c.levers.pos(1), 1.0):
		return "independent levers gave %.3f / %.3f, want 0 / 1" % [c.levers.pos(0), c.levers.pos(1)]
	j.table["throttle_2"].axis = -1  # no lever-2 axis bound at all: the throttle axis moves every lever
	j.fake_axes = {"throttle": -1.0}
	j._levers(c)
	return "" if _near(c.levers.pos(0), 1.0) and _near(c.levers.pos(1), 1.0) else "unbound lever 2 did not follow lever 1"


## The sidestick's three front buttons (measured 2026-11-05): change view = 19 is the next camera, menu = 21 pauses,
## Xbox = 20 is left unbound. The camera action is called a camera on the Controls page.
func test_sidestick_front_buttons() -> String:
	var t := FX.table()
	if int(t["view_next"].button) != 19 or str(t["view_next"].name) != "sidestick":
		return "next camera is not on sidestick button 19: %s" % [t["view_next"]]
	if int(t["pause"].button) != 21:
		return "pause is not on button 21"
	for a in t:
		if a != "view_next" and not InputBindings.is_axis(a) and str(t[a].get("name", "")) == "sidestick" and int(t[a].button) in [19, 20]:
			return "%s shares a front button (%d)" % [a, int(t[a].button)]
	return "" if str(InputBindings.LABELS["view_next"]).begins_with("Next camera") else "label is not 'Next camera'"
