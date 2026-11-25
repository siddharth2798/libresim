extends Node
## The aircraft's ground shadow (aircraft/common/ground_shadow.gd, tools/30_planform.py) and the sun's shadow splits per
## preset (core/graphics_settings.gd): every preset shows the aircraft's shadow, a real one or the decal.


func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func test_ground_shadow_pure_parts() -> String:
	if not _near(GroundShadow.ao_alpha(3.0, 3.0, 10.0), GroundShadow.AO_ALPHA) or GroundShadow.ao_alpha(14.0, 3.0, 10.0) != 0.0:
		return "contact darkening: full on the wheels, gone once 10 m up"
	var high_sun := Vector3(0.3, -0.9, 0.2).normalized()
	var low_sun := Vector3(0.99, -0.03, 0.0).normalized()
	if not _near(GroundShadow.cast_alpha(high_sun, 1.0, 3.0), GroundShadow.CAST_ALPHA) or GroundShadow.cast_alpha(low_sun, 1.0, 3.0) != 0.0:
		return "cast shadow: full with a high sun, none at the horizon"
	if GroundShadow.cast_alpha(high_sun, 0.0, 3.0) != 0.0 or GroundShadow.cast_alpha(high_sun, 1.0, 400.0) != 0.0:
		return "no cast shadow with the sun's shadow off (night, overcast) or 400 m up"
	var off := GroundShadow.cast_offset(Vector3(1.0, -1.0, 0.0).normalized(), 4.0)
	if not (_near(off.x, 4.0) and _near(off.y, 0.0)) or GroundShadow.cast_offset(Vector3(1, 0, 0), 4.0) != Vector2.ZERO:
		return "a 45 degree sun throws the shadow as far as the height: %s" % off
	if GroundShadow.real_reach(false, 1, 700.0, 0.12, 0.4) != 0.0 or not _near(GroundShadow.real_reach(true, 1, 700.0, 0.12, 0.4), 84.0) \
			or not _near(GroundShadow.real_reach(true, 2, 4000.0, 0.03, 0.4), 1600.0) or GroundShadow.real_reach(true, 0, 700.0, 0.12, 0.4) != 0.0:
		return "real shadow reach: off 0, two splits the first, four splits the third, one orthogonal map 0"
	if GroundShadow.fallback(30.0, 84.0) != 0.0 or GroundShadow.fallback(120.0, 84.0) != 1.0 or GroundShadow.fallback(5.0, 0.0) != 1.0:
		return "the decal steps in past the real shadow's reach"
	return ""


func test_ground_shadow_planforms() -> String:
	for id in ["c172", "a320"]:
		var def := AircraftDef.load_def(id)
		var m := def.json("planform")
		for k in ["x0", "x1", "y0", "y1", "z_mid", "z_low"]:
			if not m.has(k):
				return "%s planform.json lacks %s" % [id, k]
		var dir := def.path("planform").get_base_dir() + "/"
		for f in ["planform_cast.png", "planform_ao.png"]:
			if not ResourceLoader.exists(dir + f):
				return "%s: %s missing" % [id, f]
		if float(m.x1) - float(m.x0) < 5.0 or float(m.y1) - float(m.y0) < 5.0 or float(m.z_low) >= float(m.z_mid):
			return "%s planform rect looks wrong: %s" % [id, m]
	return ""


func test_ground_shadow_node() -> String:
	var prev = Session.setup.get("aircraft")
	Session.setup["aircraft"] = "a320"
	var model := AircraftModel.new()
	model.def = AircraftDef.load_def("a320")
	add_child(model)
	var g := GroundShadow.attach(model)
	var err := ""
	if g == null or g.ao == null or g.cast == null or g.ao.texture_albedo == null or g.cast.texture_albedo == null:
		err = "attach builds two textured decals"
	elif g.ao.cull_mask & LightLogic.AIRCRAFT_LAYER or g.cast.cull_mask & LightLogic.AIRCRAFT_LAYER:
		err = "the decals must not paint the aircraft itself"
	elif not _near(g.ao.size.x, float(g.meta.y1) - float(g.meta.y0)) or not _near(g.ao.size.z, float(g.meta.x1) - float(g.meta.x0)):
		err = "decal size = planform rect (x across = span, z along = length): %s" % g.ao.size
	model.free()
	if prev == null:
		Session.setup.erase("aircraft")
	else:
		Session.setup["aircraft"] = prev
	return err


func test_ground_shadow_presets_keep_the_aircraft() -> String:
	for q in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[q]
		if float(s.shadow) <= 0.0:
			continue  # no sun shadow: the decal does it
		var split1 := float(s.get("split1", Graphics.SPLIT1))
		if int(s.pssm) == 1 and float(s.shadow) * split1 < 60.0:
			return "%s: two splits whose first ends at %.0f m lose the aircraft's shadow past it" % [q, float(s.shadow) * split1]
		if int(s.pssm) == 0:
			return "%s: one orthogonal map is too coarse for the aircraft's own shadow" % q
	return ""
