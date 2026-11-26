class_name AirportBuilder
extends Node3D
## Builds runway and taxiway surfaces from data/processed/runways.json (tools/09_runways.py), only near the camera.
## One group per airport (AirportGroups): built while the camera is within its range (the draw distance of something as
## large as its longest runway, scaled by the preset like world/vis_ranges.gd), freed beyond that x 1.3 (no flicker).
## Airports within SYNC_M are built at once on this thread (the start airport, a save at another airport, an air start:
## before the first frame); the others are cut on a worker (AirportStream), nearest first, a few nodes a frame.
## Each surface is a strip mesh draped on the terrain triangles (GroundDrape: at the FDM's ground height, no lift; the
## shaders win the depth test), anchored at a lattice point, re-positioned when the floating origin shifts. Per airport:
## a mesh and material per runway, ONE merged taxiway mesh and ONE lead-on mesh (AirportCut; shared materials, UV2).
## Runways draw world/runway_v2.gdshader (ICAO layout from RunwayMarkings, static look baked lazily near the camera by
## RunwayBakes); taxiways and lead-on lines draw strip.gdshaderinc. runway_material(key) finds a runway's material for
## TouchdownMarks (key: TouchdownMarks.runway_key); runway_built(key) says when a runway got its mesh (again, after
## being freed), so its tyre marks go back on.

signal runway_built(key: String)

const SYNC_M := RunwayBakes.NEAR_M  # groups this close are built at once
const CHECK_S := 0.5  # how often the near / far check runs
const JUMP_M := 2000.0  # the camera moved this far since the last check (a load, a teleport): check now
const NODES_PER_FRAME := 3  # nodes created a frame for a group that came from the worker

var terrain: TerrainQuadtree
var data: Dictionary
var _groups: Array = []  # AirportGroups.make; read by the worker, never written after build()
var _state: Array[int] = []  # per group: 0 absent, 1 being cut on the worker, 2 nodes waiting in _spawn, 3 built
var _nodes: Array = []  # per group: its MeshInstance3D nodes
var _keys: Array = []  # per group: the runway keys it put into _runway_mats
var _left: Array[int] = []  # per group: nodes of _spawn not created yet
var _items: Array = []  # [MeshInstance3D, anchor ENU Vector3] of every built node (a floating-origin shift moves them)
var _spawn: Array = []  # [group, kind (0 runway, 1 taxiways, 2 lead-ons), cut] waiting for NODES_PER_FRAME
var _want: Array = []  # groups for the worker, nearest first (renewed every check)
var _last_ex: Array = []  # metres from the camera to each group's circle at the last check
var _stream: AirportStream
var _shader := preload("res://world/runway_v2.gdshader")
var _taxi_shader := preload("res://world/taxiway.gdshader")  # fades out when a few px wide
var _lead_shader := preload("res://world/lead_on.gdshader")  # yellow line only, drawn over a runway
var _taxi_mat: ShaderMaterial  # shared by every airport
var _lead_mat: ShaderMaterial
var _ils: Array = []  # ils.json: which runway ends have an ILS (precision paint and lights)
var _runway_mats := {}  # TouchdownMarks.runway_key -> ShaderMaterial
var _bakes := RunwayBakes.new(self)
var _t := 0.0
var _last_cam := Vector3(INF, INF, INF)


## wait: build every airport now, on this thread (tests); else only what update() / focus() asks for.
## preset: runways.json contents to use instead of the file (tests).
func build(t: TerrainQuadtree, wait := false, preset := {}) -> void:
	terrain = t
	data = preset if not preset.is_empty() else Paths.load_json("runways.json")
	if data == null:
		return
	var il = Paths.load_json("ils.json")
	_ils = il if il is Array else []
	_groups = AirportGroups.make(data)
	_stream = AirportStream.new(_groups)
	_state.resize(_groups.size())
	_state.fill(0)
	_left.resize(_groups.size())
	_left.fill(0)
	for g in _groups:
		_nodes.append([])
		_keys.append([])
	_taxi_mat = _surface_material(_taxi_shader, 15.0)
	_lead_mat = _surface_material(_lead_shader, AirportCut.LEAD_W)
	_shader_defaults()
	FloatingOrigin.shifted.connect(func(_d): _reposition())
	if wait:
		for i in _groups.size():
			_build_now(i)


func _surface_material(sh: Shader, w: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()  # default render priority: the apron light pools draw over it (ApronFloodlights.POOL_PRIORITY)
	mat.shader = sh
	mat.set_shader_parameter("is_runway", false)
	mat.set_shader_parameter("width_m", w)
	return mat


## Call after placing the aircraft (ENU x, y, up; flight start, a loaded save, an air start): its airports have
## runways before the next frame is drawn.
func focus(enu: Vector3) -> void:
	_last_cam = enu
	_t = 0.0
	update(enu)


## One check from camera position cam (ENU x, y, up): frees what is beyond range x hysteresis, builds what is within
## SYNC_M at once (everything wanted when sync_all), queues the others for the worker, nearest first.
func update(cam: Vector3, sync_all := false) -> void:
	var ex := []
	var rg := []
	var built := []
	for i in _groups.size():
		ex.append(AirportGroups.excess(_groups[i], cam))
		rg.append(AirportGroups.range_m(_groups[i]))
		built.append(_state[i] != 0)
	_last_ex = ex
	var p := AirportGroups.plan(ex, rg, built)
	for i in p.free:
		_free(i)
	_want = []
	for i in p.build:
		if sync_all or ex[i] < SYNC_M:
			_build_now(i)
		else:
			_want.append(i)


## True while an airport within SYNC_M of the camera has no meshes (never, once update() has run).
func busy() -> bool:
	return not _groups.is_empty() and (_last_ex.is_empty() or progress() < 1.0)


## 0..1 of the airports within SYNC_M of the camera that are built.
func progress() -> float:
	var n := 0
	var done := 0
	for i in _last_ex.size():
		if _last_ex[i] < SYNC_M:
			n += 1
			done += 1 if _state[i] == 3 else 0
	return 1.0 if n == 0 else float(done) / float(n)


## Keys of the airports (ICAO, or "cell:x:y" for taxiways far from any runway) that have their meshes now.
func built_keys() -> Array:
	var out := []
	for i in _groups.size():
		if _state[i] == 3:
			out.append(_groups[i].key)
	return out


## The group (AirportGroups) of an airport key, {} if there is none.
func group(key: String) -> Dictionary:
	for g in _groups:
		if g.key == key:
			return g
	return {}


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var at := Vector3(FloatingOrigin.origin.x, FloatingOrigin.origin.y, 0.0)
	if cam:
		at = FloatingOrigin.to_world(cam.global_position)
		_bakes.step(Vector2(at.x, at.y), dt)
	if _groups.is_empty():
		return
	_t += dt
	if _t >= CHECK_S or Vector2(at.x, at.y).distance_to(Vector2(_last_cam.x, _last_cam.y)) > JUMP_M:
		_t = 0.0
		_last_cam = at
		update(at)
	var r := _stream.poll()
	if not r.is_empty() and _state[r[0]] == 1:  # (a group freed or built at once meanwhile is dropped)
		_queue_specs(r[0], r[1])
	_spawn_some(NODES_PER_FRAME)
	if _stream.inflight < 0:
		for i in _want:
			if _state[i] == 0:
				_state[i] = 1
				_stream.start(i)
				break


func _exit_tree() -> void:
	_bakes.stop()
	if _stream:
		_stream.stop()


## The nodes of one cut group: [[kind, spec]], a runway each, then the taxiways, then the lead-on lines.
func _specs(cut: Dictionary) -> Array:
	var out: Array = cut.runways.map(func(rw): return [0, rw])
	if not cut.taxi.is_empty():
		out.append([1, cut.taxi])
	if not cut.lead.is_empty():
		out.append([2, cut.lead])
	return out


func _queue_specs(i: int, cut: Dictionary) -> void:
	var specs := _specs(cut)
	for s in specs:
		_spawn.append([i, s[0], s[1]])
	_left[i] = specs.size()
	_state[i] = 2 if specs.size() > 0 else 3


func _spawn_some(budget: int) -> void:
	while budget > 0 and not _spawn.is_empty():
		var e: Array = _spawn.pop_front()
		_spawn_node(e[0], e[1], e[2])
		_left[e[0]] -= 1
		if _left[e[0]] == 0:
			_state[e[0]] = 3
		budget -= 1


## Builds group i now, on this thread, with the terrain's own cache.
func _build_now(i: int) -> void:
	_free(i)
	for s in _specs(AirportCut.cut(_groups[i], terrain.cache)):
		_spawn_node(i, s[0], s[1])
	_state[i] = 3


## Frees group i: its nodes, runway materials and bakes.
func _free(i: int) -> void:
	if _state[i] == 0:
		return
	_spawn = _spawn.filter(func(e): return e[0] != i)
	for mi in _nodes[i]:
		_items = _items.filter(func(it): return it[0] != mi)
		mi.queue_free()
	for key in _keys[i]:
		if _runway_mats.has(key):
			_bakes.remove(_runway_mats[key])
			_runway_mats.erase(key)
	_nodes[i] = []
	_keys[i] = []
	_left[i] = 0
	_state[i] = 0


## One node of group i: kind 0 a runway (cut: {rec, arrays, anchor, along}), 1 the taxiways, 2 the lead-on lines.
func _spawn_node(i: int, kind: int, cut: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = GroundDrape.to_mesh(cut.arrays)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := ""
	if kind == 0:
		var rec: Dictionary = cut.rec
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("is_runway", true)
		mat.set_shader_parameter("length_m", float(rec.length))
		mat.set_shader_parameter("width_m", float(rec.width))
		var u := RunwayMarkings.uniforms(rec, RunwayMarkings.lights_from_ils(rec, _ils))
		for k in u:
			mat.set_shader_parameter(k, u[k])
		key = TouchdownMarks.runway_key(rec)
		_runway_mats[key] = mat
		_keys[i].append(key)
		_bakes.add(mat, rec, u)
		mi.material_override = mat
	else:
		mi.material_override = _taxi_mat if kind == 1 else _lead_mat
	add_child(mi)
	mi.position = FloatingOrigin.to_render(cut.anchor)
	_nodes[i].append(mi)
	_items.append([mi, cut.anchor])
	if key != "":
		runway_built.emit(key)


## The material of runway `key` (TouchdownMarks.runway_key), null if it has no mesh yet.
func runway_material(key: String) -> ShaderMaterial:
	return _runway_mats.get(key)


## Runways holding a bake now (tests, the preview).
func baked_runways() -> int:
	return _bakes.baked_count()


## Textures every runway / taxiway material shares, bound once as shader defaults.
func _shader_defaults() -> void:
	TerrainDetail.apply(_shader)
	if _shader.get_default_texture_parameter("glyphs") == null:
		_shader.set_default_texture_parameter("glyphs", RunwayGlyphs.texture())
		_shader.set_default_texture_parameter("rw_noise_tex", RunwayNoise.texture())
		_taxi_shader.set_default_texture_parameter("rw_noise_tex", RunwayNoise.texture())


func _reposition() -> void:
	for it in _items:
		(it[0] as MeshInstance3D).position = FloatingOrigin.to_render(it[1])


## Start position on a runway: returns {pos: Vector2 ENU, heading_deg} or {}.
func runway_start(airport: String, ident: String) -> Dictionary:
	if data == null:
		return {}
	var rwys: Array = data.runways.filter(func(r): return r.airport == airport)
	rwys.sort_custom(func(a, b): return a.length > b.length)  # default: longest runway
	for r in rwys:
		for i in 2:
			var e: Dictionary = r.ends[i]
			if ident == "" or e.ident == ident:
				var hd := deg_to_rad(float(e.heading_true))
				var fwd := Vector2(sin(hd), cos(hd))
				var p := Vector2(e.x, e.y) + fwd * 25.0
				return {"pos": p, "heading_deg": float(e.heading_true), "ident": e.ident}
	return {}
