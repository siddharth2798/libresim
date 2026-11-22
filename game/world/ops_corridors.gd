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


## ops: one airport of airport_ops.json ({stands, taxi: {nodes, edges}}); runways: its runways.json entries;
## aircraft: null = the current one (tests pass their own). All at once on this thread; CorridorBook registers the
## airports of a flight lazily (the boxes are worked out by CorridorPlan, on a worker for a far airport).
static func register(icao: String, ops: Dictionary, runways: Array, aircraft: AircraftDef = null) -> void:
	ObstacleRegistry.remove_corridors("corridor:" + icao)
	CorridorPlan.insert(icao, CorridorPlan.compute(CorridorPlan.job(icao, ops, runways, aircraft)))


static func unregister(icao: String) -> void:
	ObstacleRegistry.remove_corridors("corridor:" + icao)
