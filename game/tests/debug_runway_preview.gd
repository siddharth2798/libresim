extends Node
## Debug (realistic runways, Stage 1): the real flight scene at one runway, with ONLY that runway's material swapped
## between the sim's own (runway_v2, baked lazily by RunwayBakes) and a fresh runway_v2 baked at once (three fake
## own-touchdown marks). Every shot is saved twice, <name>_old.png then <name>_new.png. Nothing else changes and no
## save is written. Needs a display; mute it:
##   godot --path game res://tests/debug_runway_preview.tscn --audio-driver Dummy -- --quality=high
## Low preset: add --rendering-method mobile and --quality=low (runway_detail 0). Environment:
##   RWPV_OUT=<dir>  RWPV_AIRPORT=VABB  RWPV_RUNWAY=27  RWPV_TOD=10  RWPV_RAIN=0.6  RWPV_TAG=_low  RWPV_DETAIL=0|1|2
##   RWPV_SHOTS=cockpit,chase,final,tdz,closeup,farend,overhead,lowsun,concrete   RWPV_GPU=1 (old vs new GPU ms)

const MARKS := [Vector4(285.0, 1.2, 0.012, 11.85), Vector4(318.0, -2.4, -0.02, 38.7), Vector4(352.0, 0.6, 0.006, 11.6)]
var f: Node3D
var cam: CameraRig
var _rwy := {}
var _mi: MeshInstance3D
var _old: Material
var _new: ShaderMaterial
var _out := ""
var _end := 0  # landing end: 0 = ends[0]


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)  # always silent (also run with --audio-driver Dummy)
	Session.interactive_override = 0  # never write the player's files
	Session.setup = Session.DEFAULT.duplicate(true)
	var s: Dictionary = Session.setup
	s.airport = _env("RWPV_AIRPORT", "VABB")
	s.runway = _env("RWPV_RUNWAY", "27")
	s.start = "runway"
	s.cold = true  # engine off, parking brake set: the aircraft stays put
	var rain := float(_env("RWPV_RAIN", "0"))
	Session.apply_weather_preset("Overcast" if rain > 0.0 else "Clear")
	s.precip = rain
	s.time_h = float(_env("RWPV_TOD", "10"))
	s.time_rate = 0.0
	s.wind_kt = 0.0
	s.live_weather = false
	Session.clean = true
	_out = _env("RWPV_OUT", OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1600, 900)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	cam = f.cam
	_run.call_deferred()


func _run() -> void:
	await _settle(40.0)
	if not _find_runway():
		push_error("RWPV: runway mesh not found")
		get_tree().quit(1)
		return
	_make_material()
	Graphics.render_frac = 1.0  # native resolution, no auto scaling while measuring (not saved)
	Graphics.apply_to_scene(f)
	_clean_lens()
	for shot in _env("RWPV_SHOTS", "cockpit,chase,final,tdz,closeup,farend,overhead,lowsun").split(","):
		await _shot(shot.strip_edges())
	if _env("RWPV_GPU", "") != "":
		await _gpu("chase")
		await _gpu("tdz")
	get_tree().quit()


## Waits until the runway meshes are cut and no terrain tile is pending for a second, then 1.5 s more.
func _settle(limit: float) -> void:
	var t0 := Time.get_ticks_msec()
	var calm := 0
	while calm < 60 and Time.get_ticks_msec() - t0 < limit * 1000.0:
		await get_tree().process_frame
		var busy: bool = f.airports.busy() or f.terrain.pending_tiles > 0 or f.terrain.visible_nodes <= 0
		calm = 0 if busy else calm + 1
	await _wait(1.5)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
	await RenderingServer.frame_post_draw


func _find_runway() -> bool:
	var icao: String = Session.setup.airport
	var ident: String = Session.setup.runway
	for r in f.airports.data.runways:
		if r.airport == icao and (r.ends[0].ident == ident or r.ends[1].ident == ident):
			_rwy = r
			_end = 0 if r.ends[0].ident == ident else 1
	if _rwy.is_empty():
		return false
	var a := Vector2(_rwy.ends[0].x, _rwy.ends[0].y)
	var best := 1e9
	for it in f.airports._items:
		var mi: MeshInstance3D = it[0]
		var m := mi.material_override as ShaderMaterial
		if m == null or not m.get_shader_parameter("is_runway"):
			continue
		var d := Vector2(it[1].x, it[1].y).distance_to(a)
		if d < best and absf(float(m.get_shader_parameter("length_m")) - float(_rwy.length)) < 1.0:
			best = d
			_mi = mi
	print("RWPV runway %s %s/%s %.0f x %.0f m, mesh %.1f m from ends[0]" % [icao, _rwy.ends[0].ident, _rwy.ends[1].ident, _rwy.length, _rwy.width, best])
	return _mi != null and best < 60.0


func _make_material() -> void:
	_old = _mi.material_override
	var sh: Shader = load("res://world/runway_v2.gdshader")
	TerrainDetail.apply(sh)
	sh.set_default_texture_parameter("rw_noise_tex", RunwayNoise.texture())
	_new = ShaderMaterial.new()
	_new.shader = sh
	var u := RunwayMarkings.uniforms(_rwy)
	for k in u:
		_new.set_shader_parameter(k, u[k])
	_new.set_shader_parameter("glyphs", RunwayGlyphs.texture())
	var tb := Time.get_ticks_usec()
	_new.set_shader_parameter("bake_tex", RunwayBake.bake(_rwy, u, self))
	var tb2 := Time.get_ticks_usec()
	RunwayBake.bake(_rwy, u, self)  # again: the steady cost once the bake shader is compiled
	print("RWPV bake again: %.1f ms" % ((Time.get_ticks_usec() - tb2) / 1000.0))
	print("RWPV bake %s: %.1f ms, %s texels, %.1f MB" % [RunwayBake.size_for(_rwy), (Time.get_ticks_usec() - tb) / 1000.0, RunwayBake.size_for(_rwy), RunwayBake.bytes_for(_rwy) / 1048576.0])
	var detail := RunwayQuality.level(Graphics.preset)
	detail = int(_env("RWPV_DETAIL", str(detail)))
	RenderingServer.global_shader_parameter_set("runway_detail", detail)
	_new.set_shader_parameter("bake_mix", 1.0)
	var marks := []
	for m in MARKS:  # along / yaw given for the landing end; stored from ends[0]
		marks.append(m if _end == 0 else Vector4(float(_rwy.length) - m.x, -m.y, m.z + PI, m.w))
	marks.resize(32)
	for i in 32:
		if marks[i] == null:
			marks[i] = Vector4.ZERO
	_new.set_shader_parameter("marks", marks)
	_new.set_shader_parameter("mark_count", MARKS.size())
	_new.set_shader_parameter("marks_along", Vector2(0.0, float(_rwy.length)))
	print("RWPV uniforms ", u, " detail ", detail)


## Landing threshold (ENU), unit direction of landing, unit right of it.
func _thr() -> Vector2:
	var e: Dictionary = _rwy.ends[_end]
	return Vector2(e.x, e.y)


func _dir() -> Vector2:
	var e: Dictionary = _rwy.ends[1 - _end]
	return (Vector2(e.x, e.y) - _thr()).normalized()


func _gnd(p: Vector2) -> float:
	return f.terrain.height_at(p.x, p.y)


## Free camera at p (ENU), `agl` metres above the ground, looking at q (`q_agl` above the ground).
func _free(p: Vector2, agl: float, q: Vector2, q_agl := 0.0) -> void:
	cam.set_mode(CameraRig.Mode.FREE)
	var from := Vector3(p.x, p.y, _gnd(p) + agl)
	var d := Vector3(q.x, q.y, _gnd(q) + q_agl) - from
	cam._free_enu = from
	cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))


## Straight down over p from h metres, runway across the frame.
func _overhead(p: Vector2, h: float) -> void:
	cam.set_mode(CameraRig.Mode.FREE)
	cam._free_enu = Vector3(p.x, p.y, _gnd(p) + h)
	var u := _dir()
	cam._look = Vector2(PI * 0.5 - atan2(u.x, u.y), -PI * 0.5 + 0.002)


func _view(name: String) -> void:
	var t := _thr()
	var u := _dir()
	var rt := Vector2(u.y, -u.x)
	var L := float(_rwy.length)
	var aim := float(RunwayMarkings.aiming_point(L, float(_rwy.width)).dist)
	match name:
		"cockpit": cam.set_mode(CameraRig.Mode.COCKPIT)
		"chase", "wet", "high", "low": cam.set_mode(CameraRig.Mode.CHASE)
		"final": _free(t - u * 5556.0, 305.0, t + u * 300.0)
		"final1nm": _free(t - u * 1852.0, 100.0, t + u * 300.0)
		"tdz", "concrete": _free(t + u * (aim - 230.0) - rt * 12.0, 91.0, t + u * (aim + 60.0))
		"closeup": _free(t + u * (aim + 30.0) + rt * 1.0, 1.7, t + u * (aim + 42.0) + rt * 4.0)
		"farend": _free(t + u * (L - 160.0), 22.0, t + u * (L - 40.0))
		"overhead": _overhead(t + u * L * 0.5, L * 0.52)
		"overtdz": _overhead(t + u * (aim + 100.0), 320.0)
		"lowsun": _free(t + u * (aim - 220.0) + rt * 7.0, 9.0, t + u * (aim + 250.0))
		"tdzlow": _free(t + u * (aim - 60.0) + rt * 2.0, 12.0, t + u * (aim + 120.0))


## Sharp, dry lens for review shots (free-camera depth of field, raindrops on the lens), the window at 1600 x 900;
## again before every shot: a window resize re-applies the preset (and the post effects).
func _clean_lens() -> void:
	if get_window().size != Vector2i(1600, 900):
		get_window().size = Vector2i(1600, 900)
	var fx := f.get_node_or_null("PostFxDriver")
	if fx:
		fx.flags["depth_of_field"] = false
		fx.flags["lens_rain"] = false


func _shot(name: String) -> void:
	_view(name)
	if name == "lowsun":
		Props.set_v("weather/time_h", 18.0)
	if name == "concrete":
		_new.set_shader_parameter("concrete_ends_m", 600.0)
	await _settle(20.0)
	await _wait(2.5)  # auto exposure
	_clean_lens()
	await _wait(0.5)
	_mi.material_override = _old
	await _wait(1.2)
	_save(name + "_old")
	_mi.material_override = _new
	await _wait(1.2)
	_save(name + "_new")
	Props.set_v("weather/time_h", float(Session.setup.time_h))
	_new.set_shader_parameter("concrete_ends_m", 0.0)


func _save(name: String) -> void:
	var p := _out.path_join(name + _env("RWPV_TAG", "") + ".png")
	get_viewport().get_texture().get_image().save_png(p)
	print("RWPV saved ", p)


## GPU cost of the swap at one view: whole frames drawn and waited for (force_draw + force_sync, so the loop time is
## the GPU time even where the driver has no GPU timestamps, e.g. Metal), old and new interleaved, medians.
func _gpu(view: String) -> void:
	_view(view)
	await _settle(20.0)
	await _wait(1.0)
	var t := {"old": [], "new": []}
	for rep in 41:
		for which in ["old", "new"]:
			_mi.material_override = _old if which == "old" or _env("RWPV_AA", "") != "" else _new  # RWPV_AA=1: old vs old (noise floor)
			RenderingServer.force_draw(false)
			RenderingServer.force_sync()
			var t0 := Time.get_ticks_usec()
			for i in 4:
				RenderingServer.force_draw(false)
				RenderingServer.force_sync()
			if rep > 0:
				t[which].append((Time.get_ticks_usec() - t0) / 4000.0)
		await get_tree().process_frame
	t.old.sort()
	t.new.sort()
	var o: float = t.old[t.old.size() / 2]
	var w: float = t.new[t.new.size() / 2]
	var vp := get_viewport()
	print("RWPV gpu %s [%s %s, %s x%.2f]: frame old %.3f ms, new %.3f ms, extra %.3f ms" % [view, Graphics.preset,
		Graphics.renderer(), vp.size, vp.scaling_3d_scale, o, w, w - o])
