extends Node
## The A320 V/S knob as on the real FCU (systems/autoflight_logic.gd): turning it outside V/S only presets the target,
## which the FCU window shows (ap/vs_preset, FcuWindows.vs); pulling it flies V/S at that target (or at the present
## vertical speed when the window shows dashes); pushing it levels off (V/S 0). In V/S a turn changes the target at once.
## The keyboard follows the same rules (fcu_vs_up / fcu_vs_down preset, fcu_vs_pull / fcu_vs_push: input/control_actions.gd).

const KEEP := ["ap/vs_preset", "ap/fma/vertical", "controls/fcu/vs_fpm", "controls/fcu/vert_select", "controls/fcu/vs_managed",
	"controls/fcu/trk_fpa", "systems/electrical/avionics_powered", "environment/wind_ned", "environment/gust_pqr", "environment/qnh_pa",
	"environment/delta_t", "weather/use_humidity"]
const FPM := 0.00508  # m/s per ft/min

var _saved := {}


func _keep() -> void:
	for k in KEEP:
		if not _saved.has(k):
			_saved[k] = Props.get_v(k) if Props.has(k) else null


func teardown() -> void:
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()


func _air() -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.ra_m = 3000.0
	i.alt_m = 3048.0
	i.cas = 130.0
	i.tas = 200.0
	i.gs_mps = 200.0
	i.f.fd = true
	i.f.ap1 = true
	i.f.alt = 3048.0
	i.f.spd = 130.0
	return i


func test_vs_turn_presets_and_only_the_pull_flies_it() -> String:
	var logic := AfLogic.new({})
	var i := _air()
	logic.update(i)
	if logic.vert.mode != "ALT":
		return "the AP starts in ALT at the selected altitude: %s" % logic.vert.mode
	i.f.vs = -1000.0 * FPM  # the knob turned to -1000
	logic.update(i)
	if logic.vert.mode != "ALT" or logic.vs_preset <= 0.0:
		return "a turn must only preset V/S (mode %s, preset %.1f s)" % [logic.vert.mode, logic.vs_preset]
	logic.update(i)
	if logic.vert.mode != "ALT":
		return "the preset alone never engages V/S: %s" % logic.vert.mode
	i.f.select = "VS"  # pull
	logic.update(i)
	i.f.select = ""
	if logic.vert.mode != "V/S" or logic.writes.has("vs") or absf(i.f.vs + 1000.0 * FPM) > 1.0e-6:
		return "the pull flies the preset -1000: mode %s, writes %s" % [logic.vert.mode, logic.writes]
	if logic.vs_preset != 0.0:
		return "in V/S the window shows the target itself (no preset timer)"
	i.f.vs = -1500.0 * FPM  # in V/S a turn changes the target directly
	logic.update(i)
	if logic.vert.mode != "V/S" or logic.vs_preset != 0.0:
		return "a turn in V/S keeps V/S: %s" % logic.vert.mode
	i.f.select = "LEVEL"  # push
	logic.update(i)
	i.f.select = ""
	if logic.vert.mode != "V/S" or float(logic.writes.get("vs", 99.0)) != 0.0:
		return "the push levels off at V/S 0: %s %s" % [logic.vert.mode, logic.writes]
	return ""


func test_vs_pull_with_dashes_flies_the_present_rate_and_the_preset_times_out() -> String:
	var logic := AfLogic.new({})
	var i := _air()
	logic.update(i)
	i.f.vs = 2000.0 * FPM
	logic.update(i)
	for k in int(AfLogic.VS_PRESET_S / i.dt) + 2:
		logic.update(i)
	if logic.vs_preset > 0.0 or logic.vert.mode != "ALT":
		return "the preset shows %.1f s then the window goes back to dashes (mode %s)" % [logic.vs_preset, logic.vert.mode]
	i.vs_mps = 700.0 * FPM
	i.f.select = "VS"
	logic.update(i)
	if logic.vert.mode != "V/S" or absf(float(logic.writes.get("vs", 0.0)) - 700.0 * FPM) > 1.0e-6:
		return "a pull over dashes flies the present V/S, not the stale +2000: %s" % [logic.writes]
	return ""


func test_fcu_window_shows_the_preset_before_the_pull() -> String:
	_keep()
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("controls/fcu/trk_fpa", false)
	Props.set_v("controls/fcu/vs_fpm", -800.0)
	Props.set_v("ap/fma/vertical", "ALT")
	Props.set_v("ap/vs_preset", false)
	var dashes := str(FcuWindows.vs().text)
	Props.set_v("ap/vs_preset", true)
	var preset := str(FcuWindows.vs().text)
	return "" if dashes == "-----" and preset == "-0800" else "window: no preset %s, preset %s" % [dashes, preset]


func test_keys_turn_then_pull_in_the_closed_loop() -> String:
	_keep()
	for k in ["environment/wind_ned", "environment/gust_pqr"]:  # calm air: wind left by an earlier suite shifted the level-off by 1500 fpm
		Props.set_v(k, Vector3.ZERO)
	Props.set_v("environment/qnh_pa", 101325.0)
	Props.set_v("environment/delta_t", 0.0)
	Props.set_v("weather/use_humidity", false)
	var r := AfRig.new(250.0, 10000.0, 0.0)
	r.fcu("ap1", true)
	r.run(2.0)
	if r.fma("vertical").get_slice("\n", 0) != "ALT":
		return "AP1 holds ALT first: %s" % r.fma("vertical")
	var knobs := {}
	for k in 12:  # Alt+; tapped 12 times: -1200 ft/min preset
		ControlSteps.knob("fcu_vs_down", true, 0.01, knobs)
		ControlSteps.knob("fcu_vs_down", false, 0.01, knobs)
	r.run(1.0)
	if Props.get_f("controls/fcu/vs_fpm") != -1200.0 or r.fma("vertical").get_slice("\n", 0) != "ALT":
		return "the keys preset -1200 without leaving ALT: %s, %s" % [Props.get_f("controls/fcu/vs_fpm"), r.fma("vertical")]
	if not Props.get_b("ap/vs_preset") or str(FcuWindows.vs().text) != "-1200":
		return "the FCU window shows the preset: %s" % FcuWindows.vs().text
	if r.fpm() < -600.0:  # ALT hold may wobble a little; the -1200 preset must not be flown
		return "still level before the pull (not descending toward the preset): %.0f fpm" % r.fpm()
	Props.set_v("controls/fcu/alt_ft", 8000.0)  # a target below, so the level-off does not capture at once
	ControlSteps.press("fcu_vs_pull")
	r.run(12.0)
	if r.fma("vertical").get_slice("\n", 0) != "V/S" or r.fpm() > -900.0:
		return "after the pull V/S -1200 is flown: %s, %.0f fpm" % [r.fma("vertical"), r.fpm()]
	ControlSteps.press("fcu_vs_push")
	r.run(12.0)
	if Props.get_f("controls/fcu/vs_fpm") != 0.0 or absf(r.fpm()) > 300.0:
		return "the push levels off: set %s, %.0f fpm" % [Props.get_f("controls/fcu/vs_fpm"), r.fpm()]
	return ""


func test_vs_pull_and_push_keys_are_bound_apart_from_the_turn() -> String:
	var t := KeyBindings.defaults()
	var sh := KeyBindings.shifted_keys(t)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_APOSTROPHE
	e.alt_pressed = true
	e.shift_pressed = true
	e.pressed = true
	if not KeyBindings.matches(t, "fcu_vs_pull", e, sh) or KeyBindings.matches(t, "fcu_vs_up", e, sh):
		return "Shift+Alt+' pulls the V/S knob and does not also turn it"
	e.shift_pressed = false
	if KeyBindings.matches(t, "fcu_vs_pull", e, sh):
		return "Alt+' alone only turns the knob"
	for a in ["fcu_vs_pull", "fcu_vs_push"]:
		if ControlActions.group_of(a) != "fcu" or not a in InputBindings.BUTTONS or InputBindings.LABELS.get(a, "") == "":
			return "%s is an FCU action with a key and a joystick button" % a
	return ""
