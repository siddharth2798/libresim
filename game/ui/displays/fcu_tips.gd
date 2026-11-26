class_name FcuTips
extends RefCounted
## The hover note of the 2D FCU card: the cockpit note's three lines (CockpitTip), name / how to work it and its key / state.
## Names and key bindings come from the cockpit note's own tables (ui/cockpit_tip_text.gd, cockpit_tip_fcu.gd) so a rebind shows.
## Pure: reads Props only for the state line.

const Text = preload("res://ui/cockpit_tip_text.gd")

const LEVER := {  # card id -> the cockpit lever id (names) and the property it drives (keys, state)
	"knob_spd": ["spd_sel", "controls/fcu/spd_kt"], "knob_hdg": ["hdg_sel", "controls/fcu/hdg_deg"],
	"knob_alt": ["alt_sel", "controls/fcu/alt_ft"], "knob_vs": ["vs_sel", "controls/fcu/vs_fpm"],
	"btn_ap1": ["ap1", "controls/fcu/ap1"], "btn_ap2": ["ap2", "controls/fcu/ap2"], "btn_athr": ["athr", "controls/fcu/athr"],
	"btn_loc": ["loc", "controls/fcu/loc"], "btn_appr": ["appr", "controls/fcu/appr"],
	"btn_spd_mach": ["spd_mach", "controls/fcu/spd_mach"], "btn_trk_fpa": ["trk_fpa", "controls/fcu/trk_fpa"],
	"btn_metric_alt": ["metric_alt", "controls/fcu/metric_alt"], "btn_alt_inc": ["alt_inc", "controls/fcu/alt_inc_1000"],
	"btn_fd": ["fd_cpt", "controls/fcu/fd"], "btn_ls": ["ls_cpt", "controls/efis/ls"],
}
const KNOB_HOW := "Wheel or drag: turn · Click: push · Shift+click: pull"
const LAMPS := {"btn_ap1": "ap1", "btn_ap2": "ap2", "btn_athr": "athr", "btn_loc": "loc", "btn_appr": "appr"}


## The note for zone `id` ("" when there is none). `bindings` is KeyBindings.load_from() (tests pass defaults).
static func text(id: String, bindings: Dictionary) -> String:
	if id == "btn_exped":
		return "Expedite (EXPED)\nNot modelled in libresim\nDisabled"
	if id == "btn_ap_disc":  # the sidestick takeover button: no cockpit twin in the model
		var k := _keys("controls/fcu/ap_disc", bindings)
		return "Autopilot disconnect (sidestick takeover)\nClick" + (" · " + k if k != "" else "") + "\n" + _disc_state()
	if not LEVER.has(id):
		return ""
	var drive: String = LEVER[id][1]
	var title: String = Text.title(LEVER[id][0])
	var keys := _keys(drive, bindings)
	if id.begins_with("knob_"):
		return "%s\n%s\n%s" % [title, KNOB_HOW + (" · " + keys if keys != "" else ""), _knob_state(id.substr(5), drive)]
	return "%s\n%s\n%s" % [title, "Click" + (" · " + keys if keys != "" else ""), _button_state(id, drive)]


## Keys that work the property (the same first bindings the cockpit note lists).
static func _keys(drive: String, bindings: Dictionary) -> String:
	var bits := []
	for action in Text.KEYS.get(drive, []):
		var slots: Array = bindings.get(action, [])
		if not slots.is_empty():
			bits.append(KeyBindings.describe(slots[0]))
	return " / ".join(bits)


static func _disc_state() -> String:
	if Props.get_b("ap/disconnect_warning"):
		return "AP OFF warning: press again to cancel"
	return "Autopilot engaged" if Props.get_b("ap/ap1") or Props.get_b("ap/ap2") else "Autopilot off"


static func _button_state(id: String, drive: String) -> String:
	if LAMPS.has(id):  # what the autopilot really did, not the press
		return "Engaged" if Props.get_b("ap/" + str(LAMPS[id]), Props.get_b(drive)) else "Off"
	return Text.state(drive, Props.get_v(drive, null))


static func _knob_state(key: String, drive: String) -> String:
	var n := Props.get_f(drive)
	var v := ""
	var mode := ""
	match key:
		"spd":
			v = "%d kt" % roundi(n)
			mode = "selected (pulled)" if FcuActions.pulled(key) else "managed (pushed)"
		"hdg":
			v = "%03d°" % (roundi(n) % 360)
			mode = "selected (pulled)" if FcuActions.pulled(key) else "managed, NAV (pushed)"
		"alt":
			v = "%d ft" % roundi(n)
			mode = "open climb / descent (pulled)" if FcuActions.pulled(key) else "managed (pushed)"
		"vs":
			v = "%+d ft/min" % roundi(n)
			mode = "flying V/S (pulled)" if FcuActions.pulled(key) else "not flying V/S"
	return "%s · %s" % [v, mode]
