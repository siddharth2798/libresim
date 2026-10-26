extends Node
## Quality presets (core/graphics_settings.gd): shadows are off on Low and cascade (PSSM 2 / 4 splits)
## further out with each step up; the sun in flight.tscn starts with four splits.


func test_shadow_presets_grow_with_quality() -> String:
	var last := -1.0
	var last_mode := -1
	for p in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[p]
		if not s.has("pssm") or int(s.pssm) < 0 or int(s.pssm) > 2:
			return "%s: pssm missing or not 0..2" % p
		if s.shadow < last or int(s.pssm) < last_mode:
			return "%s: shadow distance or cascade count went down" % p
		if (s.shadow > 0.0) != (p != "low"):
			return "%s: only Low should have no shadows" % p
		last = s.shadow
		last_mode = int(s.pssm)
	return "" if Graphics.PRESETS.ultra.shadow >= 3000.0 else "Ultra should cascade out to kilometres"


func test_flight_sun_uses_four_cascades() -> String:
	var flight: Node = load("res://world/flight.tscn").instantiate()
	var sun := flight.get_node("Sun") as DirectionalLight3D
	var ok := sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and sun.directional_shadow_blend_splits
	flight.free()
	return "" if ok else "the flight scene sun should start with 4 blended shadow splits"


func test_cloud_shadow_globals_follow_the_layer() -> String:
	var layer := CloudLayer.new()
	add_child(layer)
	var sun := Color(1.0, 0.95, 0.9)
	layer.update_layer(Vector3.ZERO, 1000.0, 0.5, Vector2(1234.0, 0.0), Vector3(0, 1, 0), sun, Color(0.5, 0.5, 0.5), 0.0)
	var on := layer.shadow
	layer.update_layer(Vector3.ZERO, 1000.0, 0.0, Vector2.ZERO, Vector3(0, 1, 0), sun, Color(0.5, 0.5, 0.5), 0.0)
	var clear := layer.shadow
	layer.update_layer(Vector3.ZERO, 1000.0, 0.8, Vector2.ZERO, Vector3(0, 1, 0), sun, Color(0.5, 0.5, 0.5), 0.6)
	var deck := layer.shadow
	layer.queue_free()
	if not is_equal_approx(on.x, 1000.0) or not is_equal_approx(on.y, 0.5) or on.z < 0.3:
		return "scattered cloud in sunlight should cast shadows: %s" % on
	if clear.z != 0.0:
		return "a clear sky should cast none: %s" % clear
	return "" if deck.z == 0.0 else "under a thick deck (no direct sun) there should be no patchy shadows: %s" % deck
