class_name OpsCorridors
extends RefCounted
## Where the aircraft is meant to be on an airport, as ObstacleRegistry corridors: every stand (parked
## footprint plus the pushback swing, see PushbackPath), every taxiway edge and every runway strip.
## Two uses: (1) OSM buildings and trees are forgiven while the aircraft's CG is inside one (their
## footprints are not survey-grade, normal ground operations must never crash); (2) ground dressing
## that would sit in one (parked vehicles, masts, windsocks) is dropped, drawn or not.

## Footprint about the CG (m) plus a 1.2 m margin: forward, aft (tail) and half span. The aircraft's
## aircraft.json "ground" section overrides them (ahead_m, behind_m, across_m, taxi_half_m); these are the C172's.
## The pushback swing is the arc PushbackFit would drive from that stand (published path when no taxiway
## lies behind it). Both tail directions are swept: the player may be sent either way.
const FOOTPRINT := {"ahead_m": 3.3, "behind_m": 7.4, "across_m": 6.7}
const TAXI_HALF := 8.0  # half width of a taxiway corridor
const RUNWAY_MARGIN := 10.0  # beyond the runway edge
const _Fit := preload("res://world/pushback_fit.gd")


## ops: one airport of airport_ops.json ({stands, taxi: {nodes, edges}}); runways: its runways.json entries;
## aircraft: null = the current one (tests pass their own).
static func register(icao: String, ops: Dictionary, runways: Array, aircraft: AircraftDef = null) -> void:
	var group := "corridor:" + icao
	ObstacleRegistry.remove_corridors(group)
	var def := aircraft if aircraft != null else AircraftDef.current()
	var fp := def.section_or("ground", FOOTPRINT)
	var ahead: float = fp.ahead_m
	var behind: float = fp.behind_m
	var across: float = fp.across_m
	var taxi_half := float(fp.get("taxi_half_m", TAXI_HALF))
	var pb := GroundParams.pushback(def)
	var taxi: Dictionary = ops.get("taxi", {})
	for s in ops.get("stands", []):
		var p0 := GroundParams.cg_at_stand(s, def)  # the CG sits behind a gate's door point
		var h0 := deg_to_rad(float(s.heading_deg))
		for side in [1.0, -1.0]:
			var fit: Dictionary = _Fit.plan(p0, h0, taxi, side, pb, def, true, false)
			for d in PushbackPath.samples(fit.straight, fit.radius, true, fit.turn):
				var pose := PushbackPath.pose(p0, h0, fit.side, d, fit.straight, fit.radius, fit.turn)
				var hd: float = pose[1]
				var c: Vector2 = pose[0] + Vector2(sin(hd), cos(hd)) * ((ahead - behind) * 0.5)
				ObstacleRegistry.add_corridor(group, ObstacleShapes.box(c, (ahead + behind) * 0.5, across, hd, 0.0, 0.0, ""))
	var nodes: Dictionary = taxi.get("nodes", {})
	for e in taxi.get("edges", []):
		var a := Vector2(nodes[e[0]][0], nodes[e[0]][1])
		var b := Vector2(nodes[e[1]][0], nodes[e[1]][1])
		_strip(group, a, b, 30.0 if e[4] == "runway" else taxi_half, 4.0)
	for r in runways:
		_strip(group, Vector2(r.ends[0].x, r.ends[0].y), Vector2(r.ends[1].x, r.ends[1].y), float(r.width) * 0.5 + RUNWAY_MARGIN, 0.0)


static func _strip(group: String, a: Vector2, b: Vector2, half: float, extra: float) -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	ObstacleRegistry.add_corridor(group, ObstacleShapes.box((a + b) * 0.5, d.length() * 0.5 + extra, half, atan2(d.x, d.y), 0.0, 0.0, ""))


static func unregister(icao: String) -> void:
	ObstacleRegistry.remove_corridors("corridor:" + icao)
