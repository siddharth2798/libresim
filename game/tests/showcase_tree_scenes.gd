extends RefCounted
## Tree look checks (docs/GRAPHICS-PLAN.md G8; review_screenshots/trees/): close trees beside a runway, a Konkan coconut
## grove, the Western Ghats forest from 2000 ft and 8000 ft, a Mumbai suburb, a low sun and a night view; ground cover
## (undergrowth in the Ghats forest, a grass field beside a runway), a palm close-up and forest shadows at low sun. Depth
## of field is off so the trees themselves are judged. Run with --quality=low / high for the preset pairs.


static func scenes() -> Dictionary:
	var sharp := {"depth_of_field": false}
	var rwy := {"airport": "VOCI", "runway": "09", "start": "runway", "time_h": 10.5, "visibility_m": 30000.0}
	var coast := {"airport": "VOGO", "runway": "26", "start": "air", "air_ft": 350.0, "air_nm": 3.0, "time_h": 10.0,
		"visibility_m": 30000.0}
	var ghats := {"airport": "VAAV", "start": "air", "air_nm": 5.0, "time_h": 10.5, "visibility_m": 40000.0}
	var fly := {"secs": 2.0, "pitch": 0.0, "throttle": 0.6}
	return {
		"trees_runway": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": rwy,
			"variants": [{"cam": [1300.0, 205.0, 2.0], "aim": [1420.0, 300.0, 7.0], "fov": 60.0},
				{"cam": [1100.0, 120.0, 5.0], "aim": [1700.0, 260.0, 6.0], "fov": 60.0}]},
		"trees_palm_grove": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": coast, "fly": fly,
			"variants": [{"cam": [-20.0, -30.0, 35.0], "aim": [200.0, 200.0, 3.0], "fov": 62.0},
				{"cam": [60.0, 120.0, 14.0], "aim": [160.0, 220.0, 7.0], "fov": 60.0}]},
		"trees_ghats_2000": {"weather": "Fair", "view": "chase", "options": sharp, "fly": fly,
			"setup": ghats.merged({"air_ft": 2000.0}, true),
			"cam": [-30.0, -10.0, 8.0], "aim": [600.0, 0.0, -300.0], "fov": 62.0},
		"trees_ghats_8000": {"weather": "Clear", "view": "chase", "options": sharp, "fly": fly,
			"setup": ghats.merged({"air_ft": 8000.0, "air_nm": 10.0}, true),
			"cam": [-30.0, -10.0, 8.0], "aim": [2500.0, 0.0, -1200.0], "fov": 62.0},
		"trees_suburb": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "fly": fly,
			"setup": {"airport": "VAJJ", "runway": "26", "start": "air", "air_ft": 400.0, "air_nm": 1.0, "time_h": 11.0,
				"visibility_m": 30000.0},
			"cam": [-30.0, -10.0, 70.0], "aim": [400.0, 0.0, 0.0], "fov": 62.0},
		"trees_low_sun": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": coast.merged({"time_h": 18.15}, true),
			"fly": fly, "cam": [-20.0, -4.0, 25.0], "aim": [200.0, 0.0, 4.0], "fov": 62.0},
		"trees_undergrowth": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true,
			"setup": {"airport": "VAAV", "runway": "32", "start": "runway", "time_h": 10.5, "visibility_m": 30000.0},
			"cam": [1100.0, -195.0, 1.7], "aim": [1135.0, -212.0, 0.7], "fov": 65.0},
		"trees_grass_runway": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": rwy,
			"cam": [600.0, 42.0, 1.3], "aim": [690.0, 62.0, 0.2], "fov": 60.0},
		"trees_palm_closeup": {"weather": "Fair", "view": "chase", "options": sharp, "agl": true, "setup": coast, "fly": fly,
			"cam": [40.0, 100.0, 4.0], "aim": [110.0, 170.0, 10.0], "fov": 65.0},
		"trees_shadows_low_sun": {"weather": "Clear", "view": "chase", "options": sharp, "fly": fly,
			"setup": ghats.merged({"air_ft": 2000.0, "time_h": 17.6}, true),
			"cam": [-30.0, -10.0, 8.0], "aim": [500.0, 150.0, -320.0], "fov": 62.0},
		"trees_night": {"weather": "Clear", "view": "chase", "options": sharp, "agl": true, "setup": rwy.merged({"time_h": 21.0}, true),
			"cam": [1100.0, 120.0, 5.0], "aim": [1700.0, 260.0, 6.0], "fov": 60.0},
	}
