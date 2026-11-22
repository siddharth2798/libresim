extends Node
## Ground particle effects (graphics Phase 3, world/ground_fx.gd): preset counts (ground_fx_quality.gd), wheel spray,
## rooster tail and dust rates (wheel_spray.gd), engine wash (engine_wash.gd), rain splashes (rain_splash.gd), the
## floating-origin anchoring of every emitter (ground_emitter.gd), paved or not (ground_surface.gd), the rain ripples
## in the pavement shaders, and the real C172 / A320 FDM rolling on a wet and a dry runway.

var _nodes: Array = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			for p in n.find_children("*", "AudioStreamPlayer3D", true, false):
				p.stop()
			n.free()
	_nodes.clear()
	FloatingOrigin.set_origin(Vector2.ZERO)
	Props.set_v("environment/wetness", 0.0)
	Props.set_v("environment/precip", 0.0)


func _keep(n: Node) -> Node:
	add_child(n)
	_nodes.append(n)
	return n


## A GroundFx on the real FDM of an aircraft, standing on the ground at the origin, everything paved.
func _fx(id: String, preset: String) -> GroundFx:
	var def := AircraftDef.load_def(id)
	var fn := FdmNode.new()
	fn.fdm = FDM.new(def)
	fn.fdm.set_on_ground(0.0, 0.0, 0.0)
	_nodes.append(fn)
	var g := GroundFx.new()
	g.surface.fixed = 1
	_keep(g)
	g.setup(fn, def)
	g.set_counts(GroundFxQuality.counts(preset))
	g.set_process(false)
	return g


static func _particles(n: Node) -> Array:
	return n.find_children("*", "GPUParticles3D", true, false)


func test_ground_fx_preset_counts_scale() -> String:
	var low := GroundFxQuality.counts("low")
	for k in low:
		if int(low[k]) != 0:
			return "Low has no ground particles at all (%s = %d)" % [k, low[k]]
	for k in ["splash", "spray", "wash", "dust"]:
		var prev := 0
		for p in ["medium", "high", "ultra", "max"]:
			var n := int(GroundFxQuality.counts(p)[k])
			if n <= prev:
				return "%s grows with every preset above Low (%s: %d after %d)" % [k, p, n, prev]
			prev = n
	if int(GroundFxQuality.counts("medium").tail) != 0 or int(GroundFxQuality.counts("high").tail) <= 0:
		return "the rooster tail starts on High"
	var compat := GroundFxQuality.counts("max", "gl_compatibility")
	for k in compat:
		if int(compat[k]) > int(GroundFxQuality.counts("medium")[k]):
			return "the Compatibility renderer is held to the Medium counts (%s = %d)" % [k, compat[k]]
	return ""


func test_ground_fx_spray_zero_dry_or_stopped_and_rises() -> String:
	for gs in [0.0, 10.0, 40.0, 70.0]:
		if WheelSpray.spray_rate(gs, 0.0) != 0.0 or WheelSpray.tail_rate(gs, 0.0) != 0.0:
			return "no spray on a dry runway (gs %.0f)" % gs
	if WheelSpray.spray_rate(0.0, 1.0) != 0.0 or WheelSpray.spray_rate(1.5, 1.0) != 0.0:
		return "no spray from a stopped or creeping wheel"
	var a := WheelSpray.spray_rate(6.0, 0.8)
	var b := WheelSpray.spray_rate(20.0, 0.8)
	var c := WheelSpray.spray_rate(40.0, 0.8)
	if not (a > 0.0 and b > a and c > b):
		return "spray rises with ground speed (%.2f, %.2f, %.2f)" % [a, b, c]
	var w1 := WheelSpray.spray_rate(30.0, 0.2)
	var w2 := WheelSpray.spray_rate(30.0, 0.45)
	var w3 := WheelSpray.spray_rate(30.0, 0.9)
	if not (w1 > 0.0 and w2 > w1 and w3 > w2):
		return "spray rises with wetness (%.2f, %.2f, %.2f)" % [w1, w2, w3]
	if WheelSpray.spray_rate(30.0, 0.9, false) >= w3:
		return "wet grass throws less than a wet runway"
	if WheelSpray.tail_rate(8.0, 1.0) != 0.0 or WheelSpray.tail_rate(45.0, 1.0) < 0.99:
		return "the rooster tail only at takeoff and landing speeds"
	return ""


func test_ground_fx_dust_only_dry_unpaved() -> String:
	if WheelSpray.dust_rate(20.0, 0.0, true) + WheelSpray.dust_rate(20.0, 0.8, false) + WheelSpray.dust_rate(0.0, 0.0, false) != 0.0:
		return "no dust on pavement, off wet grass or from a stopped wheel"
	if WheelSpray.dust_rate(20.0, 0.0, false) <= 0.5:
		return "dust rolling on dry grass"
	var w := WheelSpray.new()
	_keep(w)
	w.set_counts(GroundFxQuality.counts("high"))
	w.touchdown(0.0, false)
	w.update(true, Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, 0.0, 0.0, false, Vector3.ZERO, 0.01)
	if not w.dust.emitting:
		return "a wheel landing on dry grass puffs dust"
	w.clear()
	w.touchdown(0.0, true)
	w.update(true, Vector3.ZERO, Vector3.ZERO, Vector3.FORWARD, 0.0, 0.0, true, Vector3.ZERO, 0.01)
	if w.dust.emitting:
		return "no dust puff landing on pavement"
	return ""


func test_ground_fx_wash_by_thrust_and_surface() -> String:
	if EngineWash.wash_k(100.0, 2300.0) != 0.0 or EngineWash.wash_k(2300.0, 2300.0) < 0.99:
		return "no wash at idle, full at full static thrust"
	var wet: Array = EngineWash.wash_rate(1.0, 0.8, 0.0, true)
	if wet[0] <= 0.5 or wet[1]:
		return "full power standing on wet pavement blows mist (got %s)" % [wet]
	if EngineWash.wash_rate(1.0, 0.8, 30.0, true)[0] + EngineWash.wash_rate(1.0, 0.0, 0.0, true)[0] != 0.0:
		return "no wash mist on dry pavement or by takeoff speed"
	if EngineWash.wash_rate(1.0, 0.8, 0.0, true, true)[0] >= wet[0]:
		return "a jet only stirs a lighter mist"
	var dry: Array = EngineWash.wash_rate(1.0, 0.0, 0.0, false)
	if dry[0] <= 0.0 or not dry[1]:
		return "full power on dry grass raises dust"
	var c172 := AircraftDef.load_def("c172")
	var ref := EngineWash.thrust_ref(FDM.new(c172).units[0])
	if ref < 1500.0 or ref > 3500.0:
		return "the C172 prop's full static thrust is about 2.3 kN (got %.0f N)" % ref
	return ""


func test_ground_fx_splashes_off_without_rain() -> String:
	if RainSplash.strength(0.0, 2.0) != 0.0:
		return "no splashes without rain"
	if RainSplash.strength(0.8, 2.0) <= 0.5:
		return "splashes in heavy rain near the ground"
	if RainSplash.strength(0.8, RainSplash.MAX_AGL + 1.0) != 0.0:
		return "no splashes seen from high up"
	if RainSplash.strength(0.8, 2.0, 5.0) != 0.0:
		return "no splashes on uneven ground (they would float)"
	var cam: Camera3D = _keep(Camera3D.new())
	cam.position = Vector3(0.0, 3.0, 0.0)
	var s: RainSplash = _keep(RainSplash.new())
	s.set_capacity(600)
	s.update(cam, 0.0)
	if s.emitting:
		return "a dry day: the splash emitter stays off"
	s.update(cam, 0.8)
	if not s.emitting or absf(s.amount_ratio - RainSplash.strength(0.8, 3.0)) > 0.01:
		return "rain: splashes on, at the rain's strength"
	s.update(cam, 0.0)
	if s.emitting:
		return "the rain stops: the splashes stop"
	s.set_capacity(0)
	s.update(cam, 0.8)
	return "" if not s.emitting and not s.visible else "a preset with no splashes never emits"


func test_ground_fx_low_builds_no_particles() -> String:
	for id in ["c172", "a320"]:
		var low := _fx(id, "low")
		if not _particles(low).is_empty():
			return "%s on Low: no particle nodes at all (got %d)" % [id, _particles(low).size()]
		var high := _fx(id, "high")
		if high.wheels.size() != 3:
			return "%s: one spray set per wheel (got %d)" % [id, high.wheels.size()]
		if high.washes.size() != (2 if id == "a320" else 1):
			return "%s: one wash per engine (got %d)" % [id, high.washes.size()]
		high.set_counts(GroundFxQuality.counts("low"))
		if _particles(high).any(func(p): return p.emitting or p.visible):
			return "%s: switching to Low stops and hides every emitter" % id
	return ""


func test_ground_fx_materials_lit_not_glowing() -> String:
	for t in ["mist", "streak"]:
		var m: StandardMaterial3D = GroundFxLook.material(t)
		if m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or m.emission_enabled:
			return "%s sprites are lit by the scene and never glow at night" % t
		if m.distance_fade_mode == BaseMaterial3D.DISTANCE_FADE_DISABLED:
			return "%s sprites fade out close to the camera" % t
	var img := GroundFxTextures.mist().get_image()
	if (GroundFxLook.material("mist") as StandardMaterial3D).particles_anim_h_frames < 2 or img.get_pixel(0, 0).a > 0.01 \
			or img.get_pixel(GroundFxTextures.FRAME / 2, 0).a > 0.01 or img.get_pixel(GroundFxTextures.FRAME / 2, GroundFxTextures.FRAME / 2).a < 0.05:
		return "mist sprites pick one of several noise shapes that fade to nothing before the edge (no round discs)"
	var crown: ShaderMaterial = GroundFxLook.material("crown")
	GroundFxLook.splash_tint(0.0)
	var night: Color = crown.get_shader_parameter("tint")
	GroundFxLook.splash_tint(1.0)
	if night.v > 0.1 or (crown.get_shader_parameter("tint") as Color).v < 0.8:
		return "the unshaded splashes follow the daylight: dark at night (%.2f), white by day" % night.v
	return ""


## The real C172 rolls on a wet runway: spray and (at speed) a rooster tail from the mains; on a dry one nothing.
func test_ground_fx_c172_wet_roll_sprays_dry_roll_does_not() -> String:
	for wet in [0.9, 0.0]:
		var g := _fx("c172", "high")
		var f := g.fdm_node.fdm
		Props.set_v("environment/wetness", wet)
		f.prop.rpm = 2300.0
		f.engine.throttle = 1.0
		var seen := {"spray": false, "tail": false}
		for i in 25 * 120:
			f.fcs.yaw = clampf(-3.0 * f.euler().z if f.euler().z < PI else 3.0 * (TAU - f.euler().z), -1, 1)
			f.step(1.0 / 240.0)
			f.step(1.0 / 240.0)
			if i % 4 == 0:
				g._process(1.0 / 30.0)
				var w: WheelSpray = g.wheels.LEFT_MAIN
				seen.spray = seen.spray or w.spray.emitting
				seen.tail = seen.tail or w.tail.emitting
			if f.cas > 25.0:
				break
		if wet > 0.0 and not (seen.spray and seen.tail):
			return "wet runway: spray and a rooster tail on the takeoff roll (%s)" % [seen]
		if wet == 0.0 and (seen.spray or seen.tail):
			return "dry runway: no spray (%s)" % [seen]
	return ""


func test_ground_fx_cleared_on_new_flight() -> String:
	var def := AircraftDef.load_def("a320")
	var fn := FdmNode.new()
	fn.fdm = FDM.new(def)
	fn.fdm.set_on_ground(0.0, 0.0, 0.0)
	_nodes.append(fn)
	var fx := TouchdownFx.new()
	_keep(fx)
	fx.setup(fn, def)
	fx.set_physics_process(false)
	fx.ground.set_counts(GroundFxQuality.counts("max"))
	var parts := _particles(fx.ground)
	if parts.is_empty():
		return "Max builds the A320's ground emitters"
	for p in parts:
		p.set_rate(1.0)
	fx.clear()  # what flight.gd _reset (new flight, F5) calls
	for p in parts:
		if p.emitting or p.rate() != 0.0:
			return "%s still emitting after a reset" % p.get_path()
	return ""


func test_ground_fx_emitters_survive_origin_shift() -> String:
	var e: GroundEmitter = _keep(GroundEmitter.new("spray"))
	e.set_capacity(100)
	var enu := Vector3(4900.0, 30.0, 12.0)
	e.place(FloatingOrigin.to_render(enu))
	e.set_rate(1.0)
	var anchor := FloatingOrigin.to_world(e.position)
	var src := FloatingOrigin.to_world(e.position + e.proc.emission_shape_offset)
	FloatingOrigin.update_focus(Vector3(5100.0, 0.0, 0.0))  # crosses the 5 km step: the origin shifts
	if FloatingOrigin.origin == Vector2.ZERO:
		return "the test needs an origin shift"
	if not is_instance_valid(e) or not e.emitting:
		return "the emitter survives the shift and keeps emitting"
	if FloatingOrigin.to_world(e.position).distance_to(anchor) > 0.01:
		return "the emitter moves with the ground: live particles keep their place (anchor moved %.1f m)" % FloatingOrigin.to_world(e.position).distance_to(anchor)
	if FloatingOrigin.to_world(e.position + e.proc.emission_shape_offset).distance_to(src) > 0.01:
		return "the source stays on the same ground point across the shift"
	e.place(FloatingOrigin.to_render(enu))
	if FloatingOrigin.to_world(e.position + e.proc.emission_shape_offset).distance_to(enu) > 0.01:
		return "placing after the shift puts the source back on its ground point"
	return ""


func test_ground_fx_surface_ribbons() -> String:
	var s := GroundSurface.new()
	var o := 9.0e6  # far from any pavement mask tile
	s.setup({"runways": [{"ends": [{"x": o, "y": o}, {"x": o + 1000.0, "y": o}], "width": 45.0}],
		"taxiways": [{"pts": [[o, o + 100.0], [o, o + 400.0]], "width": 15.0}]})
	if not s.paved(o + 500.0, o + 20.0) or not s.paved(o + 5.0, o + 250.0):
		return "on a runway or taxiway ribbon is paved"
	if s.paved(o + 500.0, o + 60.0) and not s.near_runway(Vector2(o + 500.0, o + 60.0)):
		return "beside the runway is grass"
	if s.paved(o + 5000.0, o + 5000.0):
		return "far from any airport is unpaved"
	return ""


func test_ground_fx_ripples_in_pavement_shaders() -> String:
	for p in ["res://world/runway_v2.gdshader", "res://world/strip.gdshaderinc", "res://world/terrain.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		if not (src.contains("rr_grad(") or src.contains("rr_enu(")):
			return "%s draws the rain rings" % p
	for p in ["res://world/runway_v2.gdshader", "res://world/strip.gdshaderinc", "res://world/terrain_pavement.gdshaderinc"]:
		if not FileAccess.get_file_as_string(p).contains("rain_ripples.gdshaderinc"):
			return "%s includes the rain rings" % p
	var inc := FileAccess.get_file_as_string("res://world/rain_ripples.gdshaderinc")
	if not inc.contains("precip < 0.01"):
		return "the rings cost nothing when it is not raining"
	for p in ["res://world/runway_v2.gdshader", "res://world/taxiway.gdshader", "res://world/terrain.gdshader"]:
		var sh: Shader = load(p)
		if sh == null or sh.get_shader_uniform_list().is_empty():
			return "%s compiles with the rain rings" % p
	return ""
