extends RefCounted
## Jetway close-ups for tests/debug_showcase.gd (airport audit: rotunda / fixed link meets the terminal,
## wheels on the apron, cab at the door). An A320 parked at a gate (the jetway docks), or a C172 there (it
## rests). cam / aim: [forward, right, up] from the aircraft (A320: its CG, 11.3 m behind the gate point).

const A320 := {"aircraft": "a320", "start": "stand", "time_h": 11.0, "visibility_m": 30000.0}
const C172 := {"start": "stand", "time_h": 11.0, "visibility_m": 30000.0}


static func _at(base: Dictionary, airport: String, stand: String) -> Dictionary:
	var s := base.duplicate()
	s.airport = airport
	s.stand = stand
	return s


static func scenes() -> Dictionary:
	return {
		# VABB T2 pier: 64 m fixed link from the pier to a shared rotunda, two bridges to L1 / L2
		"jw_vabb_v4l": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VABB", "Bay V4L"),
			"cam": [-38.0, -42.0, 14.0], "aim": [12.0, -50.0, 4.0], "fov": 60.0,
			"variants": [{"cam": [40.0, 5.0, 9.0], "aim": [5.0, -30.0, 4.5], "fov": 60.0},
				{"cam": [-5.0, -10.0, 45.0], "aim": [12.0, -50.0, 0.0], "fov": 60.0}]},
		"jw_vabb_v4l_rest": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(C172, "VABB", "Bay V4L"),
			"cam": [-30.0, -40.0, 14.0], "aim": [5.0, -55.0, 4.0], "fov": 60.0},
		# VABB T1 (domestic): short bent bridges straight at the building
		"jw_vabb_a8": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VABB", "Bay A8"),
			"cam": [-40.0, -22.0, 10.0], "aim": [2.0, -30.0, 4.0], "fov": 60.0},
		"jw_vapo_3": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VAPO", "3"),
			"cam": [-15.0, -38.0, 10.0], "aim": [30.0, -15.0, 4.0], "fov": 60.0},
		"jw_voci_b5": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VOCI", "B5"),
			"cam": [-22.0, -40.0, 12.0], "aim": [28.0, -20.0, 4.0], "fov": 60.0},
		"jw_vokn_b1": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VOKN", "B1"),
			"cam": [-48.0, -30.0, 10.0], "aim": [-8.0, -15.0, 4.0], "fov": 60.0},
		"jw_voga_11": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VOGA", "11"),
			"cam": [-10.0, -42.0, 15.0], "aim": [40.0, 0.0, 4.0], "fov": 60.0},
		"jw_voml_7": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VOML", "7"),
			"cam": [-15.0, -35.0, 10.0], "aim": [20.0, -12.0, 4.0], "fov": 60.0},
		"jw_vocl_12a": {"weather": "Fair", "view": "chase", "agl": true, "setup": _at(A320, "VOCL", "12A"),
			"cam": [-10.0, -30.0, 12.0], "aim": [30.0, -45.0, 4.0], "fov": 60.0},
	}
