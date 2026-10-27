class_name RoutePlan
extends RefCounted
## A GPS route: the active waypoint (the direct-to target) followed by later waypoints.
## Pure logic, no nodes: sequencing when a waypoint is reached, the legs, bearing / distance / ETE.
## Props: "controls/gps/target" = active ident, "controls/gps/route_next" = idents after it.
## Waypoints are {ident: String, pos: Vector2 (ENU metres)}.

const NM := 1852.0
const ARRIVE_M := 1.0 * NM  # the next leg is flown once the aircraft is this close to the waypoint
const CRUISE_MPS := 90.0 * 1852.0 / 3600.0  # ETE speed when the aircraft is (nearly) stopped

var wps: Array[Dictionary] = []  # wps[0] is the active waypoint
var from_pos := Vector2.ZERO  # where the active leg started


## Build from idents; `lookup` is a Callable(ident) -> Vector2 or null. Unknown idents are dropped.
static func from_idents(active: String, next: Array, lookup: Callable) -> RoutePlan:
	var rp := RoutePlan.new()
	var ids: Array = ([active] if active != "" else []) + next
	for id in ids:
		var p = lookup.call(str(id))
		if p != null:
			rp.wps.append({"ident": str(id), "pos": p})
	return rp


func is_empty() -> bool:
	return wps.is_empty()


func active() -> Dictionary:
	return wps[0] if not wps.is_empty() else {}


func next_idents() -> Array:
	var out := []
	for i in range(1, wps.size()):
		out.append(wps[i].ident)
	return out


## Move to the next leg when the aircraft is within ARRIVE_M of the active waypoint and one
## follows. Returns true if it advanced (the caller then publishes the new target).
func update(pos: Vector2) -> bool:
	if wps.size() < 2 or pos.distance_to(wps[0].pos) > ARRIVE_M:
		return false
	from_pos = wps[0].pos
	wps.pop_front()
	return true


## Legs from the aircraft: [{a, b, ident (of b), active, dist_m (leg length), cum_m (from the
## aircraft to b along the route)}]. The first leg starts at `pos`.
func legs(pos: Vector2) -> Array:
	var out := []
	var a := pos
	var cum := 0.0
	for i in wps.size():
		var b: Vector2 = wps[i].pos
		var d := a.distance_to(b)
		cum += d
		out.append({"a": a, "b": b, "ident": wps[i].ident, "active": i == 0, "dist_m": d, "cum_m": cum})
		a = b
	return out


func remaining_m(pos: Vector2) -> float:
	var l := legs(pos)
	return l.back().cum_m if not l.is_empty() else 0.0


## All points a view should keep on screen: the aircraft and every waypoint.
func points() -> Array:
	var out := []
	for w in wps:
		out.append(w.pos)
	return out


## True bearing in degrees 0..360 from a to b (north = 0, east = 90).
static func bearing_deg(a: Vector2, b: Vector2) -> float:
	var d := b - a
	return fposmod(rad_to_deg(atan2(d.x, d.y)), 360.0)


static func ete_s(dist_m: float, gs_mps: float) -> float:
	return dist_m / (gs_mps if gs_mps > 5.0 else CRUISE_MPS)


static func format_ete(secs: float) -> String:
	var s := int(round(secs))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
