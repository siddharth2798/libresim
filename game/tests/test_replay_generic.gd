extends RefCounted
## Replay channels per aircraft (systems/replay_layout.gd, replay_channels.gd): the C172 layout is
## frozen, a twin records and resumes every engine and tank, FlightControls fields an aircraft adds
## (slats, spoilers, gear) and string props (FMA modes) replay.

const FX := preload("res://tests/generic_fixtures.gd")
const TICK := 1.0 / 120.0

## The C172 channel list as recorded before the data-driven layout (same order = same recordings).
const C172_KEYS := [
	"fdm/tas_mps", "fdm/cas_mps", "fdm/groundspeed_mps", "fdm/vs_mps", "fdm/alt_m", "fdm/agl_m", "fdm/alpha_rad",
	"fdm/beta_rad", "fdm/load_factor", "fdm/flap_deg", "fdm/mass_kg", "engine/rpm", "engine/map_pa",
	"engine/fuel_flow_kgs", "engine/egt_k", "engine/cht_k", "engine/oil_temp_k", "engine/oil_press_pa",
	"engine/power_w", "engine/thrust_n", "fuel/total_kg", "fuel/left_kg", "fuel/right_kg", "controls/pitch",
	"controls/roll", "controls/yaw", "controls/throttle", "controls/mixture", "controls/pitch_trim",
	"controls/brake_left", "controls/brake_right", "instruments/asi_kt", "instruments/altimeter_ft",
	"instruments/vsi_fpm", "instruments/ai/pitch_rad", "instruments/tc_rate", "instruments/tc_ball",
	"instruments/tach_rpm", "instruments/oil_temp_f", "instruments/oil_press_psi", "instruments/egt_f",
	"instruments/fuel_flow_gph", "instruments/fuel_left_gal", "instruments/fuel_right_gal",
	"instruments/suction_inhg", "instruments/ammeter_a", "instruments/altimeter/kollsman_inhg",
	"systems/vacuum/suction_inhg", "systems/electrical/battery_amps", "systems/electrical/bus_volts",
	"systems/pitot_static/pitot_pa", "systems/pitot_static/static_pa", "avionics/nav1/cdi", "avionics/nav1/gs",
	"avionics/nav1/dme_nm", "avionics/nav2/cdi", "avionics/nav2/gs", "avionics/gps/dist_nm", "avionics/gps/ete",
	"fdm/roll_rad", "fdm/pitch_rad", "fdm/heading_rad", "fdm/track_rad", "instruments/ai/roll_rad",
	"instruments/hi_deg", "instruments/compass_deg", "avionics/adf/bearing_deg", "avionics/gps/brg_mag",
	"fdm/wow", "fdm/stall_warning", "engine/running", "controls/starter", "controls/parking_brake",
	"controls/lights/beacon", "controls/lights/nav", "controls/lights/strobe", "controls/lights/taxi",
	"controls/lights/landing", "controls/electrical/master_bat", "controls/electrical/master_alt",
	"controls/electrical/avionics", "systems/electrical/powered", "systems/electrical/avionics_powered",
	"systems/electrical/gauges_powered", "systems/electrical/tc_powered", "systems/electrical/low_volts",
	"systems/electrical/flap_motor_running", "instruments/ai/flag", "instruments/tc_flag", "avionics/nav1/valid",
	"avionics/nav1/gs_valid", "avionics/nav2/valid", "avionics/nav2/gs_valid", "avionics/adf/valid",
	"controls/flaps", "controls/magnetos", "avionics/nav1/to_from", "avionics/nav2/to_from"]


## Props are a global tree and there is no erase: put it back after a test that writes new keys.
func _with_props(body: Callable) -> String:
	var saved: Dictionary = Props._p.duplicate()
	var err: String = body.call()
	Props._p = saved
	return err


func test_replay_c172_layout_frozen() -> String:
	var plain := ReplayChannels.new()
	var f := FDM.new(AircraftDef.load_def("c172"))
	var full := ReplayChannels.new(f.def, f)
	for ch in [plain, full]:
		if Array(ch.keys) != C172_KEYS:
			var i := 0
			while i < mini(ch.keys.size(), C172_KEYS.size()) and ch.keys[i] == C172_KEYS[i]:
				i += 1
			return "c172 channel list changed at #%d (%s, expected %s), %d keys" % [i, ch.keys[i] if i < ch.keys.size() else "end",
				C172_KEYS[i] if i < C172_KEYS.size() else "end", ch.keys.size()]
		if ch.n_state != 23 or ch.count() != 23 + C172_KEYS.size() or ch.enums.size() != 0:
			return "c172 layout: n_state %d, %d channels" % [ch.n_state, ch.count()]
	return ""


## A twin piston with a replay section; `extra` merges into it.
func _twin(extra := {}) -> FDM:
	var cfg := FX.twin_config()
	return FDM.new(AircraftDef.make("twin", {"name": "twin", "replay": extra}, "res://aircraft/c172", cfg))


func test_replay_twin_layout() -> String:
	var f := _twin()
	var ch := ReplayChannels.new(f.def, f)
	for k in ["engines/1/rpm", "engines/2/rpm", "engines/2/thrust_n", "engines/2/fuel_flow_kgs", "engines/2/egt_k",
			"engines/2/running", "controls/throttle_2", "controls/mixture_2", "controls/starter_2", "fuel/tank_kg#2"]:
		if not k in ch.keys:
			return "twin layout lacks " + k
	if "engines/3/rpm" in ch.keys:
		return "a twin has two engines"
	var g := _twin({"units": false})  # "units": false switches the expansion off
	var off := ReplayChannels.new(g.def, g)
	return "" if not "engines/1/rpm" in off.keys and "fuel/tank_kg#2" in off.keys else "units: false still expands engines"


func test_replay_twin_round_trip() -> String:
	return _with_props(_twin_round_trip)


func _twin_round_trip() -> String:
	var f := _twin()
	FX.fly_trimmed(f)
	f.units[0].engine.throttle = 0.7
	f.units[1].engine.throttle = 0.35
	f.mb.tanks[0].contents_kg = 11.0
	f.mb.tanks[1].contents_kg = 22.0
	f.mb.tanks[2].contents_kg = 33.0
	var node := FdmNode.new()
	node.fdm = f
	var r := Replay.new()
	r.setup(node)
	var truth := {}  # clock ms -> [rpm 1, rpm 2, tank contents, egt 2, throttle 2]
	for i in 600:  # 5 s; the engines change speed (throttle 2 up after 2 s)
		if i == 240:
			f.units[1].engine.throttle = 0.9
		for k in 2:
			Props.set_v("controls/throttle_%d" % (k + 1), f.units[k].engine.throttle)
			Props.set_v("controls/mixture_%d" % (k + 1), 1.0)
		FX.run(f, TICK)
		node._publish()
		r.record_tick(TICK)
		truth[int(roundf(r.clock * 1000.0))] = [f.units[0].thruster.rpm, f.units[1].thruster.rpm,
			f.mb.tanks.map(func(t): return t.contents_kg), f.units[1].engine.egt_k, f.units[1].engine.throttle]
	if not r.start_replay(3.0):
		return "start_replay refused"
	var key := int(roundf(r.t * 1000.0))
	if not truth.has(key):
		return "replay start %.3f s is not a recorded tick" % r.t
	var want: Array = truth[key]
	# playback: the per-engine props follow the recording although the FDM is held
	if absf(Props.get_f("engines/2/rpm") - want[1]) > 0.5 or absf(Props.get_f("engines/1/rpm") - want[0]) > 0.5:
		return "engines/n/rpm props not replayed: %.1f / %.1f, recorded %.1f / %.1f" % [Props.get_f("engines/1/rpm"), Props.get_f("engines/2/rpm"), want[0], want[1]]
	f.units[1].thruster.rpm = 0.0  # "live" state is thrown away by take_control
	f.units[1].engine.egt_k = 300.0
	for t in f.mb.tanks:
		t.contents_kg = 1.0
	r.take_control()
	print("    take control at %.2f s: rpm %.0f / %.0f (recorded %.0f / %.0f), tanks %s (recorded %s)" % [
		r.clock, f.units[0].thruster.rpm, f.units[1].thruster.rpm, want[0], want[1],
		f.mb.tanks.map(func(t): return snappedf(t.contents_kg, 0.001)), want[2].map(func(x): return snappedf(x, 0.001))])
	var err := ""
	if absf(f.units[1].thruster.rpm - want[1]) > 0.5 or absf(f.units[0].thruster.rpm - want[0]) > 0.5:
		err = "engine rpm not restored (%.1f / %.1f, recorded %.1f / %.1f)" % [f.units[0].thruster.rpm, f.units[1].thruster.rpm, want[0], want[1]]
	elif absf(f.units[1].engine.egt_k - want[3]) > 0.5:
		err = "engine 2 EGT %.1f, recorded %.1f" % [f.units[1].engine.egt_k, want[3]]
	elif absf(f.units[1].engine.throttle - want[4]) > 1e-4:
		err = "engine 2 throttle %.3f, recorded %.3f" % [f.units[1].engine.throttle, want[4]]
	for i in 3:
		if absf(f.mb.tanks[i].contents_kg - want[2][i]) > 1e-3:
			err = "tank %d: %.4f kg restored, recorded %.4f" % [i, f.mb.tanks[i].contents_kg, want[2][i]]
	node.free()
	r.free()
	return err


func test_replay_enum_channel() -> String:
	return _with_props(_enum_channel)


func _enum_channel() -> String:
	var modes := ["", "HDG", "NAV", "LOC"]
	var f := _twin({"enums": {"ap/fma/lateral": modes, "ap/fma/vertical": ["ALT", "V/S"]}, "lerp": ["ap/fcu/alt_m"],
		"bool": ["ap/engaged"], "int": ["ap/fcu/mode"], "deg": ["ap/fcu/hdg_deg"]})
	var ch := ReplayChannels.new(f.def, f)
	for k in ["ap/fma/lateral", "ap/fma/vertical", "ap/fcu/alt_m", "ap/engaged", "ap/fcu/mode", "ap/fcu/hdg_deg"]:
		if not k in ch.keys:
			return "section key %s not recorded" % k
	var b := ReplayBuffer.new(ch.kinds, 10.0, 20.0)
	var modes_seq := ["HDG", "NAV", "LOC"]
	for i in 3:
		Props.set_v("ap/fma/lateral", modes_seq[i])
		Props.set_v("ap/fma/vertical", "V/S")
		Props.set_v("ap/engaged", i >= 1)
		b.push(i * 0.05, 0.0, 0.0, 0.0, ch.capture(f))
	Props.set_v("ap/fma/lateral", "unknown mode")  # not in the table: not recorded (NaN), left alone
	var c := ch.capture(f)
	if not is_nan(c[ch.n_state + ch.keys.find("ap/fma/lateral")]):
		return "an unmapped string must not be recorded"
	Props.set_v("ap/fma/lateral", "")
	Props.set_v("ap/engaged", false)
	var fr := b.sample(0.05)  # exactly the second frame: NAV, engaged
	ch.apply_props(fr)
	var got := [Props.get_v("ap/fma/lateral"), Props.get_v("ap/fma/vertical"), Props.get_b("ap/engaged")]
	if got != ["NAV", "V/S", true]:
		return "enum replay %s, expected [NAV, V/S, true]" % [got]
	if ch.prop_value(b.sample(0.1).ch, "ap/fma/lateral") != "LOC":
		return "prop_value of an enum is its string"
	# step interpolation: between frames the earlier mode holds
	return "" if ch.prop_value(b.sample(0.025).ch, "ap/fma/lateral") == "HDG" else "enum not held between frames"


## An FDM whose FlightControls has the fields a jet adds (they come with the FDM phase).
func _jet_fcs_fdm() -> FDM:
	var f := _twin({"fcs": true})
	var s := GDScript.new()
	s.source_code = "extends FlightControls\nvar slat_deg := 0.0\nvar spoiler := [0.0, 0.0]\nvar gear_pos := 1.0\n"
	s.reload()
	f.fcs = s.new(f.cfg)
	return f


func test_replay_extra_fcs_fields() -> String:
	return _with_props(_extra_fcs_fields)


func _extra_fcs_fields() -> String:
	var f := _jet_fcs_fdm()
	var ch := ReplayChannels.new(f.def, f)
	var names := ch.fcs_extra.map(func(e): return "%s:%d" % e)
	if names != ["slat_deg:-1", "spoiler:0", "spoiler:1", "gear_pos:-1"]:
		return "extra state channels %s (speedbrake / thrust_lever do not exist and must be skipped)" % [names]
	if ch.n_state != 23 + 4:
		return "n_state %d" % ch.n_state
	f.fcs.slat_deg = 18.0
	f.fcs.spoiler = [10.0, 20.0]
	f.fcs.gear_pos = 0.5
	var b := ReplayBuffer.new(ch.kinds, 10.0, 20.0)
	b.push(0.0, 0.0, 0.0, 0.0, ch.capture(f))
	var live := ch.save_live(f)
	f.fcs.slat_deg = 0.0
	f.fcs.spoiler = [0.0, 0.0]
	f.fcs.gear_pos = 1.0
	var live2 := ch.save_live(f)
	ch.apply_state(b.sample(0.0), f)
	if f.fcs.slat_deg != 18.0 or f.fcs.spoiler != [10.0, 20.0] or f.fcs.gear_pos != 0.5:
		return "extra fcs fields not replayed: %s %s %s" % [f.fcs.slat_deg, f.fcs.spoiler, f.fcs.gear_pos]
	ch.restore_live(f, live2)
	if f.fcs.slat_deg != 0.0 or f.fcs.spoiler != [0.0, 0.0] or f.fcs.gear_pos != 1.0:
		return "restore_live lost the extra fcs fields"
	# the same aircraft without "fcs": true records nothing extra, whatever fields its fcs has
	var g := _jet_fcs_fdm()
	var plain := ReplayChannels.new(AircraftDef.make("x", {}, "res://aircraft/c172", g.cfg), g)
	return "" if plain.fcs_extra.is_empty() else "fcs fields recorded without the replay section asking for them"


func test_replay_saved_situation_has_extra_fields() -> String:
	var a := _jet_fcs_fdm()
	a.fcs.slat_deg = 22.0
	a.fcs.spoiler = [5.0, 7.5]
	a.fcs.gear_pos = 0.25
	var d: Dictionary = JSON.parse_string(JSON.stringify(Situation.capture_fdm(a), "", false, true))
	var b := _jet_fcs_fdm()
	Situation.apply_fdm(b, d)
	if b.fcs.slat_deg != 22.0 or b.fcs.spoiler != [5.0, 7.5] or b.fcs.gear_pos != 0.25:
		return "optional fcs fields not restored: %s %s %s" % [b.fcs.slat_deg, b.fcs.spoiler, b.fcs.gear_pos]
	var c172 := Situation.capture_fdm(FDM.new(AircraftDef.load_def("c172")))
	return "" if not c172.fcs.has("slat_deg") and not c172.fcs.has("spoiler") and not c172.gear.has("gear_pos") else "the C172 save gained optional keys"
