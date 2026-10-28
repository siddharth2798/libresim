class_name AtcWorld
extends RefCounted
## The world as ATC sees it: snapshot() reads the property tree plus airport data into one
## flat dictionary (metres, seconds, degrees as noted), which the controller, the monitor
## and the facility rules work on. Tests pass hand-made dictionaries (blank() + overrides).
## env = make_env(airports, coms, runways, ops): NavDatabase.airports / .coms,
## AirportBuilder.data.runways and AirportOps.data, optional ils = NavDatabase.ils (airline phrases:
## ILS or visual approach, destination airport).

const GROUND_RANGE := 8000.0   # m: airport context while on the ground
const AIR_RANGE := 80000.0     # m: nearest airport while flying
const ALIGN_DEG := 25.0


static func blank() -> Dictionary:
	return {
		"t": 0.0, "pos": Vector2.ZERO, "wow": true, "gs": 0.0, "agl": 0.0, "alt": 0.0, "vs": 0.0, "hdg": 0.0,
		"com1_mhz": 118.1, "com1_ok": true, "com1_why": "",  # why: failed | unpowered
		"wind_dir": 270.0, "wind_kt": 8.0, "gust_kt": 0.0, "qnh": 1012.0, "vis": 20000.0, "temp": 30.0,
		"cloud_cover": 0.3, "cloud_base_ft": 4500.0, "precip": 0.0,
		"apt": "", "apt_name": "", "apt_type": "", "apt_pos": Vector2.ZERO, "apt_dist": 1e9, "apt_dist_nm": 1e9,
		"ils": [], "dest": "", "coms": [], "ctl": "none", "rwy": "", "rwy_hdg": 0.0,
		"on_runway": false, "aligned": false, "rwy_dist": 1e9, "appr": {}, "hold_dist": 1e9,
		"at_stand": false, "where": "the apron", "rwy_free": true, "taxi_route": "",
	}


static func make_env(airports: Array, coms: Dictionary, runways: Array, ops: Dictionary, ils := []) -> Dictionary:
	var has_rwy := {}
	for r in runways:
		has_rwy[r.airport] = true
	return {"airports": airports, "coms": coms, "runways": runways, "ops": ops, "has_rwy": has_rwy, "ils": ils}


static func snapshot(env: Dictionary, t: float) -> Dictionary:
	var w := blank()
	var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	w.t = t
	w.pos = Vector2(p3.x, p3.y)
	w.wow = Props.get_b("fdm/wow", true)
	w.gs = Props.get_f("fdm/groundspeed_mps")
	w.agl = Props.get_f("fdm/agl_m")
	w.alt = Props.get_f("fdm/alt_m")
	w.vs = Props.get_f("fdm/vs_mps")
	w.hdg = fposmod(rad_to_deg(Props.get_f("fdm/heading_rad")), 360.0)
	w.com1_mhz = Props.get_f("controls/com1/freq_mhz", 118.1)
	var powered := Props.get_b("systems/electrical/avionics_powered", true)
	w.com1_ok = not Props.get_b("failures/com1") and powered
	w.com1_why = "failed" if Props.get_b("failures/com1") else ("" if powered else "unpowered")
	for k in [["wind_dir", "wind_dir_deg", 270.0], ["wind_kt", "wind_kt", 0.0], ["gust_kt", "gust_kt", 0.0],
			["qnh", "qnh_hpa", 1013.0], ["vis", "visibility_m", 20000.0], ["temp", "temp_c", 15.0],
			["cloud_cover", "cloud_cover", 0.0], ["cloud_base_ft", "cloud_base_ft", 5000.0], ["precip", "precip", 0.0]]:
		w[k[0]] = Props.get_f("weather/" + k[1], k[2])
	w.rwy_free = not Props.get_b("atc/rwy_busy")
	w.taxi_route = str(Props.get_v("ops/taxi_route", ""))
	var ap := nearest_airport(env, w.pos, GROUND_RANGE if w.wow else AIR_RANGE)
	if not ap.is_empty():
		var icao: String = ap.icao
		w.apt = icao
		w.apt_name = AtcFacilities.apt_name(icao, str(ap.name))
		w.apt_type = str(ap.get("type", ""))
		w.apt_pos = Vector2(ap.x, ap.y)
		w.apt_dist = ap.dist
		w.apt_dist_nm = ap.dist / 1852.0
		w.coms = env.coms.get(icao, [])
		w.ils = env.get("ils", []).filter(func(i): return str(i.airport) == icao).map(func(i): return str(i.runway))
		w.dest = AtcProfile.dest_for(env, icao, w.apt_pos)
		w.ctl = AtcFacilities.control_mode(w.coms, w.apt_type, icao)
		var rwys: Array = env.runways.filter(func(r): return r.airport == icao)
		geometry(w, rwys, env.ops.get(icao, {}))
	return w


## Nearest airport that has a runway: {icao, name, type, x, y, dist} or {}.
static func nearest_airport(env: Dictionary, p: Vector2, max_m: float) -> Dictionary:
	var best := {}
	var bd := max_m
	for a in env.airports:
		var icao: String = a.icao if str(a.get("icao", "")) != "" else str(a.ident)
		if not env.has_rwy.has(icao):
			continue
		var d := p.distance_to(Vector2(a.x, a.y))
		if d < bd:
			bd = d
			best = {"icao": icao, "name": a.get("name", icao), "type": a.get("type", ""), "x": a.x, "y": a.y, "dist": d}
	return best


## Runway in use (into wind, longer runway breaks ties; same score as GroundOps) and where the
## aircraft is relative to the runways: on one, aligned with it, distance to the nearest edge,
## the approach corridor it is in, the nearest holding position, the stand it is parked at.
static func geometry(w: Dictionary, rwys: Array, ops: Dictionary) -> void:
	var p: Vector2 = w.pos
	var best_score := -INF
	var edge := 1e9
	var appr_cross := 1e9
	w.on_runway = false
	w.aligned = false
	w.appr = {}
	w.at_stand = false
	for r in rwys:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var half := maxf(float(r.width), 20.0) * 0.5 + 3.0
		var d := _seg_dist(p, a, b)
		var rwy_hdg := fposmod(rad_to_deg(atan2(b.x - a.x, b.y - a.y)), 360.0)
		edge = minf(edge, maxf(d - half, 0.0))
		if d <= half:
			w.on_runway = true
			w.aligned = minf(_ang(w.hdg, rwy_hdg), _ang(w.hdg, rwy_hdg + 180.0)) < ALIGN_DEG
		for e in r.ends:
			var hd := float(e.heading_true)
			var fwd := Vector2(sin(deg_to_rad(hd)), cos(deg_to_rad(hd)))
			var head := float(w.wind_kt) * cos(deg_to_rad(float(w.wind_dir) - hd))
			var score := GroundChoice.runway_score(head, float(r.length))  # too short for the aircraft: last
			if score > best_score:
				best_score = score
				w.rwy = str(e.ident)
				w.rwy_hdg = hd
			var rel := p - Vector2(e.x, e.y)
			var along := rel.dot(fwd)
			var cross := absf(rel.dot(Vector2(fwd.y, -fwd.x)))
			if along > -18500.0 and along < float(r.length) and cross < 600.0 and cross < appr_cross \
					and _ang(w.hdg, hd) < 50.0:
				appr_cross = cross
				w.appr = {"ident": str(e.ident), "along": along, "cross": cross, "tail_kt": -head}
	w.rwy_dist = edge
	var hd2 := 1e9
	for h in ops.get("holds", []):
		var hp := Vector2(h.x, h.y)
		var near_rwy := false
		for r in rwys:
			if _seg_dist(hp, Vector2(r.ends[0].x, r.ends[0].y), Vector2(r.ends[1].x, r.ends[1].y)) < 120.0:
				near_rwy = true
		if near_rwy:
			hd2 = minf(hd2, p.distance_to(hp))
	w.hold_dist = hd2
	var sd := 30.0
	for s in ops.get("stands", []):
		var d2 := p.distance_to(Vector2(s.x, s.y))
		if d2 < sd:
			sd = d2
			w.at_stand = true
			w.where = _stand_text(str(s.get("ref", "")))


static func _stand_text(ref: String) -> String:
	if ref == "":
		return "the apron"
	var low := ref.to_lower()
	return ref if low.begins_with("bay") or low.begins_with("stand") or low.begins_with("gate") else "stand " + ref


static func _ang(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Calls from the radio menu into the world (GroundOps): taxi guidance, pushback, tuning.
static func make_hooks(ground_ops: GroundOps) -> Dictionary:
	var push := func() -> String:
		ground_ops.start_pushback()
		return ""
	var taxi := func() -> String:
		Props.set_v("ops/taxi_route", "")
		ground_ops.request_taxi()
		return str(Props.get_v("ops/taxi_route", ""))
	var stand := func() -> String:
		return ground_ops.request_taxi_to_stand()
	var tune := func(mhz: float) -> void:
		Props.set_v("controls/com1/standby_mhz", Props.get_f("controls/com1/freq_mhz", 118.1))
		Props.set_v("controls/com1/freq_mhz", mhz)
	return {"start_pushback": push, "request_taxi": taxi, "taxi_to_stand": stand, "tune": tune}
