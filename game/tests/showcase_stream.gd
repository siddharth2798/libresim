extends RefCounted
## Streaming settle for tests/debug_showcase.gd: waits until the terrain tiles / textures, trees and
## buildings of the flight scene have stopped loading, and describes what is on screen for the log.

const MAX_SETTLE_S := 120.0  # give up waiting for the streamers after this
const QUIET_S := 2.5  # streaming must stay idle this long


## True while any streamer of the flight scene `f` still has work: terrain tiles / textures, trees, buildings.
static func busy(f: Node) -> bool:
	var c: TerrainTileCache = f.get_node("Terrain").cache
	if not c._tasks.is_empty() or not c._done.is_empty():
		return true
	var tr: Trees = f.get_node("Trees")
	if tr.visible and (tr._in_flight > 0 or not tr._queue.is_empty() or not tr._done.is_empty() or tr._chunks.values().has(null)):
		return true
	var b: Buildings = f.get_node("Buildings")
	return b.visible and (not b._done.is_empty() or b._tiles.values().has(null))


## One log line: cloud / fog / exposure, the attitude and how much scenery is loaded.
static func state(f: Node) -> String:
	var tr: Trees = f.get_node("Trees")
	var n_bb := 0
	for mi in tr._chunks.values():
		n_bb += mi.multimesh.instance_count if mi != null else 0
	var lod: TreeLod = tr.get_node("Lod")
	var e: Vector3 = f.get_node("Fdm").fdm.euler()
	var cloud := "in_cloud %s (aircraft %.2f), fog %.4f, exposure x%.2f; " % [Props.get_v("environment/in_cloud", false), Props.get_f("environment/ac_cloud_density"),
		(f.get_node("WorldEnvironment") as WorldEnvironment).environment.fog_density, Props.get_f("environment/exposure_mult", 1.0)]
	return cloud + "attitude roll %.1f pitch %.1f deg, terrain nodes %d, tree chunks %d (%d billboards, %d LOD0 meshes within %.0f m), building tiles %d" % [rad_to_deg(e.x), rad_to_deg(e.y), f.get_node("Terrain").visible_nodes, tr._chunks.size(), n_bb, lod.instance_count(), lod.covered, f.get_node("Buildings")._tiles.size()]


## Waits (on host's tree) until the streamers of `f` have been idle for QUIET_S in a row; returns the seconds waited.
static func settle(host: Node, f: Node) -> float:
	var t := 0.0
	var quiet := 0.0
	while quiet < QUIET_S and t < MAX_SETTLE_S:
		var dt := host.get_process_delta_time()
		t += dt
		quiet = 0.0 if busy(f) else quiet + dt
		await host.get_tree().process_frame
	if t >= MAX_SETTLE_S:
		push_warning("streaming did not settle in %.0f s" % MAX_SETTLE_S)
	return t
