class_name NavDatabase
extends RefCounted
## Radio navaids for the receivers: VOR/VOR-DME and NDB from navaids.json (OurAirports,
## real), ILS from ils.json (geometry real, frequencies SIMULATED, see tools/14_ils.py),
## and COM frequencies per airport (OurAirports airport-frequencies, real).
## Positions in world ENU metres. Station elevation used for line-of-sight.

var vors: Array = []  # {ident, name, mhz, x, y, h, var_deg, dme}
var ndbs: Array = []  # {ident, name, khz, x, y, h}
var ils: Array = []   # {ident, airport, runway, mhz, course_true, loc{x,y,h}, gs{x,y,h}, gs_deg, threshold}
var coms: Dictionary = {}  # airport icao -> [{type, desc, mhz}]
var airports: Array = []


func _init() -> void:
	var n = Paths.load_json("navaids.json")
	for v in (n if n else []):
		var h: float = v.get("elev_m", 0.0)
		if str(v.type).begins_with("VOR"):
			vors.append({"ident": v.ident, "name": v.name, "mhz": float(v.khz) / 1000.0, "x": v.x, "y": v.y,
				"h": h + 5.0, "var_deg": v.get("mag_var_deg", -0.3) if v.get("mag_var_deg") != null else -0.3,
				"dme": str(v.type).contains("DME")})
		elif str(v.type).begins_with("NDB"):
			ndbs.append({"ident": v.ident, "name": v.name, "khz": float(v.khz), "x": v.x, "y": v.y, "h": h + 10.0})
	var il = Paths.load_json("ils.json")
	for s in (il if il else []):
		ils.append({"ident": s.ident, "airport": s.airport, "runway": s.runway, "mhz": float(s.freq_mhz),
			"course_true": float(s.course_true), "loc": s.loc, "gs": s.gs, "gs_deg": float(s.gs_deg),
			"threshold": s.threshold})
	var ap = Paths.load_json("airports.json")
	airports = ap if ap else []
	for a in airports:
		coms[a.icao if a.icao != "" else a.ident] = a.get("freqs", [])


## Station on a NAV frequency (VOR or ILS localizer), nearest if several share it.
func nav_station(mhz: float, from: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for v in vors:
		if absf(v.mhz - mhz) < 0.004:
			var d := from.distance_to(Vector2(v.x, v.y))
			if d < bd:
				bd = d
				best = {"kind": "VOR", "s": v}
	for s in ils:
		if absf(s.mhz - mhz) < 0.004:
			var d2 := from.distance_to(Vector2(s.loc.x, s.loc.y))
			if d2 < bd:
				bd = d2
				best = {"kind": "ILS", "s": s}
	return best


func ndb_station(khz: float, from: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for n in ndbs:
		if absf(n.khz - khz) < 0.6:
			var d := from.distance_to(Vector2(n.x, n.y))
			if d < bd:
				bd = d
				best = n
	return best


## COM frequency -> {airport, type, desc} if any airport uses it.
func com_station(mhz: float) -> Dictionary:
	for icao in coms:
		for f in coms[icao]:
			if f.mhz != null and absf(float(f.mhz) - mhz) < 0.004:
				return {"airport": icao, "type": f.type, "desc": f.desc}
	return {}
