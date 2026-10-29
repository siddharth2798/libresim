class_name JetwayDocks
extends RefCounted
## Which jetway serves which gate stand, and the pose it takes at that gate for the current aircraft.
## A gate's stand point is the L1 door's place on the aircraft centre line (GroundParams.cg_at_stand puts the CG
## behind it), so the jetway whose cab end lies nearest the door tip (GroundParams.door_tip) serves it, provided it
## can reach it: within REACH_M of its rest position and with a pose JetwayPose.docked accepts (tunnel length, cab
## twist). Two gates may share a jetway; it docks to whichever has the aircraft.

const REACH_M := 26.0  # a jetway docks to a door at most this far from where the OSM way puts its cab end
const NEAR_M := 3.0  # the CG within this of the gate's CG point (and slow) = the aircraft is at the gate
const LEAVE_M := 4.5  # ... and it stays docked until it is this far off
const SLOW_MPS := 1.0


## One jetway of an airport: {terminal, cab} (ENU Vector2, rest layout, cab = the end nearer a stand).
static func ends(pts: Array, stands: Array) -> Dictionary:
	var a := Vector2(pts[0][0], pts[0][1])
	var b := Vector2(pts[-1][0], pts[-1][1])
	var near_a := INF
	var near_b := INF
	for st in stands:
		near_a = minf(near_a, a.distance_to(Vector2(st.x, st.y)))
		near_b = minf(near_b, b.distance_to(Vector2(st.x, st.y)))
	return {"terminal": a if near_a > near_b else b, "cab": b if near_a > near_b else a}


## Dock candidates of jetway `k` among `ways` (their ends()): [{stand, cg, pose}] for every jetbridge stand whose
## nearest jetway it is. dy_of = Callable(terminal, tip) -> how much higher the door sill is than the cab floor.
static func candidates(k: int, ways: Array, stands: Array, dy_of: Callable, def: AircraftDef = null) -> Array:
	var out := []
	if not GroundParams.dockable(def):
		return out
	for st in stands:
		if not st.get("jetbridge", false):
			continue
		var tip := GroundParams.door_tip(st, def)
		var best := -1
		var bd := REACH_M
		for i in ways.size():
			var d: float = (ways[i].cab as Vector2).distance_to(tip)
			if d < bd:
				bd = d
				best = i
		if best != k:
			continue
		var hd := deg_to_rad(float(st.heading_deg))
		var pose := JetwayPose.docked(ways[k].terminal, tip, Vector2(cos(hd), -sin(hd)), dy_of.call(ways[k].terminal, tip))
		if not pose.is_empty():
			out.append({"stand": st.ref, "cg": GroundParams.cg_at_stand(st, def), "pose": pose})
	return out


## The candidate the aircraft (CG at `cg`, ground speed gs) is at; `docked` widens the margin once it is docked.
static func occupied(cands: Array, cg: Vector2, gs: float, docked: bool) -> int:
	for i in cands.size():
		var d: float = cg.distance_to(cands[i].cg)
		if d < (LEAVE_M if docked else NEAR_M) and gs < (2.0 if docked else SLOW_MPS):
			return i
	return -1
