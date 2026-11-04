extends Node
## Volumetric fog (G5: world/volumetric_fog.gd, vfog_rules.gd, vfog_composite.gd): the presets' levels, the weather
## maps (mist, shafts, rain, night, cloud), the storm-cell curtains (same cells as CloudStorm), the composite's slice
## spacing and Environment-fog check, and the node headless: one node per scene, off unless wanted, volumes placed
## from world positions and moved with FloatingOrigin shifts.

var _scene: Node3D
var _saved := {}


func teardown() -> void:
	if _scene:
		_scene.free()
		_scene = null
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)  # was not set before the test
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()


func _prop(k: String, v: Variant) -> void:
	if not _saved.has(k):
		_saved[k] = Props.get_v(k) if Props.has(k) else null
	Props.set_v(k, v)


func test_vfog_levels_per_preset() -> String:
	var want := {"low": 0, "medium": 0, "high": 1, "ultra": 2, "max": 3}
	for p in want:
		if int(Graphics.PRESETS[p].get("vfog", -1)) != want[p]:
			return "preset %s should have vfog %d" % [p, want[p]]
	var prev := {}
	for lvl in [1, 2, 3]:
		var q := VfogRules.quality(lvl)
		for k in ["size", "depth", "length", "slices", "reproject"]:
			if not q.has(k):
				return "quality %d lacks %s" % [lvl, k]
		if not prev.is_empty() and (q.size < prev.size or q.depth < prev.depth or q.length < prev.length or q.slices < prev.slices):
			return "quality %d should not be below %d" % [lvl, lvl - 1]
		prev = q
	if not VfogRules.quality(0).is_empty():
		return "level 0 is off"
	return "" if VfogRules.quality(2).length >= 10000.0 else "Ultra must reach storm curtains 10 km out"


func test_vfog_slices_round_trip() -> String:
	for z in [20.0, 37.0, 250.0, 1200.0, 4999.0]:
		var s := VfogRules.slice_index(z, 24.0, 20.0, 5000.0)
		var back := VfogRules.slice_depth(s, 24.0, 20.0, 5000.0)
		if absf(back - z) > 0.01 * z:
			return "slice %f -> %f -> %f" % [z, s, back]
	if VfogRules.slice_index(1e9, 24.0, 20.0, 5000.0) != 24.0 or VfogRules.slice_index(5.0, 24.0, 20.0, 5000.0) != 0.0:
		return "out-of-range depths clamp to the end planes"
	if VfogRules.slice_depth(1.0, 24.0, 20.0, 5000.0) > 40.0:
		return "the planes are spaced finer near the camera"
	var far := VfogRules.composite_far(10000.0, WeatherVisuals.fog_density(30000.0))
	if far != 10000.0 or VfogRules.composite_far(10000.0, 0.05) > 200.0 or 1.0 - exp(-VfogRules.composite_far(1e6, 3e-4) * 3e-4) > 0.76:
		return "composite reaches the froxel length in clear air, stops early in dense fog: %f" % far
	return ""


func test_vfog_env_fog_check() -> String:
	var env := Environment.new()
	env.fog_enabled = true
	if not VfogComposite.env_fog_invertible(env):
		return "plain exponential fog can be undone"
	env.fog_aerial_perspective = 0.5
	if VfogComposite.env_fog_invertible(env):
		return "aerial perspective fog cannot be undone"
	env.fog_aerial_perspective = 0.0
	env.fog_sun_scatter = 0.2
	return "" if not VfogComposite.env_fog_invertible(env) else "sun scatter cannot be undone"


func test_vfog_mist_conditions() -> String:
	var dawn := VfogRules.mist(6.5, 2.0, 5000.0, 0.3, 2.0, 0.1)
	if dawn < 0.6:
		return "calm humid dawn should be misty: %f" % dawn
	if VfogRules.mist(13.0, 70.0, 5000.0, 0.3, 2.0, 0.1) > 0.0:
		return "no mist at noon"
	if VfogRules.mist(6.5, 2.0, 40000.0, 0.0, 2.0, 0.1) > 0.05:
		return "no mist on a dry, clear morning"
	if VfogRules.mist(6.5, 2.0, 5000.0, 0.3, 20.0, 0.1) > 0.05:
		return "wind mixes the mist away"
	if VfogRules.mist(6.5, 2.0, 5000.0, 0.3, 2.0, 1.0) >= dawn:
		return "an overcast night forms less mist"
	var ml := VfogRules.mist_layer(1.0, 550.0)
	if ml.top <= 550.0 or ml.top > 800.0 or ml.density <= 0.001:
		return "thick mist fills the low ground to a ~150 m top: %s" % ml
	return "" if VfogRules.mist_layer(0.0, 0.0).density == 0.0 else "no mist, no density"


func test_vfog_shafts_rain_night_cloud() -> String:
	var haze := WeatherVisuals.fog_density(15000.0)
	var broken := VfogRules.shaft_density(0.6, haze, 30.0, 0.0)
	if broken <= VfogRules.shaft_density(0.0, haze, 30.0, 0.0) or broken <= VfogRules.shaft_density(1.0, haze, 30.0, 0.0):
		return "shafts are strongest under broken cloud"
	if broken > 3.0 * haze:
		return "shaft air stays a share of the haze (no double haze): %f vs %f" % [broken, haze]
	if VfogRules.rain_density(0.1) > 0.0 or VfogRules.rain_density(1.0) <= 0.0:
		return "rain streaks only in heavy rain"
	if VfogRules.night_density(1.0, haze, 15000.0) > 0.0 or VfogRules.night_density(0.08, haze, 15000.0) <= 0.0:
		return "the glow air is there only after dark"
	if VfogRules.cloud_density(0.0, 0.05) > 0.0 or VfogRules.cloud_density(1.0, 0.05) >= 0.05:
		return "in-cloud puffs only add to CloudInside's fog"
	return ""


func test_vfog_curtains_are_the_storm_cells() -> String:
	if not VfogRules.storm_cells(Vector2.ZERO, 0.0, Vector2.ZERO, 0.0).is_empty():
		return "no storms, no curtains"
	var wind := Vector2(4.0, -2.0)
	var found := 0
	for k in 12:
		var cam := Vector2(k * 23000.0, k * -17000.0)
		var a := VfogRules.storm_cells(cam, 600.0, wind, 0.7)
		if a != VfogRules.storm_cells(cam, 600.0, wind, 0.7):
			return "the curtains must be deterministic"
		if a.size() > VfogRules.MAX_CURTAINS:
			return "at most %d curtains" % VfogRules.MAX_CURTAINS
		for i in a.size():
			if i > 0 and a[i].dist < a[i - 1].dist:
				return "nearest first"
			var p: Vector2 = a[i].center
			var st := CloudStorm.sample(Vector3(p.x, p.y, 300.0), 300.0, 600.0, wind, 0.7, 600.0)
			if st.intensity < 0.3:
				return "a curtain at %s should sit on a storm core (intensity %f)" % [p, st.intensity]
		found += a.size()
	return "" if found > 0 else "monsoon storms should give curtains somewhere"


func _scene_with_camera() -> Camera3D:
	_scene = Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	we.environment.fog_enabled = true
	_scene.add_child(we)
	var cam := Camera3D.new()
	_scene.add_child(cam)
	add_child(_scene)
	cam.make_current()
	return cam


func test_vfog_node_headless() -> String:
	var cam := _scene_with_camera()
	var n := VolumetricFog.apply(_scene, 2)
	VolumetricFog.apply(_scene, 2)
	if _scene.get_children().filter(func(c): return c is VolumetricFog).size() != 1:
		return "one VolumetricFog under the scene"
	var env := (_scene.get_node("WorldEnvironment") as WorldEnvironment).environment
	n.level = 0
	n.forced = true
	n.step(0.016)
	if n.active or env.volumetric_fog_enabled or n.composite.visible:
		return "level 0 is off"
	n.level = 2
	_prop("weather/cloud_cover", 0.6)
	_prop("environment/visibility_m", 8000.0)
	n.step(0.016)
	if not n.active or not env.volumetric_fog_enabled or n.composite.get_parent() != cam:
		return "forced on: fog on, composite on the camera"
	var haze := WeatherVisuals.fog_density(8000.0)
	if env.volumetric_fog_density <= 0.0 or env.volumetric_fog_density > 1.5 * haze or env.volumetric_fog_sky_affect != 0.0:
		return "thin air (a share of the haze, %f) in the Environment density (%f); the composite fogs the sky" % [haze, env.volumetric_fog_density]
	if env.volumetric_fog_emission != env.fog_light_color or env.volumetric_fog_ambient_inject != 0.0:
		return "the froxel air glows with the haze colour (no darker or re-tinted haze)"
	if not VfogRules.MIST_ENABLED and float((n.air.material as ShaderMaterial).get_shader_parameter("mist")) != 0.0:
		return "dawn mist is gated off (VfogRules.MIST_ENABLED)"
	if float((n.air.material as ShaderMaterial).get_shader_parameter("cut")) < env.volumetric_fog_density + VfogRules.VOLUME_STEP:
		return "the cloud-shadow cut must remove all the thin air"
	if env.volumetric_fog_length != VfogRules.quality(2).length:
		return "froxel length from the quality level"
	if not n.air.visible or n.air.global_position.distance_to(cam.global_position) > 0.01:
		return "the air volume is centred on the camera"
	n.forced = false
	if n.wanted() and RenderingServer.get_current_rendering_method() != "forward_plus":
		return "never wanted off Forward+"
	return ""


func test_vfog_follows_floating_origin() -> String:
	var cam := _scene_with_camera()
	var n := VolumetricFog.apply(_scene, 2)
	n.forced = true
	_prop("weather/cloud_cover", 1.0)
	_prop("weather/cloud_base_ft", 1200.0)
	_prop("weather/precip", 0.9)
	_prop("weather/storms", 0.7)
	_prop("weather/convection", 0.5)
	_prop("weather/turbulence", 0.55)
	var kind := str(CloudPhysics.conditions().kind)
	if kind != CloudField.CUMULONIMBUS:
		return "monsoon settings should be cumulonimbus (got %s)" % kind
	var spot := Vector2.ZERO  # a camera position with a storm cell in reach
	for k in 40:
		var p := Vector2(k * 9000.0, k * -7000.0)
		if not VfogRules.storm_cells(p, n._storm_clock(_scene), Vector2.ZERO, 0.7).is_empty():
			spot = p
			break
	_prop("weather/aloft_kt", 0.0)
	var saved_origin := FloatingOrigin.origin
	FloatingOrigin.set_origin(spot.snapped(Vector2(5000.0, 5000.0)))
	cam.global_position = FloatingOrigin.to_render(Vector3(spot.x, spot.y, 600.0))
	n.step(0.016)
	var cur := n.curtains[0]
	if not cur.visible:
		FloatingOrigin.set_origin(saved_origin)
		return "a curtain should show near %s" % spot
	var world := FloatingOrigin.to_world(cur.global_position)
	FloatingOrigin.set_origin(FloatingOrigin.origin + Vector2(5000.0, -5000.0))
	var after := FloatingOrigin.to_world(cur.global_position)
	FloatingOrigin.set_origin(saved_origin)
	if Vector2(after.x, after.y).distance_to(Vector2(world.x, world.y)) > 0.5:
		return "a shift must not move the curtain in the world: %s -> %s" % [world, after]
	return ""


func test_vfog_shaders_load() -> String:
	for p in ["res://world/vfog_air.gdshader", "res://world/vfog_rain.gdshader", "res://world/vfog_composite.gdshader"]:
		var s := load(p) as Shader
		if s == null or s.code.is_empty():
			return "%s did not load" % p
	if VfogComposite.build_mesh(16).get_faces().size() != 17 * 6:
		return "the composite is n + 1 quads in one mesh"
	return ""
