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
	"keyboard_mode": "spring",  # spring: yoke keys re-centre on release | sticky: stay put (FlightGear)
	"control_smoothing": "light",  # low-pass on pilot inputs before the FDM (fdm_node.gd)
	"auto_coordination": false,  # rudder follows aileron (for keyboard / no-pedal pilots)
	"callouts": false,  # optional training callouts (ui/callouts.gd), K toggles in flight
	"callouts_voice": false,  # say them with the OS text-to-speech voice, if the system has one
}
const CHOICES := {
	"alt_unit": ["ft", "m"],
	"speed_unit": ["kt", "km/h"],
	"pressure_unit": ["inHg", "hPa"],
	"keyboard_mode": ["spring", "sticky"],
	"control_smoothing": ["off", "light", "strong"],
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
