extends Node
## Load-time fixes: corridors of only the airports near the aircraft (CorridorBook, the rest as they come near),
## the flight scene and aircraft models loaded in the background (ScenePreload). The loader film's JPG frames are
## tested in test_loader_film.gd. Needs data/processed for the corridor tests (skipped without it).

const C172_EXT := "res://aircraft/c172/models/exterior.glb"

var _ops = null
var _rws := {}


func teardown() -> void:
	CorridorBook.reset()
	FloatingOrigin.set_origin(Vector2.ZERO)


func _data() -> bool:
	if _ops == null:
		_ops = Paths.load_json("airport_ops.json")
		var rj = Paths.load_json("runways.json")
		if rj != null:
			for r in rj.runways:
				if not _rws.has(r.airport):
					_rws[r.airport] = []
				_rws[r.airport].append(r)
	return _ops is Dictionary and _ops.has("VABB") and _ops.has("VAPO") and _ops.has("VANM")


func _stand(icao: String) -> Vector2:
	var s: Dictionary = _ops[icao].stands[0]
	return GroundParams.cg_at_stand(s)


func _wait(icao: String) -> bool:
	var t := Time.get_ticks_msec()
	while not CorridorBook.registered().has(icao) and Time.get_ticks_msec() - t < 20000:
		OS.delay_msec(5)
		CorridorBook.poll()
	return CorridorBook.registered().has(icao)


## Parked at Mumbai: Mumbai's corridors are in before the first physics step; Navi Mumbai (about 25 km) and Kochi are
## not planned at all (the old load planned all 961 stands of 44 airports, about 3 s).
func test_only_airports_near_the_start_are_registered() -> String:
	if not _data():
		print("    (skipped: no data/processed)")
		return ""
	CorridorBook.setup(_ops, _rws)
	CorridorBook.request("VABB")  # AirportOps.setup asks for the start airport on a worker
	var ops := AirportOps.new()
	var p := _stand("VABB")
	ops.corridors_near_aircraft([], Vector3(p.x, p.y, 10.0))  # flight.gd, once the aircraft is placed
	ops.free()
	var reg := CorridorBook.registered()
	if not reg.has("VABB") or not ObstacleRegistry.in_corridor(p.x, p.y):
		return "the start airport's corridors should be in at once (registered %s)" % [reg]
	for far in ["VANM", "VOCI", "VAPO"]:
		if reg.has(far) or CorridorBook.pending().has(far):
			return "%s is far from Mumbai and should not be planned at the start" % far
	for icao in reg:
		if CorridorBook.dist(CorridorBook._sites[icao].rect, p) > CorridorBook.SYNC_M:
			return "%s was registered at once although it is %.0f m away" % [icao, CorridorBook.dist(CorridorBook._sites[icao].rect, p)]
	return ""


## Flying toward Pune: within 15 km it is planned on a worker and its corridors arrive; a camera point counts too, even
## after the floating origin moved (positions are world ENU).
func test_a_far_airport_registers_when_approached() -> String:
	if not _data():
		print("    (skipped: no data/processed)")
		return ""
	CorridorBook.setup(_ops, _rws)
	var rect: Rect2 = CorridorBook._sites["VAPO"].rect
	var out := Vector2(rect.position.x - 10000.0, rect.get_center().y)  # 10 km west of Pune's extent
	CorridorBook.update(Vector2(rect.position.x - 40000.0, rect.get_center().y))
	if not CorridorBook.pending().is_empty() and CorridorBook.pending().has("VAPO"):
		return "Pune should not be planned from 40 km"
	FloatingOrigin.set_origin(out)  # the world shifted on the way
	var cam_render := FloatingOrigin.to_render(Vector3(out.x, out.y, 1000.0))
	var w := FloatingOrigin.to_world(cam_render)
	CorridorBook.update(null, [Vector2(w.x, w.y)])
	if not CorridorBook.pending().has("VAPO"):
		return "Pune should be planned on a worker from 10 km (pending %s)" % [CorridorBook.pending()]
	if CorridorBook.is_ready("VAPO"):
		return "not ready until its plan is in"
	if not _wait("VAPO"):
		return "Pune's plan never arrived"
	var p := _stand("VAPO")
	if not ObstacleRegistry.in_corridor(p.x, p.y):
		return "Pune's stand is not in a corridor after its plan arrived"
	CorridorBook.reset()
	if ObstacleRegistry.in_corridor(p.x, p.y):
		return "reset() should take the flight's corridors out"
	return ""


## AirportOps' once-a-second check: a camera 10 km from Pune (render frame, any floating origin) starts its plan.
func test_airport_ops_plans_the_airport_near_the_camera() -> String:
	if not _data():
		print("    (skipped: no data/processed)")
		return ""
	CorridorBook.setup(_ops, _rws)
	var rect: Rect2 = CorridorBook._sites["VAPO"].rect
	var at := Vector2(rect.end.x + 10000.0, rect.get_center().y)  # 10 km east of Pune
	FloatingOrigin.set_origin(at + Vector2(3000.0, 0.0))
	var keep: Variant = Props.get_v("fdm/position_enu", null)
	Props.set_v("fdm/position_enu", Vector3(at.x + 200000.0, at.y, 0.0))  # the aircraft far away: only the camera counts
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = FloatingOrigin.to_render(Vector3(at.x, at.y, 800.0))
	cam.make_current()
	var ops := AirportOps.new()
	ops.data = {}
	add_child(ops)
	ops._process(0.016)
	var planned := CorridorBook.pending().has("VAPO") or CorridorBook.registered().has("VAPO")
	ops.free()
	cam.free()
	Props.set_v("fdm/position_enu", keep)
	return "" if planned else "a camera 10 km from Pune should start Pune's plan (pending %s)" % [CorridorBook.pending()]


## The worker's boxes are the boxes the single-pass registration made (taxi segments now worked out once per airport).
func test_lazy_plan_matches_the_direct_registration() -> String:
	if not _data():
		print("    (skipped: no data/processed)")
		return ""
	OpsCorridors.register("VAPO", _ops.VAPO, _rws.get("VAPO", []))
	var direct := []
	for rec in ObstacleRegistry._corr_groups.get("corridor:VAPO", []):
		direct.append(rec.poly)
	OpsCorridors.unregister("VAPO")
	CorridorBook.setup(_ops, _rws)
	CorridorBook.request("VAPO")
	if not _wait("VAPO"):
		return "no plan"
	var lazy := []
	for rec in ObstacleRegistry._corr_groups.get("corridor:VAPO", []):
		lazy.append(rec.poly)
	if direct.is_empty() or direct != lazy:
		return "boxes differ: %d direct, %d lazy" % [direct.size(), lazy.size()]
	return ""


## Pushback and taxi at the start airport: every stand's swing is a corridor (both tail directions) and a taxi route
## leads from the stand to a runway end.
func test_pushback_and_taxi_work_at_the_start_airport() -> String:
	if not _data():
		print("    (skipped: no data/processed)")
		return ""
	CorridorBook.setup(_ops, _rws)
	CorridorBook.ensure("VAPO")
	var a: Dictionary = _ops.VAPO
	var pb := GroundParams.pushback()
	for s in a.stands:
		var p0 := GroundParams.cg_at_stand(s)
		var h0 := deg_to_rad(float(s.heading_deg))
		for side in [1.0, -1.0]:
			var fit: Dictionary = preload("res://world/pushback_fit.gd").plan(p0, h0, a.taxi, side, pb, null, true, false)
			var end: Vector2 = PushbackPath.pose(p0, h0, fit.side, fit.limit, fit.straight, fit.radius, fit.turn)[0]
			if not ObstacleRegistry.in_corridor(end.x, end.y):
				return "stand %s: the end of the pushback swing is outside the corridors" % s.ref
	var ops := AirportOps.new()
	ops.data = _ops
	var rw: Dictionary = _rws.VAPO[0]
	var r: Dictionary = ops.route("VAPO", Vector2(rw.ends[0].x, rw.ends[0].y), Vector2(a.stands[0].x, a.stands[0].y))
	ops.free()
	if r.is_empty() or r.path.size() < 2:
		return "no taxi route from the runway to stand %s" % a.stands[0].ref
	return ""


## An airport the book does not know never holds anything up (RunwayLights in a scene without AirportOps).
func test_unknown_airport_is_ready() -> String:
	CorridorBook.reset()
	return "" if CorridorBook.is_ready("ZZZZ") else "an unknown airport should count as ready"


## The flight scene and the aircraft's models load on threads; take() hands over the loaded resource once, after that
## (and for anything never preloaded) the caller loads it the normal way. Another aircraft drops the first one's models.
func test_flight_scene_and_models_preload() -> String:
	# The flight scene's scripts and both aircraft's models are loaded first, on this thread; the flight scene itself
	# still loads on a loader thread, and the bookkeeping (requested, take once, drop, clear) is what this test is about.
	# Godot 4.7.2 leaks one ResourceLoader load token (a RefCounted with reference count 0, "N ObjectDB instances were
	# leaked at exit") for each preload() compiled inside a threaded load and for a texture two threaded loads fetch at
	# once, and the headless dummy renderer's mesh store is not safe for two glbs loading at once ("Attempting to
	# initialize the wrong RID", a mesh RID leaked at exit). docs/USAGE.md "Automated tests".
	var warm := []
	for dep in ResourceLoader.get_dependencies(ScenePreload.FLIGHT):
		warm.append(load(dep.get_slice("::", dep.get_slice_count("::") - 1)))
	for id in ["c172", "a320"]:
		var d := AircraftDef.load_def(id)
		for f in ScenePreload.MODEL_FILES:
			if d.has_file(f):
				warm.append(load(d.path(f)))
	var was := ScenePreload.enabled
	ScenePreload.enabled = true
	ScenePreload.begin("c172")
	var msg := ""
	if not ScenePreload.requested(ScenePreload.FLIGHT) or not ScenePreload.requested(C172_EXT):
		msg = "Fly's flight scene and the C172 exterior should be loading"
	var t := Time.get_ticks_msec()
	while msg == "" and ScenePreload.busy() and Time.get_ticks_msec() - t < 60000:
		OS.delay_msec(10)
	var ps := ScenePreload.take(ScenePreload.FLIGHT) as PackedScene
	if msg == "" and (ps == null or not ps.can_instantiate()):
		msg = "the preloaded flight scene was not handed over"
	if msg == "" and ScenePreload.take(ScenePreload.FLIGHT) != null:
		msg = "a preload is handed over once; then the normal load"
	if msg == "" and ScenePreload.scene(ScenePreload.FLIGHT) == null:
		msg = "the fallback load should still give the scene"
	ScenePreload.begin("a320")
	if msg == "" and (ScenePreload.requested(C172_EXT) or not ScenePreload.requested(AircraftDef.load_def("a320").path("exterior"))):
		msg = "picking the A320 should drop the C172 models and load the A320's"
	t = Time.get_ticks_msec()
	while ScenePreload.busy() and Time.get_ticks_msec() - t < 60000:  # let the A320's loads finish so clear() releases them now
		OS.delay_msec(10)
	ScenePreload.clear()
	ScenePreload.enabled = was
	if msg == "" and ScenePreload.requested(ScenePreload.FLIGHT):
		msg = "clear() should drop every preload"
	return msg
