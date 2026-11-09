extends RefCounted
## Loader films (ui/loader_film.gd), one per aircraft and place: the Western Ghats, the Cochin
## approach and parked at a Kochi gate (jet bridge docked for the A320, ramp vehicles out). The three flying clips
## keep the aircraft flying while the camera drifts from cam to cam_end (debug_showcase.gd _follow); the gate clip
## is a slow orbit of the parked aircraft. cam / aim: [forward, right, up] m from the aircraft.
## Scene names are film_<aircraft>_<place> (README scenes such as a320_gate keep theirs); the clip folder drops the
## prefix. Shoot all eight: tools/shoot_loader_films.sh (writes game/ui/loader/<aircraft>_<place>/NNN.jpg).

const PLACES := ["ghats", "cochin", "gate"]


static func scenes() -> Dictionary:
	return {
		"film_a320_ghats": {"weather": "Fair", "view": "chase",
			"setup": {"aircraft": "a320", "airport": "VAAV", "start": "air", "air_ft": 6500.0, "air_nm": 14.0, "air_kt": 230.0, "time_h": 17.3, "visibility_m": 35000.0},
			"cam": [-60.0, -35.0, 16.0], "aim": [10.0, 0.0, 0.0], "cam_end": [-42.0, -48.0, 10.0], "aim_end": [15.0, 0.0, -1.0], "fov": 52.0},
		"film_c172_ghats": {"weather": "Fair", "view": "chase",
			"setup": {"airport": "VAAV", "start": "air", "air_ft": 2600.0, "air_nm": 5.0, "time_h": 17.3, "visibility_m": 30000.0},
			"cam": [-24.0, -12.0, 8.0], "aim": [6.0, 0.0, -1.0], "cam_end": [-14.0, -18.0, 4.0], "aim_end": [9.0, 0.0, -1.5], "fov": 58.0},
		"film_a320_cochin": {"weather": "Fair", "view": "chase",
			"setup": {"aircraft": "a320", "airport": "VOCI", "runway": "27", "start": "air", "air_ft": 1200.0, "air_nm": 4.0, "air_kt": 145.0, "time_h": 7.4, "visibility_m": 25000.0},
			"props": {"controls/gear": 1.0, "controls/flaps": 4},
			"cam": [34.0, -38.0, 5.0], "aim": [0.0, 0.0, 0.0], "cam_end": [50.0, -18.0, 2.0], "aim_end": [-5.0, 0.0, 0.0], "fov": 50.0},
		"film_c172_cochin": {"weather": "Fair", "view": "chase",
			"setup": {"airport": "VOCI", "runway": "27", "start": "air", "air_ft": 800.0, "air_nm": 3.0, "time_h": 7.4, "visibility_m": 25000.0},
			"cam": [10.0, -11.0, 2.0], "aim": [0.0, 0.0, 0.0], "cam_end": [15.0, -5.0, 1.0], "aim_end": [-1.5, 0.0, 0.0], "fov": 50.0},
		"film_a320_gate": {"weather": "Fair", "view": "chase", "agl": true,
			"setup": {"aircraft": "a320", "airport": "VOCI", "start": "stand", "stand": "B5", "cold": true, "time_h": 17.6, "visibility_m": 25000.0},
			"props": {"controls/parking_brake": true},  # a latching hardware switch (off) would release it: no ramp crew
			"cam": [6.0, -36.0, 15.0], "aim": [6.0, -4.0, 1.0], "fov": 58.0},
		"film_c172_gate": {"weather": "Fair", "view": "chase", "agl": true,
			"setup": {"airport": "VOCI", "start": "stand", "stand": "B5", "cold": true, "time_h": 17.6, "visibility_m": 25000.0},
			"props": {"controls/parking_brake": true},  # a latching hardware switch (off) would release it: no ramp crew
			"cam": [9.0, 8.0, 2.6], "aim": [0.0, -1.5, 1.0], "fov": 52.0},
	}
