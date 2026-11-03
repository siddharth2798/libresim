extends RefCounted
## Fly-by camera scenes for tests/debug_showcase.gd (merged into the scene list there): the C172 and the A320 in
## cruise and on approach with the camera rig's own fly-by placement (ui/flyby_placement.gd). The flight starts in
## the fly-by view, flies "fly.secs" seconds (the camera stands where it was placed) and is then frozen, so
## flyby_<aircraft>_<phase>_a shows the aircraft coming in (1.5 s after placement) and _b close to the pass (4 s).
##   godot --path game res://tests/debug_showcase.tscn -- --scene=flyby_a320_approach_b --quality=ultra

const KT := {"air_custom": true, "air_kt_given": true, "time_h": 11.0, "visibility_m": 30000.0}
const PHASES := {
	"c172_cruise": {"setup": {"airport": "VAPO", "runway": "28", "start": "air", "air_ft": 2500.0, "air_nm": 8.0, "air_kt": 105.0},
		"fly": {"pitch": 2.0, "throttle": 0.8}},
	"c172_approach": {"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 700.0, "air_nm": 2.0, "air_kt": 75.0},
		"fly": {"pitch": -2.0, "throttle": 0.35, "flaps": 1}},
	"a320_cruise": {"setup": {"aircraft": "a320", "airport": "VAPO", "runway": "28", "start": "air", "air_ft": 6000.0, "air_nm": 15.0,
		"air_kt": 250.0}, "fly": {"pitch": 2.0, "throttle": 0.7}},
	"a320_approach": {"setup": {"aircraft": "a320", "airport": "VABB", "runway": "27", "start": "air", "air_ft": 1200.0, "air_nm": 4.0,
		"air_kt": 140.0}, "fly": {"pitch": 0.0, "throttle": 0.45, "flaps": 4}},
}
const MOMENTS := {"a": 1.5, "b": 4.0}


static func scenes() -> Dictionary:
	var out := {}
	for ph in PHASES:
		for m in MOMENTS:
			var d: Dictionary = PHASES[ph].duplicate(true)
			d.setup.merge(KT)
			d.fly.secs = MOMENTS[m]
			d.weather = "Fair"
			d.view = "flyby"
			d.prop_deg = 60.0
			out["flyby_%s_%s" % [ph, m]] = d
	return out
