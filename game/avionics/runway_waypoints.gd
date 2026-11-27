class_name RunwayWaypoints
extends RefCounted
## Synthetic departure and arrival fixes from a runway end the sim already stores.
## Ident is ICAO + runway + D (5 nm ahead of the threshold, along the runway heading)
## or F (8 nm out on the extended centreline), or a base fix B / A (5 nm abeam F, right / left of the final course as flown):
## the GPS puts one before F when the aircraft would have to turn back at F (base_for, avionics/gps.gd). Not a published SID
## or STAR. Published airways are expanded separately (airway.gd).


const DEP_M := 5.0 * 1852.0
const ARR_M := 8.0 * 1852.0
const BASE_M := 5.0 * 1852.0
const REVERSAL_COS := -0.3  # the leg into F points this much against the landing direction (a turn of about 107 deg or more at F)

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
	var at := Vector2(float(end.x), float(end.y)) + along * dist * sign
	if p.kind == "B" or p.kind == "A":  # abeam F: right (B) or left (A) of the final course
		at += Vector2(along.y, -along.x) * BASE_M * (1.0 if p.kind == "B" else -1.0)
	return at


## The base fix to fly before the arrival fix `f_ident` from `from` (Vector2 ENU), or "" when none is needed: only when the leg
## into F would point back against the landing direction (the aircraft is on the runway side of F, as a route arriving from
## behind the airport is). The side is the one the aircraft is on (right when on the line). Without it the aircraft turned
## 180 deg at F and rolled out 2 km off the centreline inside the glide slope intercept: no LOC / G/S capture in time.
static func base_for(f_ident: String, from: Vector2, airports: Array) -> String:
	var p := parse(f_ident)
	if p.is_empty() or str(p.kind) != "F":
		return ""
	var f: Variant = position(f_ident, airports)
	var end := runway_end(airports, str(p.icao), str(p.rwy))
	if f == null or end.is_empty() or from.distance_to(f) < 1.0:
		return ""
	var hdg := deg_to_rad(float(end.get("heading_true", 0.0)))
	var along := Vector2(sin(hdg), cos(hdg))
	if ((f as Vector2) - from).normalized().dot(along) > REVERSAL_COS:
		return ""
	var right := (from - (f as Vector2)).dot(Vector2(along.y, -along.x)) >= 0.0
	return ident(str(p.icao), str(p.rwy), "B" if right else "A")


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
				var e: Variant = rw.get(side)
				if e is Dictionary and normalize(str(e.get("ident", ""))) == want:  # a one-ended runway (helipad, strip) has a null end
					return e
	return {}


static func _pattern() -> RegEx:
	if _re == null:
		_re = RegEx.new()
		_re.compile("^([A-Z]{4})([0-9]{2}[LRC]?)([DFAB])$")
	return _re
