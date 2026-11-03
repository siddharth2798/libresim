class_name RunwayLights
extends Node3D
## Aerodrome lighting manager. Builds AirportLights lazily for airports within
## BUILD_RADIUS of the camera (frees them beyond FREE_RADIUS), keeps them on the
## floating origin, drives the day / night / visibility intensity of each light group,
## lets ApronLamps put real SpotLights on the apron floodlight banks nearest the camera, and
## runs the rotating beacons (AirportBeacon). Data: runways.json, ils.json,
## airport_ops.json, airports.json. Run with "-- --lights-debug" to print PAPI readings.

const BUILD_RADIUS := 25000.0
const FREE_RADIUS := 30000.0
## Real apron lamps by default; Graphics.apply_to_scene sets the preset's count (more on Forward+, which
## has no Mobile-style limit on lights per mesh).
const REAL_LIGHTS := 4

## group -> [additive?, gain, base_m, min_px, max_m, halo]
const GROUPS := {
	"rwy": [true, 2.4, 0.4, 1.8, 10.0, 0.2],
	"app": [true, 2.4, 0.4, 1.8, 10.0, 0.2],
	"flash": [true, 3.5, 0.6, 2.6, 18.0, 0.4],
	"taxi": [true, 1.6, 0.3, 1.4, 6.0, 0.15],
	"stop": [true, 2.4, 0.35, 1.7, 8.0, 0.25],
	"papi": [false, 1.5, 0.8, 2.6, 18.0, 0.25],
	"flood": [true, 2.0, 0.7, 1.8, 8.0, 0.3],
	"beacon": [true, 3.5, 1.0, 2.6, 30.0, 0.45],
}

var terrain: TerrainQuadtree
var mats := {}
var _airports := {}  # icao -> {center, runways, taxiways}
var _ils: Array = []
var _ops := {}
var _built := {}  # icao -> AirportLights
var _timer := 0.0
var _lamps: ApronLamps
var _beacon: AirportBeacon
var _mask_icao := ""
var _mask: Array = []
var _debug := false
var _dbg_t := 0.0


func build(data: Dictionary, t: TerrainQuadtree) -> void:
	terrain = t
	_debug = "--lights-debug" in OS.get_cmdline_user_args()
	var il = Paths.load_json("ils.json")
	_ils = il if il is Array else []
	var op = Paths.load_json("airport_ops.json")
	_ops = op if op is Dictionary else {}
	_make_materials()
	for rw in data.runways:
		var icao: String = rw.airport
		if not _airports.has(icao):
			_airports[icao] = {"runways": [], "taxiways": [], "center": Vector2.ZERO}
		_airports[icao].runways.append(rw)
	for icao in _airports:
		var c := Vector2.ZERO
		for rw in _airports[icao].runways:
			c += Vector2(rw.ends[0].x + rw.ends[1].x, rw.ends[0].y + rw.ends[1].y) * 0.5
		_airports[icao].center = c / _airports[icao].runways.size()
	_assign_taxiways(data.get("taxiways", []))
	if _lamps == null:
		set_real_lights(REAL_LIGHTS)
	_beacon = AirportBeacon.new()
	_beacon.name = "Beacons"
	add_child(_beacon)
	_beacon.setup(_beacon_sites(), _h, mats.beacon)
	FloatingOrigin.shifted.connect(func(_d): _reposition())


## Real apron SpotLights (graphics preset): n lamps, the `shadows` nearest the aircraft cast shadows.
func set_real_lights(n: int, shadows := 0) -> void:
	if _lamps == null:
		_lamps = ApronLamps.new()
		_lamps.name = "ApronLamps"
		add_child(_lamps)
	_lamps.set_budget(n, shadows)


func real_light_count() -> int:
	return _lamps.count() if _lamps else 0


func _h(e: float, n: float) -> float:
	return terrain.height_at(e, n) if terrain else 0.0


## Each taxiway belongs to the airport of the nearest runway (within 5 km).
func _assign_taxiways(taxiways: Array) -> void:
	for tw in taxiways:
		if tw.pts.size() < 2:
			continue
		var p := Vector2(tw.pts[0][0], tw.pts[0][1])
		var best := ""
		var bd := 5000.0
		for icao in _airports:
			for rw in _airports[icao].runways:
				var q := Geometry2D.get_closest_point_to_segment(p, Vector2(rw.ends[0].x, rw.ends[0].y),
					Vector2(rw.ends[1].x, rw.ends[1].y))
				if p.distance_to(q) < bd:
					bd = p.distance_to(q)
					best = icao
		if best != "":
			_airports[best].taxiways.append(tw)


## Beacon sites: the control tower, else 300 m off the runway midpoint (lit airports only).
func _beacon_sites() -> Array:
	var out := []
	for icao in _airports:
		var a: Dictionary = _airports[icao]
		if not a.runways.any(func(rw): return AirportLights.is_lit(icao, rw)):
			continue
		var towers: Array = _ops.get(icao, {}).get("towers", [])
		if not towers.is_empty():
			out.append([icao, Vector2(towers[0].x, towers[0].y)])
		else:
			var rw: Dictionary = a.runways[0]
			var u := Vector2(rw.ends[1].x - rw.ends[0].x, rw.ends[1].y - rw.ends[0].y).normalized()
			out.append([icao, a.center + Vector2(u.y, -u.x) * 300.0])
	return out


func _make_materials() -> void:
	var add := preload("res://world/light_point.gdshader")
	var mix := preload("res://world/light_point_mix.gdshader")
	for g in GROUPS:
		var p: Array = GROUPS[g]
		var m := ShaderMaterial.new()
		m.shader = add if p[0] else mix
		m.set_shader_parameter("gain", p[1])
		m.set_shader_parameter("base_m", p[2])
		m.set_shader_parameter("min_px", p[3])
		m.set_shader_parameter("max_m", p[4])
		m.set_shader_parameter("halo", p[5])
		m.render_priority = 1 if p[0] else 0
		mats[g] = m
	var pool := ShaderMaterial.new()
	pool.shader = preload("res://world/light_pool.gdshader")
	mats["pool"] = pool


func _reposition() -> void:
	for icao in _built:
		var root: Node3D = _built[icao].root
		var a: Vector2 = root.get_meta("anchor", Vector2.ZERO)
		root.position = FloatingOrigin.to_render_d(a.x, a.y, 0.0)


## Group intensities from the sun elevation and the visibility.
static func levels(sun_deg: float, vis_m: float) -> Dictionary:
	var night := clampf((5.0 - sun_deg) / 9.0, 0.0, 1.0)
	var on := maxf(night, clampf((6000.0 - vis_m) / 2000.0, 0.0, 1.0))
	return {"rwy": lerpf(0.1, 1.0, on), "app": lerpf(0.3, 1.0, on), "flash": lerpf(0.35, 1.0, on),
		"taxi": on, "stop": on, "papi": 1.0, "beacon": on,
		"flood": NightSky.night_level(sun_deg), "pool": NightSky.night_level(sun_deg)}  # apron floods: night only


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or terrain == null:
		return
	var lv := levels(Props.get_f("environment/sun_elev_deg", 30.0), Props.get_f("environment/visibility_m", Props.get_f("weather/visibility_m", 20000.0)))
	for g in lv:
		mats[g].set_shader_parameter("level", lv[g])
	var w := FloatingOrigin.to_world(cam.global_position)
	var c := Vector2(w.x, w.y)
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.5
		_update_built(c)
		_update_mask(c)
	if _lamps:
		_lamps.update(dt, _built, w, Props.get_v("fdm/position_enu", w), lv.pool, mats.pool)
	if _debug:
		_dbg_t -= dt
		if _dbg_t <= 0.0:
			_dbg_t = 1.0
			_print_papi(w)


func _exit_tree() -> void:
	ApronMask.publish([])
	for icao in _built:
		_built[icao].release()


## Builds at most one airport per call (spreads the cost when several come into range).
func _update_built(c: Vector2) -> void:
	var built_one := false
	var order := _airports.keys()
	order.sort_custom(func(a, b): return c.distance_squared_to(_airports[a].center) < c.distance_squared_to(_airports[b].center))
	for icao in order:  # nearest first
		var d := c.distance_to(_airports[icao].center)
		if d < BUILD_RADIUS and not _built.has(icao) and not built_one:
			built_one = true
			var t0 := Time.get_ticks_usec()
			var al := AirportLights.new()
			var a: Dictionary = _airports[icao]
			add_child(al.build(icao, a.runways, a.taxiways, _ils, _ops.get(icao, {}), _h, mats))
			_built[icao] = al
			_reposition()
			if _debug:
				print("lights %s built in %.0f ms: %s" % [icao, (Time.get_ticks_usec() - t0) / 1000.0, al.counts])
		elif d > FREE_RADIUS and _built.has(icao):
			_built[icao].release()
			_built[icao].root.queue_free()
			_built.erase(icao)


## Airside mask (no city-light speckle on the apron, ApronMask) of the nearest airport in range.
func _update_mask(c: Vector2) -> void:
	var best := ""
	var bd := BUILD_RADIUS
	for icao in _built:
		var d := c.distance_to(_airports[icao].center)
		if d < bd:
			bd = d
			best = icao
	if best != _mask_icao:
		_mask_icao = best
		_mask = ApronMask.paint(_ops.get(best, {}), _airports[best].runways) if best != "" else []
		ApronMask.publish(_mask)
	elif not _mask.is_empty():
		ApronMask.place(_mask[1])  # the pattern wrap base may have moved


## Debug: what the nearest PAPI shows to the camera, with the elevation angle.
func _print_papi(eye: Vector3) -> void:
	var best := []
	var bd := INF
	for icao in _built:
		for p in _built[icao].papis:
			var v := Vector2(eye.x, eye.y) - Vector2(p[1][0].pos.x, p[1][0].pos.y)
			var d := v.length()
			if d < bd and v.normalized().dot(p[1][0].dir) > 0.85:  # in front of the beam
				bd = d
				best = p
	if best.is_empty():
		return
	var u: Vector3 = best[1][1].pos
	var el := rad_to_deg(atan2(eye.z - u.z, Vector2(eye.x - u.x, eye.y - u.y).length()))
	print("PAPI %s: %s  (eye %.2f deg, %.0f m)" % [best[0], Papi.reading(best[1], eye), el, bd])
