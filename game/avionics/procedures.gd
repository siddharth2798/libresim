class_name Procedures
extends RefCounted
## Published SIDs and STARs (procedures.json, tools/31_procedures.py: AIP India supplements and AD 2.24 charts), parsed once
## per run and shared (static cache). A procedure is {name ("PPN3A"), rwy ("27"), legs: [{fix, lo_ft?, hi_ft?, spd_kt?}],
## vectors_true? (a STAR that ends in ATC vectors on this true heading), form ("rnav" | "conventional")}.
## lo_ft = at or above, hi_ft = at or below, both equal = at; spd_kt = at or below. Fix positions in ENU metres.
## Not every airport has them: Pune (VAPO) publishes SIDs only (its arrivals are radar vectored).

const FILE := "procedures.json"

static var _doc: Variant = null  # null = not read yet; {} = no file
static var _fixes: Dictionary = {}
## Points the route builder made (ProcedureRoute: the end of a STAR's vectors), ident -> Vector2; NavDatabase.position_of reads it.
static var points: Dictionary = {}


static func doc() -> Dictionary:
	if _doc == null:
		_doc = {}
		if FileAccess.file_exists(Paths.data(FILE)):
			var d = Paths.load_json(FILE)
			if d is Dictionary:
				_doc = d
				var fx: Dictionary = d.get("fixes", {})
				for id in fx:
					_fixes[str(id)] = Vector2(float(fx[id].x), float(fx[id].y))
	return _doc


## Tests: use this document instead of the file (null = read the file again).
static func use(d: Variant) -> void:
	_doc = d
	_fixes = {}
	points = {}
	if d is Dictionary:
		var fx: Dictionary = d.get("fixes", {})
		for id in fx:
			_fixes[str(id)] = Vector2(float(fx[id].x), float(fx[id].y))


static func fixes() -> Dictionary:
	doc()
	return _fixes


## The procedures of `kind` ("SID" | "STAR") at `icao`, for runway `rwy` ("" = every runway), sorted by name.
static func list(icao: String, kind: String, rwy := "") -> Array:
	var ap: Dictionary = doc().get("airports", {}).get(icao.to_upper(), {})
	var want := RunwayWaypoints.normalize(rwy) if rwy != "" else ""
	var out: Array = []
	for p in ap.get("sids" if kind == "SID" else "stars", []):
		if want == "" or RunwayWaypoints.normalize(str(p.rwy)) == want:
			out.append(p)
	out.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return out


static func names(icao: String, kind: String, rwy: String) -> Array:
	return list(icao, kind, rwy).map(func(p): return str(p.name))


## The procedure `name` for runway `rwy` at `icao`, or {}.
static func find(icao: String, kind: String, name: String, rwy: String) -> Dictionary:
	var n := name.strip_edges().to_upper().replace(" ", "")
	if n == "":
		return {}
	for p in list(icao, kind, rwy):
		if str(p.name) == n:
			return p
	return {}


## Short text of a constraint {lo, hi, spd} as the MCDU / ND show it: "+6000", "-FL120", "FL110", "FL110-FL120"; with a speed
## limit "230/+FL120". `ta_ft` = transition altitude (flight levels above it; the Mumbai tables write +6000 and -FL070).
static func text(c: Dictionary, ta_ft := 6000.0) -> String:
	var lo := float(c.get("lo", 0.0))
	var hi := float(c.get("hi", 0.0))
	var alt := ""
	if lo > 0.0 and hi > 0.0 and absf(lo - hi) < 1.0:
		alt = _alt(lo, ta_ft)
	elif lo > 0.0 and hi > 0.0:
		alt = "%s-%s" % [_alt(lo, ta_ft), _alt(hi, ta_ft)]
	elif lo > 0.0:
		alt = "+" + _alt(lo, ta_ft)
	elif hi > 0.0:
		alt = "-" + _alt(hi, ta_ft)
	var spd := float(c.get("spd", 0.0))
	return ("%d/" % roundi(spd) if spd > 0.0 else "") + alt


static func _alt(ft: float, ta_ft: float) -> String:
	return "FL%03d" % roundi(ft / 100.0) if ft > ta_ft else str(roundi(ft))
