class_name RunwayWaypoints
extends RefCounted
## Synthetic departure and arrival fixes from a runway end the sim already stores.
## Ident is ICAO + runway + D (5 nm ahead of the threshold, along the runway heading)
## or F (8 nm out on the extended centreline). Not a published SID or STAR.
## Published airways are expanded separately (airway.gd).


const DEP_M := 5.0 * 1852.0
const ARR_M := 8.0 * 1852.0

static var _re: RegEx


static func ident(icao: String, rwy: String, kind: String) -> String:
	return str(icao).to_upper() + normalize(rwy) + kind


## "9" and "9L" become "09" and "09L". "RWY 27" becomes "27".
static func normalize(rwy: String) -> String:
	var s := rwy.strip_edges().to_upper().replace(" ", "")
	if s.begins_with("RWY"):
		s = s.substr(3)
	var side := s.length() == 2 and s.substr(1, 1) in ["L", "R", "C"]
	if s.length() == 1 or side:
		s = "0" + s
	return s


## {icao, rwy, kind} or {} when `ident` is not a synthetic fix.
static func parse(ident: String) -> Dictionary:
	var m := _pattern().search(ident.strip_edges().to_upper())
	if m == null:
		return {}
	return {"icao": m.get_string(1), "rwy": m.get_string(2), "kind": m.get_string(3)}


## Vector2 ENU, or null. `airports` is the NavDatabase list (ident, icao, runways).
static func position(ident: String, airports: Array) -> Variant:
	var p := parse(ident)
	if p.is_empty():
		return null
	var end := runway_end(airports, str(p.icao), str(p.rwy))
	if end.is_empty():
		return null
	var hdg := deg_to_rad(float(end.get("heading_true", 0.0)))
	var along := Vector2(sin(hdg), cos(hdg))
	var dist := DEP_M if p.kind == "D" else ARR_M
	var sign := 1.0 if p.kind == "D" else -1.0
	return Vector2(float(end.x), float(end.y)) + along * dist * sign


static func runway_end(airports: Array, icao: String, rwy: String) -> Dictionary:
	var want := normalize(rwy)
	var id := icao.to_upper()
	for a in airports:
		var icao_a := str(a.get("icao", "")).to_upper()
		var ident_a := str(a.get("ident", "")).to_upper()
		if icao_a != id and ident_a != id:
			continue
		for rw in a.get("runways", []):
			for side in ["le", "he"]:
				var e: Dictionary = rw.get(side, {})
				if normalize(str(e.get("ident", ""))) == want:
					return e
	return {}


static func _pattern() -> RegEx:
	if _re == null:
		_re = RegEx.new()
		_re.compile("^([A-Z]{4})([0-9]{2}[LRC]?)([DF])$")
	return _re
