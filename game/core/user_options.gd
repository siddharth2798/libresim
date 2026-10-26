class_name UserOptions
extends RefCounted
## General user preferences in user://options.cfg (start-screen Options page).
## Units are only stored for now; instruments and HUD still show ft / kt / inHg.

const CFG := "user://options.cfg"
const DEFAULTS := {
	"alt_unit": "ft",  # ft | m
	"speed_unit": "kt",  # kt | km/h
	"pressure_unit": "inHg",  # inHg | hPa
	"hud_at_start": true,
	"ui_scale": "Auto",  # Auto | 100% | 125% | 150% | 200% (core/ui_scale.gd)
	"keyboard_mode": "spring",  # spring: yoke keys re-centre on release | sticky: stay put (FlightGear)
	"control_smoothing": "light",  # low-pass on pilot inputs before the FDM (fdm_node.gd)
	"auto_coordination": false,  # rudder follows aileron (for keyboard / no-pedal pilots)
	"callouts": false,  # optional training callouts (ui/callouts.gd), K toggles in flight
	"callouts_voice": false,  # say them with the OS text-to-speech voice, if the system has one
	"start_mode": "flight",  # last start-screen choice: flight | training (focused next time)
	"callsign": "VT-FSM",  # radio call sign (atc/atc_speech.gd validates it; Session.setup.callsign overrides)
	"radio_assist": true,  # radio assist: calls tune COM1 by themselves and the next call is suggested (atc/atc_assist.gd)
	"atc_voice": false,  # say ATC transmissions with the OS text-to-speech voice (atc/atc_voice.gd)
}
const CHOICES := {
	"alt_unit": ["ft", "m"],
	"speed_unit": ["kt", "km/h"],
	"pressure_unit": ["inHg", "hPa"],
	"keyboard_mode": ["spring", "sticky"],
	"control_smoothing": ["off", "light", "strong"],
	"ui_scale": ["Auto", "100%", "125%", "150%", "200%"],
}

static var _v := {}


static func get_v(key: String) -> Variant:
	if _v.is_empty():
		_v = DEFAULTS.duplicate()
		var cf := ConfigFile.new()
		if cf.load(CFG) == OK:
			for k in DEFAULTS:
				_v[k] = cf.get_value("options", k, DEFAULTS[k])
	return _v.get(key, DEFAULTS.get(key))


static func set_v(key: String, value: Variant) -> void:
	get_v(key)
	_v[key] = value
	var cf := ConfigFile.new()
	for k in _v:
		cf.set_value("options", k, _v[k])
	cf.save(CFG)
