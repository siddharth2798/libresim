class_name IlsPick
extends RefCounted
## Which ILS to tune, as pure functions (no Props); avionics/ils_autotune.gd feeds them and tunes NAV2.
## A station is a NavDatabase.ils entry {ident, airport, runway, mhz, course_true, loc{x,y,h}, gs, gs_deg, threshold{x,y,h}}.
## Two sources, the route first:
##   route    the arrival runway of the plan (MCDU ARR RWY, or the route's destination without one): when the aircraft is
##            within ROUTE_NM of the destination, or in the descent. Without an arrival runway the ILS whose course points
##            most nearly along the line from the aircraft to the airport (the straight-in runway) is chosen.
##   lineup   no plan, or the plan has no ILS: a runway ahead (before its threshold, at most LINEUP_NM away, in the
##            localizer sector LINEUP_SECTOR_DEG), whose course is within LINEUP_TRACK_DEG of the aircraft's track and
##            not more than LINEUP_ABOVE_M above its threshold (the limit is lifted when the pilot armed LOC / APPR).
## When both give an ILS, the lineup one wins only when it is a different one and nearer than the route's.

const NM := 1852.0
const ROUTE_NM := 100.0  # tune the destination's ILS from here
const LINEUP_NM := 25.0
const LINEUP_TRACK_DEG := 30.0
const LINEUP_SECTOR_DEG := 30.0
const LINEUP_ABOVE_M := 1828.8  # 6000 ft above the threshold


## A record with what the pick needs: the airport and runway, the course and the threshold (real and simulated records alike;
## a record without them, or a one-ended runway's missing end, is skipped).
static func usable(s: Dictionary) -> bool:
	var th = s.get("threshold")
	return s.has("airport") and s.has("runway") and s.has("course_true") and th is Dictionary and th.has("x") and th.has("y")


## The ILS of runway `rwy` ("27", "9L") of the airport whose names (ICAO and ident) are `names`; {} when it has none.
static func for_runway(stations: Array, names: Array, rwy: String) -> Dictionary:
	var want := RunwayWaypoints.normalize(rwy)
	for s in stations:
		if usable(s) and str(s.airport) in names and RunwayWaypoints.normalize(str(s.runway)) == want:
			return s
	return {}


## The airport's ILS the aircraft at `pos` (ENU, m) flies most nearly straight in to, {} when it has none.
static func straight_in(stations: Array, names: Array, pos: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for s in stations:
		if not usable(s) or not str(s.airport) in names:
			continue
		var th := Vector2(s.threshold.x, s.threshold.y)
		var brg := rad_to_deg(atan2(th.x - pos.x, th.y - pos.y))
		var d := absf(wrapf(float(s.course_true) - brg, -180.0, 180.0))
		if d < bd:
			bd = d
			best = s
	return best


## Distance (nm) to `s`'s threshold, and the angle (deg) off its course line, for the aircraft at `pos` flying `track_rad`
## (true): {ok, dist_nm, off_deg, track_deg, above_m}. ok = ahead of the threshold, in the sector, track within the limit.
static func geometry(s: Dictionary, pos: Vector3, track_rad: float) -> Dictionary:
	var th := Vector2(s.threshold.x, s.threshold.y)
	var c := deg_to_rad(float(s.course_true))
	var u := Vector2(sin(c), cos(c))
	var rel := Vector2(pos.x, pos.y) - th
	var along := rel.dot(u)  # < 0: before the threshold, on the approach side
	var across := absf(rel.cross(u))
	var off := rad_to_deg(atan2(across, maxf(-along, 0.001))) if along < 0.0 else 180.0
	var dtrack := absf(wrapf(rad_to_deg(track_rad) - float(s.course_true), -180.0, 180.0))
	return {"ok": along < 0.0 and off <= LINEUP_SECTOR_DEG and dtrack <= LINEUP_TRACK_DEG and rel.length() <= LINEUP_NM * NM,
		"dist_nm": rel.length() / NM, "off_deg": off, "track_deg": dtrack, "above_m": pos.z - float(s.threshold.get("h", 0.0))}


## The ILS of the runway the aircraft is lined up to ({} when none). `armed`: the pilot armed LOC / APPR (no height limit).
static func lined_up(stations: Array, pos: Vector3, track_rad: float, armed: bool) -> Dictionary:
	var best := {}
	var bs := INF
	for s in stations:
		if not usable(s):
			continue
		var g := geometry(s, pos, track_rad)
		if not g.ok or (not armed and g.above_m > LINEUP_ABOVE_M):
			continue
		var score: float = g.off_deg + g.track_deg + g.dist_nm * 0.2
		if score < bs:
			bs = score
			best = s
	return best


## What to tune. `c`: {stations, names (of the plan's destination, [] without one), dest (Vector2 or null), arr_rwy, pos
## (Vector3 ENU), track (rad true), phase ("DES" or "APPR" in the descent), armed}. Returns {s (station or {}), why ("route" | "lineup" | "")}.
static func wanted(c: Dictionary) -> Dictionary:
	var pos: Vector3 = c.pos
	var route := {}
	var route_dist := INF
	if not (c.names as Array).is_empty() and c.dest is Vector2:
		route_dist = Vector2(pos.x, pos.y).distance_to(c.dest)
		if route_dist <= ROUTE_NM * NM or str(c.get("phase", "")) in ["DES", "APPR"]:
			if str(c.arr_rwy).strip_edges() != "":
				route = for_runway(c.stations, c.names, str(c.arr_rwy))
			else:
				route = straight_in(c.stations, c.names, Vector2(pos.x, pos.y))
	var line := lined_up(c.stations, pos, float(c.track), bool(c.get("armed", false)))
	if not line.is_empty() and (route.is_empty() or (line != route and geometry(line, pos, float(c.track)).dist_nm * NM < route_dist)):
		return {"s": line, "why": "lineup"}
	if not route.is_empty():
		return {"s": route, "why": "route"}
	return {"s": {}, "why": ""}
