class_name FcuActions
extends RefCounted
## What a click on the 2D FCU card does. It adds NO autopilot logic: every control runs the code of its cockpit twin, so the
## card and the 3D glareshield cannot disagree (tests/test_fcu_panel.gd compares them):
##   pushbuttons  ControlSteps.press(<key action>): the key press (fcu_ap1 .. efis_ls), which flips the same controls/fcu/* flag the
##                cockpit button does; the autoflight consumes it and springs a refused press back (systems/autoflight.gd)
##   knob turn    CockpitKnob.value_after on the aircraft.json cockpit.levers item (<key>_sel): step, range, wrap and the ALT 100 / 1000 step
##   knob click   CockpitKnob.click(item, pull): the item's own push (managed / level off) or pull (selected / fly V/S) writes

const BUTTONS := {
	"loc": "fcu_loc", "ap1": "fcu_ap1", "ap2": "fcu_ap2", "athr": "fcu_athr", "appr": "fcu_appr",
	"spd_mach": "fcu_spd_mach", "trk_fpa": "fcu_trk_fpa", "metric_alt": "fcu_metric_alt", "alt_inc": "fcu_alt_1000",
	"fd": "efis_fd", "ls": "efis_ls", "ap_disc": "fcu_ap_disc",  # ap_disc: the sidestick takeover button, no 3D twin
}


## Press button `id` (loc, ap1, ... ls). False for EXPED (not modelled) and any unknown id: nothing is written.
static func press(id: String) -> bool:
	return BUTTONS.has(id) and ControlSteps.press(str(BUTTONS[id]))


## The cockpit lever item of knob `key` (a private copy, so a drag can keep its own detent counter), {} when there is none.
static func knob_item(key: String) -> Dictionary:
	var lev: Dictionary = AircraftDef.current().section("cockpit").get("levers", {})
	if not lev.has("alt_sel"):  # the card is shown only for an aircraft with an FCU; the A320's knobs otherwise
		lev = AircraftDef.load_def("a320").section("cockpit").get("levers", {})
	var item: Variant = lev.get(key + "_sel")
	return (item as Dictionary).duplicate(true) if item is Dictionary else {}


## Turn knob `key` by `detents` (+ = clockwise / more), the way the cockpit knob turns.
static func turn(key: String, detents: int) -> void:
	var item := CockpitKnob.active(knob_item(key))
	if not item.is_empty() and detents != 0:
		Props.set_v(str(item.drive), CockpitKnob.value_after(item, CockpitKnob.current(item), detents))


## Push (managed / level off) or, with `pull`, pull (selected / fly V/S) knob `key`.
static func click(key: String, pull: bool) -> void:
	var item := knob_item(key)
	if not item.is_empty():
		CockpitKnob.click(item, pull)


## Is knob `key` pulled now (selected SPD / HDG, open ALT, flown V/S)? The next plain click is then a push, and the hover note says so.
static func pulled(key: String) -> bool:
	match key:
		"spd": return not Props.get_b("controls/fcu/spd_managed")
		"hdg": return not Props.get_b("controls/fcu/hdg_managed")
		"alt": return not Props.get_b("controls/fcu/vs_managed")
	return str(Props.get_v("ap/fma/vertical", "")).get_slice("\n", 0) == "V/S"
