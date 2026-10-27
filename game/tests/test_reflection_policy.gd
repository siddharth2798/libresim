extends Node
## The aircraft's ReflectionProbe (aircraft/c172/reflection_policy.gd, reflection_rig.gd): which
## presets use it, when its cubemap is captured again, what it draws.

const ENU := Vector3(1000.0, 2000.0, 300.0)


func _snap(sun := 30.0, enu := ENU, alt := 300.0, cover := 0.3, precip := 0.0, vis := 20000.0, base := 4500.0) -> Dictionary:
	return ReflectionPolicy.snapshot(sun, enu, alt, cover, precip, vis, base)


func test_probe_presets() -> String:
	if ReflectionPolicy.PRESETS.keys() != Graphics.ORDER:
		return "the probe presets should be exactly the graphics presets"
	if ReflectionPolicy.for_preset("low").on:
		return "Low should not run the probe"
	var far := 0.0
	var gap := 1e9
	for p in ["medium", "high", "ultra"]:
		var c := ReflectionPolicy.for_preset(p)
		if not c.on or c.far_m < far or c.gap_s > gap or c.gap_s < ReflectionPolicy.MIN_GAP_S:
			return "%s: must be on, see further and refresh faster than the one below" % p
		far = c.far_m
		gap = c.gap_s
	return "" if ReflectionPolicy.for_preset("nonsense") == ReflectionPolicy.for_preset("high") else "an unknown preset should act like High"


func test_first_capture_is_immediate() -> String:
	return "" if ReflectionPolicy.needs_refresh({}, _snap(), 0.0, 10.0) else "an empty last capture must refresh"


func test_nothing_changed_waits_for_the_periodic_refresh() -> String:
	var a := _snap()
	if ReflectionPolicy.needs_refresh(a, _snap(30.5, ENU + Vector3(100, 0, 0)), 8.0, 12.0):
		return "small drift refreshed too early"
	if not ReflectionPolicy.needs_refresh(a, a, 12.0, 12.0):
		return "the periodic refresh did not fire"
	return "" if not ReflectionPolicy.needs_refresh(a, a, 3600.0, 0.0) else "gap 0 means never periodic"


func test_changes_trigger_refresh() -> String:
	var a := _snap()
	var cases := {
		"sun +2.5 deg": _snap(32.5), "sun -2.5 deg": _snap(27.5),
		"moved 350 m": _snap(30.0, ENU + Vector3(250, 250, 0)),
		"climbed 200 m": _snap(30.0, ENU, 500.0),
		"cloud cover": _snap(30.0, ENU, 300.0, 0.6), "rain": _snap(30.0, ENU, 300.0, 0.3, 0.5),
		"visibility": _snap(30.0, ENU, 300.0, 0.3, 0.0, 8000.0), "cloud base": _snap(30.0, ENU, 300.0, 0.3, 0.0, 20000.0, 2500.0),
	}
	for k in cases:
		if not ReflectionPolicy.needs_refresh(a, cases[k], 5.0, 0.0):
			return "%s should refresh" % k
	var ok := {"sun +1 deg": _snap(31.0), "moved 200 m": _snap(30.0, ENU + Vector3(200, 0, 0)),
		"climbed 100 m": _snap(30.0, ENU, 400.0), "cover 0.1": _snap(30.0, ENU, 300.0, 0.4)}
	for k in ok:
		if ReflectionPolicy.needs_refresh(a, ok[k], 5.0, 0.0):
			return "%s should not refresh" % k
	return ""


func test_second_capture_after_start() -> String:
	var a := _snap()
	if ReflectionPolicy.needs_refresh(a, a, ReflectionPolicy.WARM_S - 0.5, 0.0, 1):
		return "the warm-up capture came too early"
	if not ReflectionPolicy.needs_refresh(a, a, ReflectionPolicy.WARM_S + 0.1, 0.0, 1):
		return "no warm-up capture after the first one"
	return "" if not ReflectionPolicy.needs_refresh(a, a, ReflectionPolicy.WARM_S + 0.1, 0.0, 2) else "warm-up capture repeated"


func test_changes_are_throttled() -> String:
	var a := _snap()
	var far := _snap(60.0, ENU + Vector3(5000, 0, 0), 2000.0, 1.0, 1.0)
	if ReflectionPolicy.needs_refresh(a, far, ReflectionPolicy.MIN_GAP_S * 0.5, 5.0):
		return "a refresh came before the minimum gap"
	return "" if ReflectionPolicy.needs_refresh(a, far, ReflectionPolicy.MIN_GAP_S + 0.1, 5.0) else "no refresh after the gap"


func test_rig_hides_the_airframe_and_interior_from_the_capture() -> String:
	var model := Node3D.new()
	var hull := MeshInstance3D.new()
	hull.layers = LightLogic.AIRCRAFT_LAYER
	var inside := MeshInstance3D.new()
	model.add_child(hull)
	model.add_child(inside)
	add_child(model)
	var rig := ReflectionRig.attach(model)
	var probe := rig.find_children("*", "ReflectionProbe", false, false)[0] as ReflectionProbe
	var err := ""
	if inside.layers != ReflectionRig.HIDDEN_LAYER or hull.layers != LightLogic.AIRCRAFT_LAYER:
		err = "interior geometry should move to the hidden layer, the airframe stay"
	elif probe.cull_mask & (LightLogic.AIRCRAFT_LAYER | ReflectionRig.HIDDEN_LAYER) != 0 or probe.cull_mask & 1 == 0:
		err = "the probe must draw the world and neither the airframe nor the interior"
	elif probe.reflection_mask != LightLogic.AIRCRAFT_LAYER or probe.box_projection:
		err = "the probe should light only the airframe, without box projection"
	model.queue_free()
	return err


func test_rig_follows_the_preset() -> String:
	var model := Node3D.new()
	add_child(model)
	var rig := ReflectionRig.attach(model)
	var probe := rig.find_children("*", "ReflectionProbe", false, false)[0] as ReflectionProbe
	var err := ""
	for p in Graphics.ORDER:
		rig.apply_preset(p)
		var c := ReflectionPolicy.for_preset(p)
		if probe.visible != c.on or not is_equal_approx(probe.max_distance, c.far_m):
			err = "%s: probe not set from the preset" % p
	model.queue_free()
	return err
