extends RefCounted
## Graphics Phase 2 views for tests/debug_showcase.gd and tools/bench.sh (draw distances, jetway stand-ins, occlusion
## culling; docs/GRAPHICS-PLAN.md "Phase 2"). An A320 at its default VABB gate (the jetway docks), so the stand view also
## shows that a bridge at the player's aircraft is always drawn. Add --no-vis-ranges and / or --no-occlusion for "before".
##   hlod_stand        over the aircraft toward the terminal
##   hlod_taxi         5 m up on the apron 200 m behind and 70 m right of the gate, looking along the terminal frontage
##   hlod_approach     3 nm final to 27 at 1000 ft (occlusion off by the height rule), from just ahead of the nose toward the runway (45 deg view)
##   hlod_night        the stand view at 21:00 (lit windows, apron floods, lamp masts)
##   hlod_night_appr   the approach at 21:00 (distant terminal glow and apron lights)


static func scenes() -> Dictionary:
	var stand := {"aircraft": "a320", "airport": "VABB", "start": "stand", "time_h": 11.0, "visibility_m": 30000.0}
	var appr := {"aircraft": "a320", "airport": "VABB", "runway": "27", "start": "air", "air_ft": 1000.0, "air_nm": 3.0,
		"air_kt": 140.0, "time_h": 11.0, "visibility_m": 30000.0}
	var sharp := {"depth_of_field": false}  # the whole view in focus: popping and missing objects must show
	return {
		"hlod_stand": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": stand,
			"cam": [-70.0, -30.0, 14.0], "aim": [120.0, 0.0, 8.0], "fov": 60.0},
		"hlod_taxi": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": stand,
			"cam": [-200.0, 70.0, 5.0], "aim": [500.0, -60.0, 8.0], "fov": 60.0},
		"hlod_approach": {"weather": "Fair", "view": "chase", "options": sharp, "setup": appr,
			"cam": [22.0, 0.0, -3.0], "aim": [5560.0, 0.0, -305.0], "fov": 45.0},
		"hlod_night": {"weather": "Clear", "view": "chase", "options": sharp, "agl": true, "setup": stand.merged({"time_h": 21.0}, true),
			"cam": [-70.0, -30.0, 14.0], "aim": [120.0, 0.0, 8.0], "fov": 60.0},
		"hlod_night_appr": {"weather": "Clear", "view": "chase", "options": sharp, "setup": appr.merged({"time_h": 21.0}, true),
			"cam": [22.0, 0.0, -3.0], "aim": [5560.0, 0.0, -305.0], "fov": 45.0},
	}
