extends Node
## Sky radiance updates (perf study F9): Godot redraws the sky's radiance cubemap after any write to a sky uniform, so
## SkyParams (world/sky_params.gd) writes only real changes, SkyTime moves the sun in 10 s steps, and the flight sky is
## INCREMENTAL (QUALITY "should not be used if you plan on changing the sky at runtime", Godot's Sky docs).

var _scene: Node3D
var _saved := {}


func teardown() -> void:
	if _scene:
		_scene.free()
		_scene = null
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()


func _prop(k: String, v: Variant) -> void:
	if not _saved.has(k):
		_saved[k] = Props.get_v(k) if Props.has(k) else null
	Props.set_v(k, v)


func test_flight_sky_is_incremental() -> String:
	var flight: Node = load("res://world/flight.tscn").instantiate()
	var sky := (flight.get_node("WorldEnvironment") as WorldEnvironment).environment.sky
	var mode := sky.process_mode
	flight.free()
	if mode != Sky.PROCESS_MODE_INCREMENTAL:
		return "the flight sky changes at run time: INCREMENTAL, not mode %d (QUALITY rebuilt the cubemap every frame)" % mode
	return ""


func test_same_value_is_written_once() -> String:
	var p := SkyParams.new()
	p.stage(&"day", 0.5)
	p.stage(&"horizon_color", Color(0.7, 0.8, 0.9))
	if p.flush() != 2:
		return "the first frame writes every staged uniform"
	p.stage(&"day", 0.5)
	p.stage(&"horizon_color", Color(0.7, 0.8, 0.9))
	if p.flush() != 0:
		return "an unchanged value must not be written again (any write redraws the radiance cubemap)"
	p.stage(&"day", 0.5015)
	p.stage(&"horizon_color", Color(0.701, 0.8, 0.9))
	if p.flush() != 0:
		return "changes under the step stay unwritten"
	p.stage(&"day", 0.51)
	p.stage(&"horizon_color", Color(0.71, 0.8, 0.9))
	if p.flush() != 2:
		return "changes past the step are written"
	p.stage(&"day", 0.0)
	p.flush()
	p.stage(&"day", 0.0005)
	p.stage(&"day", 0.0)  # the last stage of a frame wins
	if p.flush() != 0 or p.want(&"day") != 0.0:
		return "the last staged value wins; reaching 0 again is not a change"
	return ""


func test_slow_drift_arrives_in_small_steps_and_exact_ends() -> String:
	var p := SkyParams.new()
	var writes := 0
	var last := 0.0
	for i in 1001:  # 0 -> 1 over 1000 frames
		var v := float(i) / 1000.0
		p.stage(&"day", v)
		if p.flush() > 0:
			writes += 1
			if v - last > SkyParams.STEP_FLOAT + 0.0011:
				return "a step of %f is too big to hide" % (v - last)
			last = v
	if writes > 600:
		return "a slow fade should be written in a few hundred steps, not every frame (%d)" % writes
	if p.want(&"day") != 1.0 or last != 1.0:
		return "a fade must end on exactly 1"
	var q := SkyParams.new()
	q.stage(&"horizon_dip", 0.03)
	q.flush()
	q.stage(&"horizon_dip", 0.0305)  # half a pixel of horizon: finer than the float step
	if q.flush() != 1:
		return "horizon_dip uses its own finer step"
	return ""


func test_vector4_and_per_instance_steps() -> String:
	# CloudLayer's shadow global is a Vector4 and its uniforms include metres and tiny extinctions (step_by_name).
	if SkyParams.changed(Vector4(1400, 0.5, 0.3, 0), Vector4(1400, 0.5, 0.3005, 0)):
		return "a Vector4 moving under the float step is not a change"
	if not SkyParams.changed(Vector4(1400, 0.5, 0.3, 0), Vector4(1400, 0.5, 0.0, 0)):
		return "a Vector4 component reaching exactly 0 (shadows off) is a change"
	var p := SkyParams.new()
	p.step_by_name = {&"air_haze": 0.0}
	p.stage(&"air_haze", 1.8e-5)
	p.flush()
	p.stage(&"air_haze", 2.0e-5)
	if p.flush() != 1:
		return "a per-instance step of 0 writes any change (the default 0.002 would freeze a 2e-5 extinction)"
	if SkyParams.STEP_BY_NAME.has(&"air_haze"):
		return "the sky's own steps stay as they were"
	return ""


func test_want_reads_this_frame_then_the_written_value() -> String:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/sky_clouds.gdshader")
	var p := SkyParams.new(mat)
	p.stage(&"zenith_color", Color(0.2, 0.4, 0.8))
	if p.want(&"zenith_color") != Color(0.2, 0.4, 0.8):
		return "want() sees this frame's staged value (CloudInside lerps it)"
	p.flush()
	if mat.get_shader_parameter(&"zenith_color") != Color(0.2, 0.4, 0.8):
		return "flush writes to the material"
	p.stage(&"zenith_color", Color(0.9, 0.9, 0.9))  # CloudInside's override this frame
	p.flush()
	if p.want(&"zenith_color") != Color(0.9, 0.9, 0.9):
		return "after a flush want() returns the value written"
	return ""


func _sky_scene() -> SkyTime:
	_scene = Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	we.environment.sky = Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/sky_clouds.gdshader")
	we.environment.sky.sky_material = mat
	_scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	_scene.add_child(sun)
	var st := SkyTime.new()
	st.sun_path = NodePath("../Sun")
	st.env_path = NodePath("../WorldEnvironment")
	st.set_process(false)  # stepped by hand
	_scene.add_child(st)
	add_child(_scene)
	return st


func test_still_sky_writes_nothing_and_the_sun_moves_in_steps() -> String:
	_prop("weather/time_h", 10.0)
	_prop("weather/day_of_year", 45.0)
	_prop("weather/time_rate", 1.0)
	_prop("weather/aloft_kt", 0.0)
	_prop("weather/cloud_cover", 0.0)
	_prop("environment/precip", 0.0)
	_prop("environment/lightning", 0.0)
	var st := _sky_scene()
	st._process(0.016)
	var first := st.params.writes
	if first < 10:
		return "the first frame writes the sky uniforms (%d)" % first
	var sun_basis := (_scene.get_node("Sun") as Node3D).global_basis
	for i in 60:  # one second at 60 fps: the clock runs, the sun stays inside its 10 s step
		st._process(1.0 / 60.0)
	if st.params.writes != first:
		return "a sky that did not visibly change wrote %d uniforms in a second" % (st.params.writes - first)
	if not (_scene.get_node("Sun") as Node3D).global_basis.is_equal_approx(sun_basis):
		return "the sun moves in 10 s steps, not every frame (its light is part of the radiance)"
	Props.set_v("weather/time_h", Props.get_f("weather/time_h") + 60.0 / 3600.0)
	st._process(0.016)
	if st.params.writes == first:
		return "a minute later the sun has moved: the sky follows"
	return ""
