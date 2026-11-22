extends RefCounted
## Cockpit hover note words for the A320 glareshield (FCU and both EFIS panels), used by cockpit_tip_text.gd:
## names of the hotspot controls, how a knob is worked, and what each new setting reads.

const NAMES := {
	"spd_mach": "SPD/MACH", "trk_fpa": "HDG-V/S / TRK-FPA", "metric_alt": "Metric altitude", "alt_inc": "Altitude step 100 / 1000",
	"fd": "Flight director (FD)", "ls": "Landing system (LS)", "baro": "Baro", "nd_mode": "ND mode", "nd_range": "ND range",
	"cstr": "Constraints (CSTR)", "wpt": "Waypoints (WPT)", "vord": "VOR / DME (VOR.D)", "ndb": "NDB", "arpt": "Airports (ARPT)",
}
const KNOBS := ["controls/fcu/hdg_deg", "controls/fcu/spd_kt", "controls/fcu/alt_ft", "controls/fcu/vs_fpm", "controls/baro/hpa"]
const FILTERS := ["None", "CSTR", "WPT", "VOR.D", "NDB", "ARPT"]


## "Captain baro" for baro_cpt; "" when the id is not one of ours.
static func title(id: String) -> String:
	var base := id.trim_suffix("_cpt").trim_suffix("_fo")
	if not NAMES.has(base):
		return ""
	if base == id:
		return str(NAMES[base])
	return "%s %s" % ["First officer" if id.ends_with("_fo") else "Captain", str(NAMES[base]).to_lower() if base == "baro" else NAMES[base]]


## How the knob is worked (appended to the key line), "" for anything else.
static func hint(drive: String) -> String:
	if drive in KNOBS:
		return "drag to turn · click push · Shift+click pull"
	if drive == "controls/nd/mode" or drive == "controls/nd/range_nm":
		return "drag or click to turn"
	return ""


static func state(path: String, value: Variant) -> String:
	match path:
		"controls/baro/hpa":
			if Props.get_b("controls/baro/std"):
				return "STD"
			return "%d hPa" % roundi(Props.get_f("controls/baro/hpa", Props.get_f("weather/qnh_hpa", 1013.25)))
		"controls/nd/mode":
			return "ROSE" if _num(value) >= 0.5 else "ARC"
		"controls/nd/range_nm":
			return "%d NM" % roundi(_num(value) if _num(value) > 0.0 else 40.0)
		"controls/efis/nd_filter":
			return FILTERS[clampi(roundi(_num(value)), 0, 5)]
		"controls/fcu/alt_inc_1000":
			return "1000 ft" if _num(value) >= 0.5 else "100 ft"
		"controls/fcu/spd_mach":
			return "MACH" if _num(value) >= 0.5 else "SPD"
		"controls/fcu/trk_fpa":
			return "TRK-FPA" if _num(value) >= 0.5 else "HDG-V/S"
		"controls/fcu/hdg_deg":
			return "Managed (NAV)" if Props.get_b("controls/fcu/hdg_managed") else ""
		"controls/fcu/spd_kt":
			return "Managed" if Props.get_b("controls/fcu/spd_managed") else ""
	return ""


static func _num(value: Variant) -> float:
	if value == null:
		return 0.0
	return (1.0 if value else 0.0) if value is bool else float(value)
