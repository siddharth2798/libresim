extends RefCounted
## Ground-vehicle close-ups for tests/debug_showcase.gd (merged into the scene list there): the C172 at its
## default VABB stand (a jetbridge gate, service vehicles around the gates); each scene frames
## the nearest vehicle of one kind ("frame_vehicle": cam / aim in that vehicle's frame, forward / right / up).
##   godot --path game res://tests/debug_showcase.tscn -- --scene=gse_gpu --quality=ultra

const GATE := {"airport": "VABB", "start": "stand", "time_h": 10.5, "visibility_m": 20000.0}
const NIGHT := {"airport": "VABB", "start": "stand", "time_h": 20.5, "visibility_m": 20000.0}
const FRONT := [{"cam": [9.0, 6.5, 2.4], "aim": [0.0, 0.0, 1.0], "fov": 42.0}, {"cam": [-8.0, -6.5, 2.8], "aim": [0.0, 0.0, 1.0], "fov": 42.0}]
const BIG := [{"cam": [15.0, 11.0, 3.5], "aim": [0.0, 0.0, 1.5], "fov": 45.0}, {"cam": [-14.0, -10.0, 4.0], "aim": [0.0, 0.0, 1.5], "fov": 45.0}]

const SCENES := {
	"gse_gpu": {"frame_vehicle": "gpu", "variants": FRONT, "airport": "VOCI"},
	"gse_baggage": {"frame_vehicle": "baggage_tug", "variants": FRONT},
	"gse_cart": {"frame_vehicle": "baggage_cart", "variants": FRONT},
	"gse_hydrant": {"frame_vehicle": "hydrant_dispenser", "variants": BIG},
	"gse_fuel": {"frame_vehicle": "fuel_truck", "variants": BIG},
	"gse_bus": {"frame_vehicle": "apron_bus", "variants": BIG},
	"gse_fire": {"frame_vehicle": "fire_truck", "variants": BIG},
	"gse_night": {"frame_vehicle": "baggage_tug", "weather": "Clear", "night": true, "variants": [
		{"cam": [12.0, 9.0, 3.0], "aim": [0.0, 0.0, 1.0], "fov": 50.0}, {"cam": [-4.0, 30.0, 12.0], "aim": [-4.0, 0.0, 1.0], "fov": 55.0}]},
}


## The ramp crew around the aircraft on its stand (world/ramp_crew.gd): top-down and 3/4 views, per aircraft and airport.
##   ramp_<aircraft>_<icao>[_remote]: the aircraft's default stand ("_remote": a remote stand, fuel truck and bus)
const RAMP := {"a320": {"VABB": "", "VOCI": "", "VAPO": "", "VOCI_remote": "R2"}, "c172": {"VABB": "", "VOCI": "", "VAPO": "", "VABB_remote": "Bay 40"}}
const RAMP_VIEWS := {"a320": [{"cam": [-1.0, 0.0, 95.0], "aim": [0.0, 0.0, 0.0], "fov": 50.0}, {"cam": [34.0, 30.0, 16.0], "aim": [0.0, 0.0, 1.5], "fov": 55.0}],
	"c172": [{"cam": [-0.5, 0.0, 34.0], "aim": [0.0, 0.0, 0.0], "fov": 50.0}, {"cam": [12.0, 10.0, 6.0], "aim": [0.0, 0.0, 1.0], "fov": 55.0}]}


## Night apron lighting: a wide view over the neighbouring stands, a GA apron (pole lights), the aprons from the air.
const NIGHT_WIDE := {"a320": {"cam": [-70.0, 45.0, 28.0], "aim": [0.0, 0.0, 2.0], "fov": 60.0},
	"c172": {"cam": [-40.0, 25.0, 16.0], "aim": [0.0, 0.0, 1.0], "fov": 60.0}}
const APRON_NIGHT := {
	# the apron from a parked C172 at a remote VABB stand: chase camera and cockpit
	"apron_night_chase": {"setup": {"airport": "VABB", "start": "stand", "stand": "Bay 40", "time_h": 21.0, "visibility_m": 20000.0},
		"agl": true, "variants": [{"cam": [-14.0, 3.0, 4.0], "aim": [30.0, 0.0, 1.0], "fov": 60.0}, {"cam": [-14.0, 3.0, 4.0], "aim": [10.0, 40.0, 1.0], "fov": 60.0}]},
	"apron_night_cockpit": {"view": "cockpit", "setup": {"airport": "VABB", "start": "stand", "stand": "Bay 40", "time_h": 21.0, "visibility_m": 20000.0},
		"variants": [{"look": [0.0, -3.0], "fov": 60.0}, {"look": [-60.0, -3.0], "fov": 60.0}]},
	# the stand number board ahead of a contact stand, from the aircraft (day) and at night
	"stand_board_vabb": {"setup": {"airport": "VABB", "start": "stand", "stand": "Bay V15", "time_h": 11.0, "visibility_m": 20000.0},
		"agl": true, "variants": [{"cam": [-10.0, 2.0, 3.0], "aim": [35.0, 0.0, 5.0], "fov": 50.0}, {"cam": [20.0, 18.0, 4.0], "aim": [35.0, 0.0, 5.0], "fov": 50.0}]},
	"stand_board_vabb_night": {"setup": {"airport": "VABB", "start": "stand", "stand": "Bay V15", "time_h": 21.0, "visibility_m": 20000.0},
		"agl": true, "variants": [{"cam": [-10.0, 2.0, 3.0], "aim": [35.0, 0.0, 5.0], "fov": 50.0}]},
	"ga_apron_night": {"setup": {"airport": "VAJJ", "start": "stand", "time_h": 21.0, "visibility_m": 30000.0}, "agl": true,
		"variants": [{"cam": [-30.0, 18.0, 12.0], "aim": [0.0, 0.0, 1.0], "fov": 60.0}, {"cam": [10.0, -8.0, 2.5], "aim": [0.0, 0.0, 1.2], "fov": 55.0}]},
	"apron_approach_night": {"setup": {"airport": "VABB", "runway": "27", "start": "air", "air_ft": 900.0, "air_nm": 2.4, "air_kt": 80.0,
		"time_h": 21.0, "visibility_m": 30000.0}, "fly": {"secs": 1.0, "pitch": 0.0, "throttle": 0.5},
		"variants": [{"cam": [-25.0, 0.0, 8.0], "aim": [600.0, 0.0, -60.0], "fov": 60.0}, {"cam": [-25.0, 0.0, 8.0], "aim": [600.0, -300.0, -80.0], "fov": 60.0}]},
	"apron_approach_vapo_night": {"setup": {"airport": "VAPO", "runway": "10", "start": "air", "air_ft": 1000.0, "air_nm": 2.6, "air_kt": 80.0,
		"time_h": 21.0, "visibility_m": 30000.0}, "fly": {"secs": 1.0, "pitch": 0.0, "throttle": 0.5},
		"variants": [{"cam": [-25.0, 0.0, 8.0], "aim": [600.0, 0.0, -60.0], "fov": 60.0}, {"cam": [-25.0, 0.0, 8.0], "aim": [600.0, 300.0, -80.0], "fov": 60.0}]},
}


static func ramp_scenes() -> Dictionary:
	var out := {}
	for ac in RAMP:
		for k in RAMP[ac]:
			var apt: String = k.split("_")[0]
			var setup := {"aircraft": ac, "airport": apt, "start": "stand", "time_h": 11.0, "visibility_m": 30000.0}
			if RAMP[ac][k] != "":
				setup.stand = RAMP[ac][k]
			out["ramp_%s_%s" % [ac, k.to_lower()]] = {"weather": "Fair", "view": "chase", "agl": true, "setup": setup, "variants": RAMP_VIEWS[ac]}
			var night := setup.duplicate()  # the same at 21:00: apron floodlights (world/apron_floodlights.gd)
			night.time_h = 21.0
			out["ramp_%s_%s_night" % [ac, k.to_lower()]] = {"weather": "Clear", "view": "chase", "agl": true, "setup": night,
				"variants": RAMP_VIEWS[ac] + [NIGHT_WIDE[ac]]}
	return out


static func scenes() -> Dictionary:
	var out := ramp_scenes()
	for k in APRON_NIGHT:
		var d: Dictionary = APRON_NIGHT[k].duplicate(true)
		d.weather = "Clear"
		d.view = d.get("view", "chase")
		out[k] = d
	for k in SCENES:
		var d: Dictionary = SCENES[k].duplicate(true)
		d.setup = (NIGHT if d.get("night", false) else GATE).duplicate()
		if d.has("airport"):
			d.setup.airport = d.airport
			d.erase("airport")
		d.erase("night")
		if not d.has("weather"):
			d.weather = "Fair"
		d.view = "chase"
		d.agl = true
		out[k] = d
	return out
