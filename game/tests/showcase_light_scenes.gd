extends RefCounted
## Exterior-light close-ups for tests/debug_showcase.gd (merged into the scene list there): every aircraft at night
## on runway 27 at VABB (and one airborne, gear up) with every exterior light switched on, from the front, side,
## rear and below plus a few part close-ups. "props" debug/lights_steady keeps the strobes and beacons lit so a
## single frame shows them. Positions: cam / aim [forward, right, up] metres from the aircraft ("agl": heights
## above the ground). Used to check that each light sits on its housing (aircraft.json "lights").

const ALL_ON := {"nav": true, "beacon": true, "strobe": true, "landing": true, "taxi": true, "takeoff": true,
	"rwy_turnoff": true, "wing": true, "logo": true}
const GROUND := {"airport": "VABB", "runway": "27", "start": "runway", "time_h": 21.0, "visibility_m": 30000.0}
const AIR := {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 3500.0, "air_nm": 11.0, "time_h": 21.0,
	"visibility_m": 30000.0}
const STEADY := {"debug/lights_steady": true}
## Daylight copies (<scene>_day, 12:30 IST): no halos, only the glowing bulbs, to see each bulb on its housing.
const DAY := ["lights_a320_front", "lights_a320_nose", "lights_a320_tip", "lights_a320_tail", "lights_a320_wing",
	"lights_a320_under", "lights_a320_gearup_below", "lights_c172_front", "lights_c172_tip", "lights_c172_tail", "lights_c172_below"]

const SCENES := {
	# A320 on the runway (CG about 3.4 m above the ground)
	"lights_a320_front": {"ac": "a320", "cam": [44.0, -4.0, 3.2], "aim": [0.0, 0.0, 2.8], "fov": 50.0},
	"lights_a320_under": {"ac": "a320", "cam": [8.0, -3.5, 0.8], "aim": [-1.0, -4.4, 2.6], "fov": 60.0},
	"lights_a320_side": {"ac": "a320", "cam": [-2.0, -40.0, 5.0], "aim": [-1.0, 0.0, 3.0], "fov": 58.0},
	"lights_a320_rear": {"ac": "a320", "cam": [-48.0, 12.0, 7.0], "aim": [0.0, 0.0, 4.0], "fov": 50.0},
	"lights_a320_below": {"ac": "a320", "cam": [1.0, 7.0, 0.4], "aim": [0.0, 0.0, 2.6], "fov": 85.0},
	"lights_a320_nose": {"ac": "a320", "cam": [17.0, -4.5, 1.2], "aim": [11.2, 0.0, 1.3], "fov": 45.0},
	"lights_a320_tail": {"ac": "a320", "cam": [-30.0, -9.0, 7.0], "aim": [-19.0, 0.0, 6.0], "fov": 45.0},
	"lights_a320_wing": {"ac": "a320", "cam": [-14.0, -2.5, 6.5], "aim": [-1.0, -9.0, 3.0], "fov": 60.0},
	"lights_a320_tip": {"ac": "a320", "cam": [6.0, -21.0, 4.0], "aim": [-4.0, -16.5, 3.8], "fov": 40.0},
	"lights_a320_gearup": {"ac": "a320", "air": true, "cam": [30.0, -22.0, -8.0], "aim": [0.0, 0.0, -1.0], "fov": 50.0},
	"lights_a320_gearup_below": {"ac": "a320", "air": true, "cam": [8.0, 6.0, -14.0], "aim": [2.0, 0.0, 0.0], "fov": 70.0},
	# C172 on the runway (CG about 1.4 m above the ground)
	"lights_c172_front": {"ac": "c172", "cam": [8.0, -2.5, 1.6], "aim": [0.0, 0.0, 1.3], "fov": 55.0},
	"lights_c172_side": {"ac": "c172", "cam": [0.0, -13.0, 2.4], "aim": [-1.0, 0.0, 1.4], "fov": 55.0},
	"lights_c172_rear": {"ac": "c172", "cam": [-15.0, 4.0, 3.0], "aim": [-2.5, 0.0, 1.6], "fov": 50.0},
	"lights_c172_below": {"ac": "c172", "cam": [2.6, -2.2, 0.5], "aim": [0.0, -2.9, 1.6], "fov": 70.0},
	"lights_c172_tip": {"ac": "c172", "cam": [3.0, -7.5, 2.3], "aim": [0.0, -5.6, 2.0], "fov": 40.0},
	"lights_c172_tail": {"ac": "c172", "cam": [-9.0, 2.5, 2.4], "aim": [-5.8, 0.0, 1.8], "fov": 40.0},
	"lights_c172_air": {"ac": "c172", "air": true, "cam": [10.0, -8.0, -2.5], "aim": [0.0, 0.0, 0.0], "fov": 55.0},
}


## Full showcase scene definitions (debug_showcase.gd format) for the entries above.
static func scenes() -> Dictionary:
	var out := {}
	for k in SCENES:
		var e: Dictionary = SCENES[k]
		var s: Dictionary = (AIR if e.get("air", false) else GROUND).duplicate()
		s.aircraft = e.ac
		if e.get("air", false):
			s.air_kt = 205.0 if e.ac == "a320" else 100.0
		out[k] = {"weather": "Clear", "view": "chase", "setup": s, "lights": ALL_ON, "props": STEADY,
			"agl": not e.get("air", false), "cam": e.cam, "aim": e.aim, "fov": e.fov}
		if k in DAY:
			var d: Dictionary = out[k].duplicate(true)
			d.setup.time_h = 12.5
			out[k + "_day"] = d
	return out
