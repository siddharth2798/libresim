extends Node
## A320 autothrust arming and the SPD/MACH target (systems/autoflight_thrust.gd, autoflight_speeds.gd, autoflight.gd; sources in
## docs/A320-FCU-REFERENCE.md). Pure logic with AfInputs, plus closed loops with the real A320 FDM (tests/af_rig.gd).
##   arming   on the ground the levers into TOGA (or FLX/MCT with a flex temperature), flight director on, arm A/THR (cyan A/THR,
##            white MAN TOGA / MAN FLX); only the move in arms it; CL in flight makes it active; idle in flight disconnects it
##   SPD/MACH the button converts the window value; the selected Mach is held as the altitude changes; the FMA says MACH

const KEEP := ["controls/fcu/spd_mach", "controls/fcu/mach_sel", "controls/fcu/spd_kt", "atmosphere/pressure_pa", "ap/spd_preset"]

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


func _ground(lever: float, flex := 0.0) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.wow = true
	i.ra_m = 0.0
	i.alt_m = 0.0
	i.cas = 0.0
	i.lever = lever
	i.engine_lever = lever
	i.flex_c = flex
	i.f.fd = true
	return i


func _air(lever: float, alt_m := 3048.0) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.wow = false
	i.ra_m = alt_m
	i.alt_m = alt_m
	i.cas = 130.0
	i.tas = 200.0
	i.gs_mps = 200.0
	i.lever = lever
	i.engine_lever = lever
	i.f.fd = true
	i.f.alt = alt_m
	i.f.spd = 130.0
	return i


## The node writes the armed state back to the FCU button, the next tick reads it.
func _step(logic: AfLogic, i: AfInputs, n := 1) -> void:
	for k in n:
		logic.update(i)
		i.f.athr = logic.thr.armed


func test_toga_on_the_ground_arms_the_autothrust() -> String:
	var logic := AfLogic.new({})
	var i := _ground(0.0)
	_step(logic, i, 3)
	if logic.thr.armed:
		return "levers at idle must not arm A/THR"
	i.lever = AfThrust.TOGA
	_step(logic, i, 2)
	if not logic.thr.armed or logic.thr.active:
		return "TOGA on the ground arms (not activates) A/THR: armed %s active %s" % [logic.thr.armed, logic.thr.active]
	if logic.fma.thrust != "MAN\nTOGA" or not logic.fma.misc.contains("A/THR") or not i.f.athr:
		return "FMA thrust [%s] misc [%s], FCU light %s" % [logic.fma.thrust, logic.fma.misc, i.f.athr]
	if AfFma.color("misc", 2, logic.fma.misc, logic.thr.active) != "cyan" or AfFma.color("thrust", 0, logic.fma.thrust, false) != "white":
		return "armed A/THR is cyan, MAN TOGA white"
	return ""


func test_no_flight_director_no_lever_arming() -> String:
	var logic := AfLogic.new({})
	var i := _ground(AfThrust.TOGA)
	i.f.fd = false
	_step(logic, i, 3)
	return "" if not logic.thr.armed else "TOGA without a flight director must not arm A/THR"


func test_flex_arms_only_with_a_temperature() -> String:
	var logic := AfLogic.new({})
	var i := _ground(AfThrust.MCT, 0.0)
	_step(logic, i, 3)
	if logic.thr.armed:
		return "FLX/MCT without a flex temperature is MCT: it does not arm"
	var l2 := AfLogic.new({})
	var j := _ground(AfThrust.MCT, 50.0)
	_step(l2, j, 3)
	if not l2.thr.armed or l2.fma.thrust != "MAN\nFLX 50":
		return "FLX 50 arms A/THR: armed %s, FMA [%s]" % [l2.thr.armed, l2.fma.thrust]
	return ""


func test_only_the_move_into_the_detent_arms() -> String:
	var logic := AfLogic.new({})
	var i := _ground(AfThrust.TOGA)
	_step(logic, i, 2)
	i.f.athr = false  # the pilot presses the button off with the levers still at TOGA
	_step(logic, i, 5)
	if logic.thr.armed:
		return "a disarmed A/THR must stay off while the levers stay in TOGA"
	i.lever = 0.0
	_step(logic, i, 2)
	i.lever = AfThrust.TOGA
	_step(logic, i, 2)
	return "" if logic.thr.armed else "a new move into TOGA arms again"


func test_climb_detent_activates_and_the_levers_ask_for_it() -> String:
	var logic := AfLogic.new({})
	var g := _ground(AfThrust.TOGA)
	_step(logic, g, 2)
	var i := _air(AfThrust.TOGA, 100.0)  # airborne, levers still in TOGA
	i.f.athr = true
	_step(logic, i, 3)
	if logic.thr.active or logic.fma.thrust != "MAN\nTOGA":
		return "above CL the thrust is manual: active %s, FMA [%s]" % [logic.thr.active, logic.fma.thrust]
	i.ra_m = 700.0  # above the thrust reduction altitude (1500 ft)
	i.alt_m = 700.0
	_step(logic, i, 3)
	if logic.fma.thrust != "LVR CLB" or not AfFma.flashes("thrust", logic.fma.thrust):
		return "LVR CLB (flashing) above the reduction altitude with A/THR armed: [%s]" % logic.fma.thrust
	i.lever = AfThrust.CL
	_step(logic, i, 3)
	if not logic.thr.active or logic.fma.thrust == "" or logic.fma.thrust.begins_with("MAN") or logic.fma.thrust == "LVR CLB":
		return "levers in CL make A/THR active: active %s, FMA [%s]" % [logic.thr.active, logic.fma.thrust]
	if AfFma.color("misc", 2, logic.fma.misc, logic.thr.active) != "white":
		return "active A/THR is white in column 5"
	return ""


func test_levers_to_idle_in_flight_disconnect() -> String:
	var logic := AfLogic.new({})
	var i := _air(AfThrust.CL)
	i.f.athr = true
	_step(logic, i, 3)
	if not logic.thr.active:
		return "A/THR active with the levers in CL"
	i.lever = 0.0
	_step(logic, i, 2)
	if logic.thr.armed or logic.thr.active or i.f.athr:
		return "levers at idle in flight must disconnect A/THR (and the FCU light)"
	return ""


func test_flight_button_arms_or_activates_by_lever_position() -> String:
	var logic := AfLogic.new({})
	var i := _air(0.7)
	i.f.athr = true
	_step(logic, i, 3)
	if not logic.thr.armed or logic.thr.active or logic.fma.thrust != "MAN\nTHR":
		return "button with the levers above CL arms only: active %s [%s]" % [logic.thr.active, logic.fma.thrust]
	if AfFma.box("thrust", logic.fma.thrust) != "amber":
		return "MAN THR has an amber box"
	i.lever = AfThrust.CL
	_step(logic, i, 3)
	return "" if logic.thr.active else "back in CL it becomes active"


func test_srs_is_thrust_climb_with_the_autothrust_active() -> String:
	var logic := AfLogic.new({})
	var i := _air(AfThrust.CL)
	logic.vert.set_mode("SRS")
	logic.takeoff = true
	logic.thr.armed = true
	i.f.athr = true
	logic.thr.update(i, "SRS", 100.0, false)
	return "" if logic.thr.mode == "THR CLB" else "SRS with A/THR active is THR CLB, got %s" % logic.thr.mode


# --- SPD/MACH ------------------------------------------------------------------

func test_mach_and_cas_convert_back_and_forth() -> String:
	for alt_ft in [0.0, 10000.0, 25000.0, 35000.0]:
		var p: float = 101325.0 * pow(1.0 - 6.5e-3 * alt_ft * 0.3048 / 288.15, 5.2559)
		for kt in [180.0, 250.0, 300.0]:
			var m := AtmosphereISA.mach_from_cas(Units.kt_to_mps(kt), p)
			var back := Units.mps_to_kt(AtmosphereISA.cas_at_mach(m, p))
			if absf(back - kt) > 0.01:
				return "%d kt at %d ft: Mach %.3f gives back %.2f kt" % [kt, alt_ft, m, back]
	var sl := AtmosphereISA.cas_at_mach(0.3, 101325.0)  # at sea level pressure CAS is the ISA sea level TAS
	return "" if absf(sl - 0.3 * 340.294) < 0.05 else "Mach 0.30 at sea level pressure: %.2f m/s" % sl


func test_selected_mach_is_a_cas_that_follows_the_altitude() -> String:
	var logic := AfLogic.new({})
	var i := _air(AfThrust.CL)
	i.f.spd_mach = true
	i.f.mach_sel = 0.70
	i.pressure_pa = 40000.0
	var high := logic.speeds.selected(i)
	i.pressure_pa = 70000.0
	var low := logic.speeds.selected(i)
	if low <= high:
		return "the same Mach is a higher CAS lower down: %.1f m/s at 70 kPa, %.1f m/s at 40 kPa" % [low, high]
	if absf(AtmosphereISA.mach_from_cas(low, 70000.0) - 0.70) > 1.0e-3:
		return "selected() is not Mach 0.70 at 70 kPa"
	i.f.spd_mach = false
	i.f.spd = 130.0
	return "" if is_equal_approx(logic.speeds.selected(i), 130.0) else "knots selection is left alone"


func test_fma_says_mach_for_a_mach_target() -> String:
	var logic := AfLogic.new({})
	var i := _air(AfThrust.CL, 9000.0)
	i.pressure_pa = 30000.0
	i.f.athr = true
	i.f.spd_mach = true
	i.f.mach_sel = 0.70
	_step(logic, i, 4)
	if logic.fma.thrust != "MACH":
		return "selected Mach with A/THR active: [%s]" % logic.fma.thrust
	i.f.spd_mach = false
	i.f.spd = 130.0
	_step(logic, i, 4)
	return "" if logic.fma.thrust == "SPEED" else "selected knots: [%s]" % logic.fma.thrust


func test_pressing_spd_mach_converts_the_window_and_is_not_a_turn() -> String:
	_keep()
	var a := Autoflight.new()
	a.setup({})
	Props.set_v("atmosphere/pressure_pa", 40000.0)
	Props.set_v("controls/fcu/spd_mach", false)
	Props.set_v("controls/fcu/spd_kt", 250.0)
	Props.set_v("controls/fcu/mach_sel", 0.50)
	a._spd_mach_pressed()  # first look: no conversion
	if Props.get_f("controls/fcu/mach_sel") != 0.50:
		return "nothing converts before a press"
	Props.set_v("controls/fcu/spd_mach", true)
	a._spd_mach_pressed()
	var want := roundf(AtmosphereISA.mach_from_cas(Units.kt_to_mps(250.0), 40000.0) * 100.0) / 100.0
	if absf(Props.get_f("controls/fcu/mach_sel") - want) > 1.0e-6 or Props.get_f("controls/fcu/spd_kt") != 250.0:
		return "250 kt becomes Mach %.2f, got %.3f" % [want, Props.get_f("controls/fcu/mach_sel")]
	Props.set_v("controls/fcu/spd_mach", false)
	a._spd_mach_pressed()
	var kt := Props.get_f("controls/fcu/spd_kt")
	a.free()
	return "" if absf(kt - 250.0) <= 2.0 else "back to knots: %.1f" % kt


func test_preview_ignores_the_unit_change_but_not_a_turn() -> String:
	var logic := AfLogic.new({})
	var i := _air(AfThrust.CL)
	i.f.spd_mgd = true
	i.f.mach_sel = 0.70
	_step(logic, i, 3)
	i.f.spd_mach = true  # SPD/MACH pressed while managed
	_step(logic, i, 3)
	if logic.spd_preset > 0.0:
		return "pressing SPD/MACH is not a turned value (preview %.1f s)" % logic.spd_preset
	i.f.mach_sel = 0.72
	_step(logic, i, 2)
	return "" if logic.spd_preset > 0.0 else "turning the Mach window while managed shows it for a while"


func test_speed_knob_keys_turn_the_mach_window_in_mach_mode() -> String:
	_keep()
	Props.set_v("controls/fcu/spd_mach", true)
	Props.set_v("controls/fcu/mach_sel", 0.78)
	Props.set_v("controls/fcu/spd_kt", 250.0)
	var st := {}
	ControlSteps.knob("fcu_spd_up", true, 0.0, st)
	ControlSteps.knob("fcu_spd_up", false, 0.0, st)
	if absf(Props.get_f("controls/fcu/mach_sel") - 0.79) > 1.0e-6 or Props.get_f("controls/fcu/spd_kt") != 250.0:
		return "the speed key steps Mach by 0.01 in Mach mode: %.3f / %.0f" % [Props.get_f("controls/fcu/mach_sel"), Props.get_f("controls/fcu/spd_kt")]
	var item := FcuActions.knob_item("spd")
	FcuActions.turn("spd", -3)
	if absf(Props.get_f("controls/fcu/mach_sel") - 0.76) > 1.0e-6:
		return "the card's knob steps Mach too: %.3f (item %s)" % [Props.get_f("controls/fcu/mach_sel"), item.get("when_on")]
	Props.set_v("controls/fcu/spd_mach", false)
	FcuActions.turn("spd", 2)
	return "" if Props.get_f("controls/fcu/spd_kt") == 252.0 else "knots again: %.0f" % Props.get_f("controls/fcu/spd_kt")
