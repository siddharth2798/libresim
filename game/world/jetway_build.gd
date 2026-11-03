class_name JetwayBuild
extends RefCounted
## Builds an airport's jet bridges (AirportOps, and the jetway audit tests/jetway_audit.gd): one JetwayRig per movable
## bridge of airport_ops.json "jetbridges" (rotunda, cab end and stub direction from tools/jetway_net.py, JetwayDocks.ends)
## and the fixed links between the rotundas and the terminal ("jetlinks", JetwayLinks).


## root: AirportOps' per-airport root (frame x east, y height, z -north); a: the airport's ops data; h: Callable(e, n)
## -> ground height; solids: the airport's OpsSolids (null: none, e.g. in tests); def: the aircraft (null = current).
static func build(root: Node3D, a: Dictionary, h: Callable, solids: OpsSolids, scene: PackedScene, def: AircraftDef = null) -> Array:
	var ways := []
	for jb in a.get("jetbridges", []):
		var e := JetwayDocks.ends(jb, a.stands)
		if not e.is_empty():
			ways.append(e)
	var sill := float(GroundParams.ground(def).get("door_height_m", 0.0))
	var dy := func(t: Vector2, tip: Vector2) -> float:
		return float(h.call(tip.x, tip.y)) + sill - (float(h.call(t.x, t.y)) + JetwayPose.FLOOR_Y)
	var rigs := []
	var rots := []
	for k in ways.size():
		var w: Dictionary = ways[k]
		var t: Vector2 = w.terminal
		var rig := JetwayRig.new()
		rig.ground_at = h
		rig.setup(scene.instantiate(), t, w.cab, JetwayDocks.candidates(k, ways, a.stands, dy, def), w.back, w.own_rot)
		var g := float(h.call(t.x, t.y))
		rig.position = Vector3(t.x, g, -t.y)
		root.add_child(rig)
		rig.start(solids, str(k), g)
		rigs.append(rig)
		rots.append(t)
	var links := JetwayLinks.build(a.get("jetlinks", []), h, rots)
	if links:
		root.add_child(links)
	return rigs
