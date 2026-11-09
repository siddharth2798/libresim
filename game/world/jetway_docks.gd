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


## One movable jetway of an airport's "jetbridges" entry: {terminal (its rotunda), cab, back, own_rot} (ENU Vector2s).
## tools/jetway_net.py gives the rotunda, cab end and the stub's direction toward the building; {} for a way that is
## only a fixed link or has no building near it. Older data (pts only): the end nearer a stand is the cab.
static func ends(jb: Dictionary, stands: Array) -> Dictionary:
	if jb.has("tip"):
		return {"terminal": Vector2(jb.rot[0], jb.rot[1]), "cab": Vector2(jb.tip[0], jb.tip[1]),
			"back": Vector2(jb.back[0], jb.back[1]), "own_rot": bool(jb.get("own_rot", true))}
	if jb.get("fixed", false) or jb.get("orphan", false):
		return {}
	var pts: Array = jb.pts
	var a := Vector2(pts[0][0], pts[0][1])
	var b := Vector2(pts[-1][0], pts[-1][1])
	var near_a := INF
	var near_b := INF
	for st in stands:
		near_a = minf(near_a, a.distance_to(Vector2(st.x, st.y)))
		near_b = minf(near_b, b.distance_to(Vector2(st.x, st.y)))
	return {"terminal": a if near_a > near_b else b, "cab": b if near_a > near_b else a, "back": Vector2.ZERO, "own_rot": true}


## Dock candidates of jetway `k` among `ways` (their ends()): [{stand, cg, pose}] for every jetbridge stand it serves:
## of the jetways whose cab end is within REACH_M of the door, the nearest one that can reach it (a pose
## JetwayPose.docked accepts: at a two-bridge rotunda the one drawn nearer the door may come from the wrong side).
## dy_of = Callable(rotunda, tip) -> how much higher the door sill is than the cab floor.
static func candidates(k: int, ways: Array, stands: Array, dy_of: Callable, def: AircraftDef = null) -> Array:
	var out := []
	if not GroundParams.dockable(def):
		return out
	for st in stands:
		if not st.get("jetbridge", false):
			continue
		var tip := GroundParams.door_tip(st, def)
		var hd := deg_to_rad(float(st.heading_deg))
		var cab_dir := Vector2(cos(hd), -sin(hd))
		var order := []
		for i in ways.size():
			var d: float = (ways[i].cab as Vector2).distance_to(tip)
			if d < REACH_M:
				order.append([d, i])
		order.sort()
		for o in order:
			var i: int = o[1]
			var pose := JetwayPose.docked(ways[i].terminal, tip, cab_dir, dy_of.call(ways[i].terminal, tip))
			if pose.is_empty():
				continue
			if i == k:
				out.append({"stand": st.ref, "st": st, "cg": GroundParams.cg_at_stand(st, def), "pose": pose})
			break
	return out


## The candidate the aircraft (CG at `cg`, ground speed gs) is at; `docked` widens the margin once it is docked.
static func occupied(cands: Array, cg: Vector2, gs: float, docked: bool) -> int:
	for i in cands.size():
		var d: float = cg.distance_to(cands[i].cg)
		if d < (LEAVE_M if docked else NEAR_M) and gs < (2.0 if docked else SLOW_MPS):
			return i
	return -1


## The jetbridge stands (dicts of `stands`) an aircraft `def` can dock to: some OSM gates have no bridge that can reach their door.
static func docking_stands(a: Dictionary, def: AircraftDef = null) -> Array:
	var ways := []
	for jb in a.get("jetbridges", []):
		var e := ends(jb, a.stands)
		if not e.is_empty():
			ways.append(e)
	var flat := func(_t: Vector2, _tip: Vector2) -> float: return 0.0
	var out := []
	for k in ways.size():
		for c in candidates(k, ways, a.stands, flat, def):
			var st: Dictionary = c.st
			if not out.has(st):
				out.append(st)
	return out
