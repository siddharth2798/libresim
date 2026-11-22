class_name RouteTerrain
extends RefCounted
## The planned route against the terrain (the Route step's profile strip and RouteChecks). Pure maths over a height
## Callable(east, north) -> metres, so the tests run without terrain data.
## Legs follow RouteSetup.leg_alts: the leg into waypoint i flies wps[i].alt_ft, the leg into the destination the last
## waypoint's (cruise_ft without waypoints). The route is sampled every STEP_M (coarser on very long routes, at most
## MAX_SAMPLES), every leg end included. Samples within TERMINAL_M of the departure or the destination are the take-off
## and landing (the aircraft is near the ground there by design): drawn, never judged.
## A sample is "low" when the planned altitude is under terrain + MARGIN_FT, "below" when it is under the terrain itself.

const FT := 0.3048
const NM := 1852.0
const STEP_M := 0.5 * NM
const MAX_SAMPLES := 600
const TERMINAL_M := 2.0 * NM
const MARGIN_FT := 1000.0

static var _memo_sig := ""
static var _memo := {}


## The route as points and leg altitudes: {pts: [Vector2], ids: [String], alts: [ft per leg], dep: bool (pts[0] is the
## departure airport), dest: bool (the last point is the destination)}. Unknown departure / destination are left out.
static func path(setup: Dictionary, d: NavDatabase) -> Dictionary:
	var r := RouteSetup.repair(setup.get("route", {}))
	var out := {"pts": [], "ids": [], "alts": [], "dep": false, "dest": false}
	if not RouteSetup.active(r) or d == null:
		return out
	var dep: Variant = d.position_of(str(setup.get("airport", "")))
	if dep != null:
		out.pts.append(dep)
		out.ids.append(str(setup.airport))
		out.dep = true
	for w in r.wps:
		out.pts.append(Vector2(float(w.x), float(w.y)))
		out.ids.append(str(w.id))
	var dp: Variant = d.position_of(str(r.dest)) if str(r.dest) != "" else null
	if dp != null:
		out.pts.append(dp)
		out.ids.append(str(r.dest))
		out.dest = true
	var alts: Array = RouteSetup.leg_alts(r)  # one per waypoint, then the destination leg
	if dp == null and str(r.dest) != "":
		alts.pop_back()
	if dep == null and not alts.is_empty():
		alts.pop_front()  # no departure: the first waypoint starts the route, it ends no leg
	out.alts = alts
	return out


## Samples along `pts` (legs flown at `alts`): [{d_m, x, y, terrain_ft, alt_ft, leg, terminal}].
static func sample(pts: Array, alts: Array, height: Callable, dep := true, dest := true) -> Array:
	var out := []
	if pts.size() < 2:
		return out
	var total := 0.0
	for k in range(1, pts.size()):
		total += (pts[k - 1] as Vector2).distance_to(pts[k])
	var step := maxf(STEP_M, total / MAX_SAMPLES)
	var first: Vector2 = pts[0]
	var last: Vector2 = pts.back()
	var cum := 0.0
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		var len := a.distance_to(b)
		var n := maxi(ceili(len / step), 1)
		var alt := float(alts[k - 1]) if k - 1 < alts.size() else 0.0
		for i in range(0 if k == 1 else 1, n + 1):
			var p := a.lerp(b, float(i) / n)
			var near := (dep and p.distance_to(first) < TERMINAL_M) or (dest and p.distance_to(last) < TERMINAL_M)
			out.append({"d_m": cum + len * float(i) / n, "x": p.x, "y": p.y, "terrain_ft": float(height.call(p.x, p.y)) / FT,
				"alt_ft": alt, "leg": k - 1, "terminal": near})
		cum += len
	return out


## The worst of the judged samples: {clear_ft (lowest altitude above the terrain; INF when nothing is judged), leg (its
## leg, -1), below_leg (first leg under the terrain, -1), low_leg (first leg under terrain + MARGIN_FT, -1),
## top_ft (highest terrain on the route, terminal samples too)}.
static func verdict(samples: Array) -> Dictionary:
	var out := {"clear_ft": INF, "leg": -1, "below_leg": -1, "low_leg": -1, "top_ft": 0.0}
	for s in samples:
		out.top_ft = maxf(out.top_ft, float(s.terrain_ft))
		if s.terminal:
			continue
		var c := float(s.alt_ft) - float(s.terrain_ft)
		if c < out.clear_ft:
			out.clear_ft = c
			out.leg = int(s.leg)
		if c < 0.0 and out.below_leg < 0:
			out.below_leg = int(s.leg)
		if c < MARGIN_FT and out.low_leg < 0:
			out.low_leg = int(s.leg)
	return out


## Whether a sample is drawn as a problem (red): judged and under terrain + MARGIN_FT.
static func is_low(s: Dictionary) -> bool:
	return not s.terminal and float(s.alt_ft) < float(s.terrain_ft) + MARGIN_FT


## Path, samples and verdict of the setup's route: {pts, ids, alts, dep, dest, samples, verdict, dep_ft, dest_ft}
## (dep_ft / dest_ft: terrain at the end airports, NAN when unknown). The last result is kept while the route and the
## height source are the same, so the start screen's checks and the profile strip share one sampling.
static func profile(setup: Dictionary, d: NavDatabase, height: Callable) -> Dictionary:
	var p := path(setup, d)
	var sig := JSON.stringify([p.pts, p.alts, p.dep, p.dest]) + str(height.hash())
	if sig == _memo_sig:
		return _memo
	p.samples = sample(p.pts, p.alts, height, p.dep, p.dest)
	p.verdict = verdict(p.samples)
	p.dep_ft = float(p.samples[0].terrain_ft) if p.dep and not p.samples.is_empty() else NAN
	p.dest_ft = float(p.samples.back().terrain_ft) if p.dest and not p.samples.is_empty() else NAN
	_memo_sig = sig
	_memo = p
	return p


## "leg 2 to PAPRI" for messages.
static func leg_name(p: Dictionary, leg: int) -> String:
	var ids: Array = p.get("ids", [])
	return "leg %d to %s" % [leg + 1, ids[leg + 1]] if leg + 1 < ids.size() else "leg %d" % (leg + 1)
