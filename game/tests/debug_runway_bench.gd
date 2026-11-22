extends Node3D
## Debug (realistic runways): GPU cost of world/runway_v2.gdshader against the taxiway shader (the cost of the old
## flat runway: strip.gdshaderinc) per screen pixel, on a
## synthetic runway piece filling the frame (touchdown zone seen from 25 m), in 6 views of 2560x1440 so the GPU is the
## bottleneck. Each draw is forced and waited for (force_draw + force_sync), alternating old / new (drivers without GPU
## timestamps, e.g. Metal, report 0 from viewport_get_measured_render_time_gpu). Prints ns per pixel. Needs a display; mute it:
##   godot --path game res://tests/debug_runway_bench.tscn --audio-driver Dummy [--rendering-method mobile] -- [--detail=0]

const VIEWS := 6
const VIEW_PX := Vector2i(2560, 1440)
var _mi: MeshInstance3D
var _detail := 2
var _old: ShaderMaterial
var _new: ShaderMaterial


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)  # always silent (also run with --audio-driver Dummy)
	get_window().size = Vector2i(1600, 900)
	var r := {"airport": "VABB", "width": 60.0, "length": 3470.2, "ends": [{"ident": "27", "heading_true": 269.4},
		{"ident": "09", "heading_true": 89.4}]}
	var cell := 900.0  # --cell=7.5: cut into lattice cells like GroundDrape (many small triangles far away)
	var msaa := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cell="):
			cell = float(a.substr(7))
		if a.begins_with("--msaa="):
			msaa = int(a.substr(7))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var nx := maxi(int(ceil(60.0 / cell)), 1)
	var ny := maxi(int(ceil(900.0 / cell)), 1)
	for iy in ny:
		for ix in nx:
			for q in [[0.0, 0.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0], [0.0, 1.0], [1.0, 1.0]]:  # clockwise from above
				var u: float = (ix + q[0]) / nx
				var v: float = (iy + q[1]) / ny
				st.set_uv(Vector2(u, 150.0 + v * 900.0))
				st.add_vertex(Vector3((u - 0.5) * 60.0, 0.0, -v * 900.0))
	_mi = MeshInstance3D.new()
	_mi.mesh = st.commit()
	add_child(_mi)
	_old = ShaderMaterial.new()
	_old.shader = load("res://world/taxiway.gdshader")
	for k in ["is_runway", "length_m", "width_m"]:
		_old.set_shader_parameter(k, RunwayMarkings.uniforms(r)[k])
	var sh: Shader = load("res://world/runway_v2.gdshader")
	TerrainDetail.apply(sh)
	sh.set_default_texture_parameter("rw_noise_tex", RunwayNoise.texture())
	_new = ShaderMaterial.new()
	_new.shader = sh
	var u := RunwayMarkings.uniforms(r)
	for k in u:
		_new.set_shader_parameter(k, u[k])
	_new.set_shader_parameter("glyphs", RunwayGlyphs.texture())
	var tb := Time.get_ticks_usec()
	_new.set_shader_parameter("bake_tex", RunwayBake.bake(r, u, self))
	print("RWPV bake %s: %.1f ms, %s texels, %.1f MB" % [RunwayBake.size_for(r), (Time.get_ticks_usec() - tb) / 1000.0, RunwayBake.size_for(r), RunwayBake.bytes_for(r) / 1048576.0])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--detail="):
			_detail = int(a.substr(9))
	RenderingServer.global_shader_parameter_set("runway_detail", _detail)
	_new.set_shader_parameter("bake_mix", 1.0)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	for i in VIEWS:  # several full-size views of the same piece: enough pixels that the GPU sets the frame time
		var vp := SubViewport.new()
		vp.size = VIEW_PX
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][msaa]
		add_child(vp)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.fov = 35.0
		cam.look_at_from_position(Vector3(0.0, 25.0, -i * 40.0), Vector3(0.0, 0.0, -120.0 - i * 40.0))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var px := Vector2(VIEW_PX.x * VIEWS, VIEW_PX.y)
	var t := {"old": [], "new": []}
	for rep in 41:  # interleaved rounds of 6 forced draws (each waited for: loop time = GPU time); medians
		for which in ["old", "new"]:
			_mi.material_override = _old if which == "old" else _new
			RenderingServer.force_draw(false)
			RenderingServer.force_sync()
			var t0 := Time.get_ticks_usec()
			for i in 6:
				RenderingServer.force_draw(false)
				RenderingServer.force_sync()
			if rep > 0:  # the first round warms up (pipeline compiles)
				t[which].append((Time.get_ticks_usec() - t0) / 6000.0)
		await get_tree().process_frame
	var shot := OS.get_environment("RWPV_BENCH_SHOT")
	if shot != "":
		(get_child(-1) as SubViewport).get_texture().get_image().save_png(shot)
	t.old.sort()
	t.new.sort()
	var o: float = t.old[t.old.size() / 2]
	var w: float = t.new[t.new.size() / 2]
	print("RWPV bench [%s, detail %d, %dx%d px]: draw old %.3f ms, new %.3f ms -> %.3f ms extra per megapixel" % [
		RenderingServer.get_current_rendering_method(), _detail, px.x, px.y, o, w,
		(w - o) * 1e6 / (px.x * px.y)])
	get_tree().quit()
