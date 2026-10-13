class_name AtcSlots
extends RefCounted
## Fills the {slots} of the phrases from the world snapshot and the controller state (see
## atc_phraseology.gd for the formats; every slot in AtcPhraseology.SAMPLE is always present).

const DIRS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


static func build(c: AtcController, w: Dictionary, extra := {}) -> Dictionary:
	var tuned := AtcFacilities.tuned(w)
	var apt_name := str(w.get("apt_name", ""))
	var name: String = tuned.name if tuned.name != "" else apt_name + " ATC"
	var rwy := c.runway_for(w)
	var routes: Dictionary = AtcFacilities.config().get("departure_routes", {})
	var sl := {
		"callsign": c.s.callsign, "fac": name, "fac2": name, "apt": apt_name, "rwy": rwy,
		"freq": float(w.get("com1_mhz", 118.1)), "freq2": float(w.get("com1_mhz", 118.1)), "freq3": float(w.get("com1_mhz", 118.1)),
		"wind": [float(w.get("wind_dir", 0.0)), float(w.get("wind_kt", 0.0)), float(w.get("gust_kt", 0.0))],
		"qnh": float(w.get("qnh", 1013.0)), "squawk": c.s.squawk, "info": c.info_word(),
		"vis": float(w.get("vis", 20000.0)), "temp": float(w.get("temp", 15.0)), "clouds": _clouds(w),
		"alt": Units.m_to_ft(float(w.get("alt", 0.0))), "alt_limit": AtcController.ALT_LIMIT_FT, "pos": pos_text(w),
		"where": str(w.get("where", "the apron")), "join": "", "opt_via": "",
		"opt_info": ("information %s, " % c.info_word()) if c.s.info_heard else "",
		"opt_route": ("via %s, " % routes[w.get("apt", "")]) if routes.get(w.get("apt", ""), "") != "" else "",
		"opt_wx": _wx(w)}
	sl.merge(extra, true)
	return sl


static func _clouds(w: Dictionary) -> Array:
	var cc := float(w.get("cloud_cover", 0.0))
	if cc < 0.1:
		return ["", 0.0]
	return ["few" if cc < 0.35 else "scattered" if cc < 0.55 else "broken" if cc < 0.85 else "overcast", float(w.get("cloud_base_ft", 3000.0))]


static func _wx(w: Dictionary) -> String:
	var p := float(w.get("precip", 0.0))
	return "heavy rain, " if p > 0.6 else "moderate rain, " if p > 0.3 else "light rain, " if p > 0.05 else ""


## "8 miles south-west of the field" / "overhead the field".
static func pos_text(w: Dictionary) -> String:
	var d: Vector2 = Vector2(w.get("pos", Vector2.ZERO)) - Vector2(w.get("apt_pos", Vector2.ZERO))
	var nm := d.length() / 1852.0
	if nm < 1.0:
		return "overhead the field"
	var brg := fposmod(rad_to_deg(atan2(d.x, d.y)), 360.0)  # from the airport to the aircraft
	var n := int(round(nm))
	return "%d mile%s %s of the field" % [n, "" if n == 1 else "s", DIRS[int(round(brg / 45.0)) % 8]]
