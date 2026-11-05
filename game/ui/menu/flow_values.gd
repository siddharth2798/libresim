class_name FlowValues
extends RefCounted
## What the Free-flight rail and footer chips say about the setup: one live value line per step, its
## status level and its tooltip. Pure functions over a Session.setup-shaped Dictionary and the
## SetupChecks list (no nodes), so they are testable headless. Steps are keyed like SetupChecks:
## "aircraft" | "livery" | "airport" | "weather" | "failures" | "recording" (the order of start_flow.gd STEPS).
## Level: "ok" ready, "warn" / "bad" from SetupChecks.step_level, "none" = an optional step with nothing chosen.

const KEYS := ["aircraft", "livery", "airport", "weather", "failures", "recording"]
const TITLES := {"aircraft": "Aircraft", "livery": "Livery", "airport": "Airport & start", "weather": "Weather & time", "failures": "Failures", "recording": "Recording"}
const OPTIONAL := ["livery", "failures", "recording"]
const ConditionsPage := preload("res://ui/menu/conditions_page.gd")


## The one-line live value under a step in the rail, e.g. "A320-family · 8500 kg fuel".
static func rail_value(key: String, s: Dictionary) -> String:
	match key:
		"aircraft":
			var ac := AircraftDef.load_def(str(s.get("aircraft", "")))
			if ac == null:
				return "No aircraft"
			var fuel := WeightBalance.fuel_total(ac.data, s)
			return "%s · %d %s fuel" % [_name(ac), roundi(fuel), "kg" if WeightBalance.fuel_in_kg(ac.data) else "gal"]
		"livery":
			return _paint(s, false)
		"airport":
			return _start(s, false)
		"weather":
			return _weather(s, false)
		"failures":
			var n := armed_count(s)
			return "%d armed%s" % [n, " + random" if _random(s) else ""]
		"recording":
			return _rec(s, false)
	return ""


## The shorter text of a footer chip, e.g. "A320 · 64.5 t".
static func chip_text(key: String, s: Dictionary) -> String:
	match key:
		"aircraft":
			var ac := AircraftDef.load_def(str(s.get("aircraft", "")))
			if ac == null:
				return "No aircraft"
			var kg := WeightBalance.takeoff_kg(ac.data, s)
			return "%s · %s" % [_name(ac).replace("-family", ""), "%.1f t" % (kg / 1000.0) if kg > 9999.0 else "%d kg" % roundi(kg)]
		"livery":
			return _paint(s, true)
		"airport":
			return _start(s, true)
		"weather":
			return _weather(s, true)
		"failures":
			var n := armed_count(s)
			var f := "No failures" if n == 0 else "%d failure%s" % [n, "" if n == 1 else "s"]
			return f if not _random(s) else (("%s + random" % f) if n > 0 else "Random failures")
		"recording":
			return _rec(s, true)
	return ""


## Status level of a step: SetupChecks for the first three, "ok" / "none" for the optional two.
static func level(key: String, s: Dictionary, list: Array) -> String:
	match key:
		"livery":
			return "ok" if _paint_custom(s) else "none"
		"failures":
			return "ok" if armed_count(s) > 0 or _random(s) else "none"
		"recording":
			return "ok" if bool(s.get("record", false)) else "none"
	return SetupChecks.step_level(list, key)


## Tooltip of a rail entry or chip: what the step holds, then the problems of that step (SetupChecks texts).
static func tooltip(key: String, s: Dictionary, list: Array, index := -1) -> String:
	var lines: Array[String] = []
	var head := "%s: %s" % [TITLES[key], rail_value(key, s)]
	if key == "aircraft":
		var ac := AircraftDef.load_def(str(s.get("aircraft", "")))
		if ac != null:
			head += "  (takeoff weight %d kg)" % roundi(WeightBalance.takeoff_kg(ac.data, s))
	lines.append(head)
	for c in list:
		if c.step == key:
			lines.append(("Problem: " if c.level == "bad" else "Note: ") + str(c.text))
	lines.append("Click to change" + (" (key %d)" % (index + 1) if index >= 0 else ""))
	return "\n".join(lines)


## [title, one line] for the readiness box at the top of the rail.
static func ready_text(list: Array) -> Array[String]:
	match SetupChecks.worst(list):
		"bad":
			return ["Check before flying", "You can still fly; you will feel it."]
		"warn":
			return ["%d thing%s to look at" % [list.size(), "" if list.size() == 1 else "s"], "Nothing stops you flying."]
	return ["Ready to fly", "Everything has a sensible default."]


## The Fly button's label: "Fly anyway" (and amber, in start_flow.gd) when a check is "bad", else "Fly now".
static func fly_label(list: Array) -> String:
	return "Fly anyway  ▶" if SetupChecks.worst(list) == "bad" else "Fly now  ▶"


## Failures that are armed (mode above 0), not counting the random option.
static func armed_count(s: Dictionary) -> int:
	var n := 0
	var f = s.get("failures", {})
	for id in f:
		if int(f[id][0]) > 0:
			n += 1
	return n


static func _paint(s: Dictionary, short: bool) -> String:
	var id := str(s.get("aircraft", ""))
	var ac := AircraftDef.load_def(id)
	var lv := {} if ac == null else Livery.of(ac)
	if lv.get("regions", []).is_empty() and lv.get("stickers", []).is_empty():
		return "No paint" if short else "Nothing to paint"
	if not _paint_custom(s):
		return "Factory"
	var colors := Livery.colors_of(lv, Livery.entry(s.get("livery"), id))
	var n := 0
	for r in lv.regions:
		if Livery.to_hex(colors[r.key]) != Livery.to_hex(r.default):
			n += 1
	var bits := PackedStringArray()
	if n > 0:
		bits.append("%d colour%s" % [n, "" if n == 1 else "s"])
	if _has_stickers(s):
		bits.append("stickers")
	return ", ".join(bits)


static func _paint_custom(s: Dictionary) -> bool:
	var id := str(s.get("aircraft", ""))
	var ac := AircraftDef.load_def(id)
	if ac == null:
		return false
	var lv := Livery.of(ac)
	if lv.regions.is_empty() and lv.stickers.is_empty():
		return false
	var e := Livery.entry(s.get("livery"), id)
	return not Livery.is_identity(lv, Livery.colors_of(lv, e)) or _has_stickers(s)


static func _has_stickers(s: Dictionary) -> bool:
	var e := Livery.entry(s.get("livery"), str(s.get("aircraft", "")))
	return e.get("stickers") is Dictionary and not e.stickers.is_empty()


static func _random(s: Dictionary) -> bool:
	return bool((s.get("random", {}) as Dictionary).get("enabled", false))


static func _name(ac: AircraftDef) -> String:
	return str(ac.data.get("short_name", ac.id))


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	for i in range(t.length() - 3, 0, -3):
		t = t.insert(i, ",")
	return ("-" if n < 0 else "") + t


static func _start(s: Dictionary, short: bool) -> String:
	var icao := str(s.get("airport", ""))
	match str(s.get("start", "runway")):
		"stand":
			var st := StandNames.label(str(s.get("stand", "")))  # "stand 12", "Bay 3": one rule everywhere
			return "%s · %s" % [icao, st if st != "" else "gate"]
		"air":
			return "%s · %s ft · %s nm" % [icao, _thousands(roundi(float(s.get("air_ft", 0.0)))), Session.nm_text(float(s.get("air_nm", 0.0)))]
	var rw := str(s.get("runway", ""))
	if rw == "":
		rw = str(SetupChecks.runway_of(s).get("ident", "longest"))
	var cold := " · cold" if short else " · cold & dark"
	return "%s %s%s" % [icao, rw, cold if bool(s.get("cold", false)) else ""]


static func _weather(s: Dictionary, short: bool) -> String:
	var name: String = ConditionsPage.weather_match(s)
	var m := roundi(fmod(float(s.get("time_h", 12.0)), 24.0) * 60.0) % 1440
	var wind := float(s.get("wind_kt", 0.0))
	var gust := float(s.get("gust_kt", 0.0))
	return "%s · %02d:%02d · %s%03d/%d%s" % [name if name != "" else "Custom", m / 60, m % 60, "" if short else "wind ",
		roundi(float(s.get("wind_dir_deg", 0.0))), roundi(wind), ("G%d" % roundi(gust)) if gust > wind else ""]


static func _rec(s: Dictionary, short: bool) -> String:
	if not bool(s.get("record", false)):
		return "Rec off" if short else "Off"
	var h := int(s.get("record_height", 720))
	var body := "%s %d fps" % ["native" if h <= 0 else "%dp" % h, int(s.get("record_fps", 30))]
	return "● REC %s" % body if short else "On · " + body
