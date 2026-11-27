extends RefCounted
## Night look of the apron: the soft floodlight cone (world/pool_profile.gd, light_pool.gdshader, apron_lamps.gd), the warm
## lamp colours (apron_light_layout.gd) and the lit jetways (world/jetway_night.gd, jetway.gdshader,
## jetway_standin.gdshader, jetway_link.gdshader, jetway_door_glow.gdshader): emission only at night (global night_level),
## nothing by day. The draw order guard is in test_apron_lights.gd.


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_terminal_night_written_only_on_change() -> String:
	# Terminals._process runs every frame; `night` goes to every terminal material only when it moved (PERFORMANCE-RULES 10).
	var t := Terminals.new()
	for i in 3:
		var m := ShaderMaterial.new()
		m.shader = preload("res://world/terminal.gdshader")
		t._mats.append(m)
	t.set_night(0.0)
	var first := t.night_writes
	for i in 30:
		t.set_night(0.0)
	var still := t.night_writes - first
	t.set_night(0.7)
	var got: float = t._mats[2].get_shader_parameter("night")
	t.free()
	if first != 3 or still != 0:
		return "first frame writes each material once (%d), unchanged frames none (%d)" % [first, still]
	return "" if is_equal_approx(got, 0.7) else "a new night level reaches the materials (%f)" % got

## The cone is 1 on the axis, 0 at the edge, never rises with the angle and has no step between neighbouring angles.
func test_pool_cone_falls_smoothly() -> String:
	var cone_cos := cos(deg_to_rad(ApronLamps.cone_deg(52.0)))
	if absf(PoolProfile.cone(1.0, cone_cos) - 1.0) > 1e-6 or PoolProfile.cone(cone_cos, cone_cos) > 1e-6:
		return "cone is not 1 on the axis and 0 at the edge"
	var prev := 1.0
	var worst := 0.0
	var n := 2000
	for i in n + 1:
		var a := deg_to_rad(ApronLamps.cone_deg(52.0)) * float(i) / n
		var f := PoolProfile.cone(cos(a), cone_cos)
		if f > prev + 1e-9:
			return "cone rises at %.1f deg" % rad_to_deg(a)
		worst = maxf(worst, prev - f)
		prev = f
	return "" if worst < 0.01 else "step of %.3f between neighbouring angles" % worst


## The shader's constants are the GDScript ones (the real lamp and the pool must match).
func test_pool_shader_matches_profile() -> String:
	var s := _src("res://world/light_pool.gdshader")
	for k in ["const float CONE_EXP = %.1f;" % PoolProfile.EXP, "const float RANGE_K = %.1f;" % ApronLamps.RANGE_K]:
		if not s.contains(k):
			return "light_pool.gdshader lacks `%s`" % k
	var lamps := ApronLamps.new()
	lamps.set_budget(1)
	var l := lamps.get_child(0) as SpotLight3D
	var ok := is_equal_approx(l.spot_angle_attenuation, PoolProfile.EXP)
	lamps.free()
	return "" if ok else "the real lamp's spot_angle_attenuation is not PoolProfile.EXP"


## Floodlights are warm (red > green > blue, clearly warmer than the old neutral white), sodium warmer than LED.
func test_lamp_colours_are_warm() -> String:
	for c in [ApronLightLayout.LED, ApronLightLayout.HPS]:
		if not (c.r > c.g and c.g > c.b) or c.b / c.r > 0.78:
			return "lamp colour %s is not warm" % c
	return "" if ApronLightLayout.HPS.b < ApronLightLayout.LED.b else "sodium should be warmer than LED"


## Every jetway shader adds light only through the night_level global (zero by day), and the door glow draws nothing by day.
func test_jetway_shaders_follow_night_level() -> String:
	for f in ["jetway", "jetway_standin", "jetway_link", "jetway_door_glow"]:
		var s := _src("res://world/%s.gdshader" % f)
		if not s.contains("global uniform float night_level;"):
			return "%s.gdshader does not read night_level" % f
	for f in ["jetway", "jetway_standin", "jetway_link"]:
		var s := _src("res://world/%s.gdshader" % f)
		if not s.contains("if (night_level > 0.0)") or not s.contains("EMISSION = e * night_level;"):
			return "%s.gdshader emission is not gated by night_level" % f
	return "" if _src("res://world/jetway_door_glow.gdshader").contains("if (night_level <= 0.0)") else "door glow draws by day"


## The window and spill maths: no emission at day level, rising with the night, underside lit most, windows periodic.
func test_jetway_night_emission_follows_the_level() -> String:
	var prev := -1.0
	for i in 11:
		var k := i / 10.0
		var e := JetwayNight.window_emission(k, 0.5)
		if e < prev - 1e-9:
			return "window emission falls as the night deepens"
		prev = e
	if JetwayNight.window_emission(0.0, 0.5) != 0.0 or JetwayNight.window_emission(-1.0, 0.5) != 0.0:
		return "window emission at daytime level"
	if JetwayNight.window_emission(1.0, 0.5) < 0.9:
		return "window not lit at night"
	if JetwayNight.window_emission(1.0, JetwayNight.WIN_PITCH * 0.8) > 0.01:
		return "no gap between windows"
	if absf(JetwayNight.window_x(0.4) - JetwayNight.window_x(0.4 + JetwayNight.WIN_PITCH * 3.0)) > 1e-4:
		return "windows are not periodic"
	if not (JetwayNight.spill(-1.0) > JetwayNight.spill(0.0) and JetwayNight.spill(0.0) > JetwayNight.spill(1.0) and JetwayNight.spill(1.0) > 0.0):
		return "spill order: underside > sides > roof > 0"
	return ""


## The model's meshes get the night material (tunnels with windows, others without), the glb's own material stays as meta for
## the stand-in's colour, the stand-in is a night-capable shader box, and the glow quad is no solid.
func test_jetway_materials() -> String:
	var model: Node = (load("res://world/models/vehicles/jetway.glb") as PackedScene).instantiate()
	JetwayNight.apply(model)
	var seen := 0
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m := mi.material_override as ShaderMaterial
		if m == null or m.shader != JetwayNight.SHADER or not mi.has_meta("jw_src"):
			model.free()
			return "%s has no night material" % mi.name
		if bool(m.get_shader_parameter("windows")) != (str(mi.name) in JetwayNight.WINDOW_TUNNELS):
			model.free()
			return "%s: windows flag" % mi.name
		seen += 1
	var hood := model.find_child("Hood", true, false) as Node3D
	JetwayNight.door_glow(hood)
	var glow := hood.find_child(JetwayNight.GLOW_NAME, false, false)
	var solid_free: bool = glow != null and glow.has_meta("no_solid")
	var colour := JetwayStandin._albedo(hood as MeshInstance3D)
	model.free()
	if seen < 10:
		return "only %d meshes got the night material" % seen
	if not solid_free:
		return "the door glow quad is missing or counts as a solid"
	if colour.get_luminance() < 0.2:
		return "stand-in colour lost with the material swap (%s)" % colour
	var box := JetwayStandin._material(Vector3(0.7, 0.7, 0.7))
	return "" if box is ShaderMaterial and box.shader.resource_path.ends_with("jetway_standin.gdshader") else "stand-in is not the night shader"


## The glow map lights only the cab windows and door lamp: a small share of the atlas, no light where the day skin is plain.
func test_jetway_glow_map_is_sparse() -> String:
	var img := JetwayNight.GLOW_TEX.get_image()
	if img.is_compressed():
		img.decompress()
	var lit := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).get_luminance() > 0.05:
				lit += 1
	var share := float(lit) / (img.get_width() * img.get_height())
	return "" if share > 0.002 and share < 0.05 else "glow map lights %.3f of the atlas" % share
