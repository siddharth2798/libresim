extends RefCounted
## A small made-up nav world for the route tests (no data files needed). Distances in nm, north up.
##   AAAA (0, 0) and BBBB (0, 200) with runway 18/36 each (AAAA also has a one-ended pad H1, "he": null), CCCC (0, 60), ZZZZ (0, -500) far from every airway.
##   V1 VOR (5, 100) near the AAAA-BBBB line, V2 VOR (60, 100) far off it, N1 NDB (0, 1) beside AAAA.
##   W1 (both ways)  FA (0, 10) - FB (30, 100) - FC (0, 190)
##   J9 (forward)    FC (0, 190) - FX (0, 100) - FA (0, 10)   shorter, but only from north to south
##   Q2 (both ways)  FQ1 (0, -480) - FQ2 (10, -480)           near ZZZZ, joined to nothing

const NM := 1852.0


static func p(e_nm: float, n_nm: float) -> Vector2:
	return Vector2(e_nm, n_nm) * NM


static func _airport(icao: String, name: String, at: Vector2) -> Dictionary:
	var rw := {"le": {"ident": "18", "x": at.x, "y": at.y + 1000.0, "heading_true": 180.0},
		"he": {"ident": "36", "x": at.x, "y": at.y - 1000.0, "heading_true": 0.0}}
	return {"ident": icao, "icao": icao, "name": name, "type": "medium_airport", "x": at.x, "y": at.y, "elev_m": 10.0,
		"runways": [rw], "freqs": []}


static func db() -> NavDatabase:
	var d := NavDatabase.new()
	d.airports = [_airport("AAAA", "Alpha Airport", p(0, 0)), _airport("BBBB", "Bravo Field Airport", p(0, 200)),
		_airport("CCCC", "Charlie Airport", p(0, 60)), _airport("ZZZZ", "Zulu Airport", p(0, -500))]
	d.airports[0].runways.push_front({"le": {"ident": "H1", "x": 0.0, "y": 0.0, "heading_true": 0.0}, "he": null})  # one-ended pad
	d.vors = [{"ident": "V1", "name": "V one", "mhz": 113.0, "x": p(5, 100).x, "y": p(5, 100).y, "h": 0.0, "var_deg": 0.0, "dme": true},
		{"ident": "V2", "name": "V two", "mhz": 114.0, "x": p(60, 100).x, "y": p(60, 100).y, "h": 0.0, "var_deg": 0.0, "dme": true}]
	d.ndbs = [{"ident": "N1", "name": "N one", "khz": 300.0, "x": p(0, 1).x, "y": p(0, 1).y, "h": 0.0}]
	d.ils = []
	d.coms = {}
	d.fixes = {"FA": p(0, 10), "FB": p(30, 100), "FC": p(0, 190), "FX": p(0, 100), "FQ1": p(0, -480), "FQ2": p(10, -480)}
	d.airways = {"W1": {"fixes": ["FA", "FB", "FC"], "direction": "both"},
		"J9": {"fixes": ["FC", "FX", "FA"], "direction": "forward"},
		"Q2": {"fixes": ["FQ1", "FQ2"], "direction": "both"}}
	return d


static func ids(wps: Array) -> Array:
	return wps.map(func(w): return str(w.id))
