class_name ObstacleCollision
extends RefCounted
## Does any part of the aircraft touch a solid (trees, buildings, terminals, jetways, vehicles)?
## Broad phase: ask the world for obstacles near the CG (FDM.obstacles, sphere of the hull
## radius). Only if there are any, narrow phase: every hull segment against every one. With
## 120 Hz x 2 steps and < 100 m/s the aircraft moves < 0.4 m per step, less than the thinnest
## solid (a mast is inflated to 0.5 m radius), so nothing is tunnelled through.

const REST_STEP := 0.0003  # m per step (0.07 m/s): the aircraft is parked, or was placed this step
const TELEPORT := 25.0  # m per step: a teleport (placement, situation load), not motion
const FORGIVE_R := 6.0  # a forgiven overlap holds while the CG stays this close to where it began

var hull: ObstacleHull
var _ignored := {}  # record id -> CG position (Vector2) when its overlap was forgiven
var _last := Vector2(INF, INF)


func _init(def: AircraftDef = null) -> void:
	hull = ObstacleHull.new(def)


## {} or {part, label, kind} for the first contact.
## Forgiven, because the data is not survey-grade: an overlap that exists while the aircraft is parked
## or has just been placed (a stand next to a tree: sitting still cannot crash into it; it holds only
## while the CG stays within FORGIVE_R and the overlap lasts), and "soft" solids (OSM buildings, trees)
## while the CG is inside a taxiway / runway corridor (FDM.in_corridor).
## raw: no forgiveness at all (tools and tests that want every overlap); moving: assume the aircraft is
## not parked (tests, scans that call it on teleported poses).
func check(f: FDM, raw := false, moving := false) -> Dictionary:
	var r := hull.radius(f.mb) + 0.3
	var alt := -f.pos_d
	var here := Vector2(f.pos_e, f.pos_n)
	var moved := here.distance_to(_last)
	_last = here
	var all: Array = f.obstacles.call(f.pos_e, f.pos_n, r, alt - r, alt + r)
	var cands := []
	for o in all:  # cheap altitude cut: most buildings are far below / above
		if o.top >= alt - r and o.base <= alt + r:
			cands.append(o)
	if cands.is_empty():
		_ignored.clear()
		return {}
	var pts := hull.world_points(f.mb, Basis(f.q), f.pos_e, f.pos_n, alt)
	var rest := not moving and not raw and (moved < REST_STEP or moved > TELEPORT)
	var corridor := -1  # not asked yet
	var touching := {}
	var hit := {}
	for o in cands:
		if o.soft and not raw:
			if corridor < 0:
				corridor = 1 if f.in_corridor.call(f.pos_e, f.pos_n) else 0
			if corridor == 1:
				continue
		for i in hull.count():
			if not ObstacleShapes.segment_hits(pts[i * 2], pts[i * 2 + 1], o):
				continue
			if not raw and _ignored.has(o.id) and here.distance_to(_ignored[o.id]) < FORGIVE_R:
				touching[o.id] = true
			elif rest:
				_ignored[o.id] = here
				touching[o.id] = true
			elif hit.is_empty():
				hit = {"part": hull.names[i], "label": o.label, "kind": o.k}
			break
	for id in _ignored.keys():
		if not touching.has(id):
			_ignored.erase(id)
	return hit


## "The right wingtip hit trees at 82 kt" / "The nose hit a building at 8 kt (taxiing)".
static func reason(hit: Dictionary, f: FDM) -> String:
	var kt := f.velocity_ned().length() / 0.514444
	var part: String = hit.part
	var s := "The %s hit %s at %.0f kt" % [part, hit.label, kt]
	return s + (" (taxiing)" if f.gear.wow and kt < 40.0 else "")
