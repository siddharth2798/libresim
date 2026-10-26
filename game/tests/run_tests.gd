extends Node
## Headless test runner (a scene, so autoloads such as Props exist):
##   godot --headless --path game res://tests/run_tests.tscn [-- --only=<prefix>] [--leaks]
## --leaks lists the tests that leave orphan nodes or objects behind (they show up as "resources
## still in use at exit" and fail the e2e sweep's "no script errors" check).
## Each test_* method returns "" on success or a failure message.
## Test suites: tests/test_core.gd (M2), tests/test_fdm_cards.gd (M3 POH test cards).

const SUITES := ["res://tests/test_core.gd", "res://tests/test_fdm_cards.gd", "res://tests/test_flight.gd", "res://tests/test_instruments.gd", "res://tests/test_systems.gd", "res://tests/test_landing.gd", "res://tests/test_nav.gd", "res://tests/test_failures.gd", "res://tests/test_input.gd", "res://tests/test_input_captain_pack.gd", "res://tests/test_weight_balance.gd", "res://tests/test_situation.gd", "res://tests/test_replay.gd", "res://tests/test_terrain_regions.gd", "res://tests/test_airport_lights.gd", "res://tests/test_weather_visuals.gd", "res://tests/test_aircraft_lights.gd", "res://tests/test_touchdown_fx.gd", "res://tests/test_callouts.gd", "res://tests/test_training.gd", "res://tests/test_menu.gd", "res://tests/test_atc.gd", "res://tests/test_atc_flow.gd", "res://tests/test_atc_rules.gd", "res://tests/test_atc_session.gd", "res://tests/test_atc_assist.gd", "res://tests/test_atc_radio_ui.gd", "res://tests/test_obstacles.gd", "res://tests/test_speech.gd", "res://tests/test_engine_start.gd", "res://tests/test_fdm_handsoff.gd", "res://tests/test_airport_ops_stands.gd", "res://tests/test_attribution.gd", "res://tests/test_apron_flat.gd", "res://tests/test_ui_scale.gd", "res://tests/test_graphics_presets.gd", "res://tests/test_approach_lights.gd"]


func _ready() -> void:
	var only := ""
	var leaks := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		leaks = leaks or a == "--leaks"
	var fails := 0
	var total := 0
	for path in SUITES:
		if not ResourceLoader.exists(path):
			continue
		var suite = load(path).new()
		if suite is Node:
			add_child(suite)
		for m in suite.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_") or not name.begins_with("test_" + only):
				continue
			total += 1
			var t := Time.get_ticks_msec()
			var orphans0 := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
			var objs0 := Performance.get_monitor(Performance.OBJECT_COUNT)
			var err: String = suite.call(name)
			var ms := Time.get_ticks_msec() - t
			if leaks:
				var dn := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) - orphans0
				var do := Performance.get_monitor(Performance.OBJECT_COUNT) - objs0
				if dn > 0.0 or do > 0.0:
					print("  LEAK  %s: +%d orphan nodes, +%d objects" % [name, dn, do])
			if err.is_empty():
				print("  PASS  %s  (%d ms)" % [name, ms])
			else:
				fails += 1
				print("  FAIL  %s: %s" % [name, err])
	print("%d/%d passed" % [total - fails, total])
	get_tree().quit(1 if fails > 0 else 0)
