class_name ProcedureRoute
extends RefCounted
## A published SID and STAR (Procedures) put into a GPS route (RouteSetup.gps_plan, FlightPlan.with_procedures).
## insert(ids, ...) takes the route idents [waypoints..., destination] and returns
##   {ids, cstr, sid, star}: the SID's fixes first, the STAR's fixes before the destination (a fix the route already has next
##   to it is not repeated), and cstr = the constraints, ident -> {lo, hi, spd (0 = none), proc: "SID" | "STAR"}.
## The caller adds the runway fixes: no departure fix "D" when a SID is flown, the arrival fix "F" before the destination.
## A STAR that ends in ATC vectors (a VM leg, e.g. OPAKA 3K at BB257, FL100, 10 nm from the final fix) gets a vectors point
## <ICAO><RWY>V on the published heading, as far out as the descent from the STAR's last altitude to the arrival fix needs
## (VerticalProfile rates), so the GPS flies "the vectors" and then the final fix; none when the direct leg is long enough.
## Its position is kept in Procedures.points. Unknown names are ignored (sid / star come back "").

const NM := 1852.0
const VECTORS_MAX_NM := 60.0
const VECTORS_STEP_NM := 0.5


static func insert(ids: Array, dep: String, dep_rwy: String, sid: String, dest: String, arr_rwy: String, star: String,
		airports: Array) -> Dictionary:
	var out: Array = ids.duplicate()
	var cstr := {}
	var s := Procedures.find(dep, "SID", sid, dep_rwy) if dep_rwy != "" else {}
	var a := Procedures.find(dest, "STAR", star, arr_rwy) if arr_rwy != "" and dest != "" else {}
	if not s.is_empty():
		var fx := _fixes(s, "SID", cstr)
		if not out.is_empty() and not fx.is_empty() and str(out[0]) == str(fx.back()):
			out.pop_front()
		out = fx + out
	if not a.is_empty() and not out.is_empty() and str(out.back()) == dest:
		var fx := _fixes(a, "STAR", cstr)
		var at := out.size() - 1
		if at > 0 and not fx.is_empty() and str(out[at - 1]) == str(fx[0]):
			at -= 1
			out.remove_at(at)
		var v := vectors(a, dest, arr_rwy, airports)
		if v != "":
			fx.append(v)
		for i in fx.size():
			out.insert(at + i, fx[i])
	return {"ids": out, "cstr": cstr, "sid": str(s.get("name", "")), "star": str(a.get("name", ""))}


static func _fixes(p: Dictionary, proc: String, cstr: Dictionary) -> Array:
	var out: Array = []
	for g in p.get("legs", []):
		var id := str(g.fix)
		if not out.is_empty() and out.back() == id:
			continue
		out.append(id)
		var c := {"lo": float(g.get("lo_ft", 0.0)), "hi": float(g.get("hi_ft", 0.0)), "spd": float(g.get("spd_kt", 0.0)), "proc": proc}
		if c.lo > 0.0 or c.hi > 0.0 or c.spd > 0.0:
			cstr[id] = c
	return out


## The vectors point of STAR `p` into `dest` runway `rwy` ("" when the STAR has no vectors or the direct leg is long enough).
static func vectors(p: Dictionary, dest: String, rwy: String, airports: Array) -> String:
	if not p.has("vectors_true") or (p.legs as Array).is_empty():
		return ""
	var last: Dictionary = p.legs.back()
	var alt := float(last.get("hi_ft", last.get("lo_ft", 0.0)))
	var f_id := RunwayWaypoints.ident(dest, rwy, "F")
	var f: Variant = RunwayWaypoints.position(f_id, airports)
	var l: Variant = Procedures.fixes().get(str(last.fix))
	var ap := {}
	for x in airports:
		if str(x.get("icao", "")) == dest or str(x.get("ident", "")) == dest:
			ap = x
	if alt <= 0.0 or f == null or l == null or ap.is_empty():
		return ""
	var approach := Units.m_to_ft(float(ap.get("elev_m", 0.0))) + VerticalProfile.APPROACH_AGL_FT
	var need := (alt - approach) / VerticalProfile.FT_PER_NM + VerticalProfile.DECEL_NM \
		+ (VerticalProfile.LIMIT_DECEL_NM if alt > VerticalProfile.LIMIT_FT else 0.0)
	if (l as Vector2).distance_to(f) / NM >= need:
		return ""
	var h := deg_to_rad(float(p.vectors_true))
	var u := Vector2(sin(h), cos(h))
	var s := VECTORS_STEP_NM
	while s < VECTORS_MAX_NM:
		var v: Vector2 = (l as Vector2) + u * s * NM
		if s + v.distance_to(f) / NM >= need:
			break
		s += VECTORS_STEP_NM
	var id := RunwayWaypoints.ident(dest, rwy, "V")
	Procedures.points[id] = (l as Vector2) + u * s * NM
	return id
