extends Node
## The A320 as a selectable aircraft (P9): aircraft.json sections, the FDM and model build from it, the
## start screen's aircraft page, controls, ATC profile, W&B in kg and % MAC, the model drives, the
## registration plan for both fuselage sides, and that the C172's entry and behaviour did not change.

const KT := 0.514444


func _def() -> AircraftDef:
	return AircraftDef.load_def("a320")


func test_a320_def_sections_present() -> String:
	var d := _def()
	if d.id != "a320" or d.display_name() != "A320-family twin-jet airliner":
		return "id / name: %s %s" % [d.id, d.display_name()]
	for s in ["model", "cockpit", "lights", "audio", "limits", "damage", "systems", "ground", "pushback", "payload",
			"cg_envelope", "controls", "replay", "atc", "registration", "cameras", "fcs", "failures", "start", "callouts"]:
		if d.section(s).is_empty():
			return "section %s missing" % s
	if "Airbus" not in str(d.data.description) or str(d.data.model_credit).find("Immersive") < 0:
		return "non-affiliation note / model credit"
	if d.engine_count() != 2 or d.engine_type() != "turbine" or AircraftSystems.profile_of(d) != "airliner":
		return "engines %d %s" % [d.engine_count(), d.engine_type()]
	if str(d.data.radio_type) != "A320" or d.section("fcs").get("law") != "airbus_fbw":
		return "radio_type / fcs"
	for f in ["config", "aero", "panel", "checklists", "exterior", "interior"]:
		if not d.has_file(f):
			return "file %s missing" % f
	return ""


func test_a320_fdm_builds_with_law() -> String:
	var f := FDM.new(_def())
	if f.units.size() != 2 or not f.fcs is AirlinerControls or f.fcs.law == null:
		return "fdm: units %d fcs %s law %s" % [f.units.size(), f.fcs, f.fcs.law]
	if f.gear.contacts.is_empty() or not f.engine is EngineTurbineFadec:
		return "gear / engine type"
	return ""


func test_a320_listed_and_c172_entry_unchanged() -> String:
	var ids := AircraftDef.list_ids()
	if "a320" not in ids or "c172" not in ids:
		return "list_ids %s" % [ids]
	var c := AircraftDef.load_def("c172")
	if c.display_name() != "Cessna 172S Skyhawk SP" or c.section("payload").has("fuel_unit") or c.section("payload").has("defaults"):
		return "c172 entry changed"
	if c.section("systems").has("profile") or c.section("fcs").size() != 0 or c.section("callouts").size() != 0:
		return "c172 gained airliner keys"
	if AircraftSystems.profile_of(c) != "ga" or AirlinerNodes.wanted(c) or not AirlinerNodes.wanted(_def()):
		return "profiles"
	return ""


func test_a320_controls_offered() -> String:
	var c := AircraftControls.for_def(_def())
	for g in ["thrust_levers", "reverse", "speedbrake", "gear", "autobrake", "engine_master", "engine_mode", "apu", "rudder_trim", "tiller", "fcu"]:
		if not c.has_group(g):
			return "group %s" % g
	if c.has_group("mixture") or c.has_group("magnetos") or c.levers.count != 2 or not c.levers.separate or not c.levers.reverse:
		return "piston groups offered / lever model"
	if c.levers.detents.size() != 6 or c.defaults.get("controls/gear") != 1:
		return "detents / defaults"
	return ""


func test_a320_atc_profile_airline() -> String:
	var a := _def().section("atc")
	if a.profile != "airline" or a.wake != "M" or a.callsign_style != "airline" or a.telephony != "Skyline":
		return "atc %s" % [a]
	return ""


func test_a320_wb_default_loading_inside_envelope() -> String:
	var d := _def()
	Session.apply_payload_defaults(d)
	var r := WeightBalance.compute(d.data, Session.setup)
	Session.apply_payload_defaults(AircraftDef.load_def("c172"))
	if r.is_empty():
		return "no W&B result"
	var t: Dictionary = r.takeoff
	var want: float = 43277.0 + 8500.0 + 10500.0 + 1500.0
	if absf(t.kg - want) > 5.0:
		return "weight %.0f kg, expected %.0f" % [t.kg, want]
	if not r.ok or t.over_max or t.cg_in < 17.0 or t.cg_in > 40.0:
		return "default loading flagged: %.0f kg CG %.1f %% MAC ok=%s" % [t.kg, t.cg_in, r.ok]
	var over := WeightBalance.compute(d.data, {"fuel_gal": 19400.0, "cabin_kg": 15000.0, "cargo_kg": 5000.0})
	if not over.takeoff.over_max:
		return "82 t not over MTOW"
	return ""


func test_a320_fuel_fill_order() -> String:
	var d := _def()
	var cfg := d.config()
	var low := WeightBalance.fuel_per_tank(d.data, cfg, 4000.0)
	var full := WeightBalance.fuel_per_tank(d.data, cfg, 19400.0)
	var sum := func(a): return a.reduce(func(x, y): return x + y, 0.0)
	if absf(sum.call(low) - 4000.0) > 1.0 or low[2] != 0.0 or low[5] != 0.0:
		return "4 t must sit in the wing tanks only: %s" % [low]
	if absf(sum.call(full) - 19400.0) > 5.0 or full[2] < 6000.0:
		return "full tanks: %s" % [full]
	var c := AircraftDef.load_def("c172")
	var gal := WeightBalance.fuel_per_tank(c.data, c.config(), 10.0)
	if absf(gal[0] - 27.2) > 0.01:
		return "c172 gal per tank path: %s" % [gal]
	return ""


func test_a320_aircraft_page_lists_both_with_kg_sliders() -> String:
	var was: String = Session.setup.aircraft
	Session.setup.aircraft = "a320"
	Session.apply_payload_defaults(_def())
	var page: Control = load("res://ui/menu/aircraft_page.gd").new()
	add_child(page)
	var err := ""
	var names: Array = []
	for id in page._chips:
		names.append(AircraftDef.load_def(id).display_name())
	if "A320-family twin-jet airliner" not in names or "Cessna 172S Skyhawk SP" not in names:
		err = "list %s" % [names]
	elif page._hero._title.text != "A320-family twin-jet airliner" or not page._sliders.has("cabin_kg") or page._sliders.fuel_gal.max_value != 19400.0:
		err = "A320 card / sliders: %s %s" % [page._hero._title.text, page._sliders.keys()]
	elif "Weight 63777 kg" not in page._weight.text or "% MAC" not in page._weight.text:
		err = "weight text: %s" % page._weight.text
	page.free()
	Session.setup.aircraft = was
	Session.apply_payload_defaults(AircraftDef.load_def(was))
	return err


func test_a320_model_drives() -> String:
	var f := FDM.new(_def())
	var w := {}
	var door := ModelDrives.angle("door_main_L", {"drive": "gear_pos", "map": [[0.0, 0.0], [0.1, -90.0], [0.9, -90.0], [1.0, 0.0]]}, f, w)
	f.fcs.gear_pos = 0.05
	var half := ModelDrives.angle("door_main_L", {"drive": "gear_pos", "map": [[0.0, 0.0], [0.1, -90.0], [0.9, -90.0], [1.0, 0.0]]}, f, w)
	if absf(door) > 1e-6 or absf(rad_to_deg(half) + 45.0) > 0.01:
		return "gear door map: %.2f %.2f" % [rad_to_deg(door), rad_to_deg(half)]
	f.fcs.spoiler = [0, 0, 30, 0, 0, 0, 0, 0, 40, 0]
	var l3 := ModelDrives.angle("spoiler_L3", {"drive": "spoiler_l3_deg"}, f, w)
	var r4 := ModelDrives.angle("spoiler_R4", {"drive": "spoiler_r4_deg"}, f, w)
	var l4 := ModelDrives.angle("spoiler_L4", {"drive": "spoiler_l4_deg"}, f, w)
	if absf(rad_to_deg(l3) - 30.0) > 0.01 or absf(rad_to_deg(r4) - 40.0) > 0.01 or l4 != 0.0:
		return "spoilers %.1f %.1f %.1f" % [rad_to_deg(l3), rad_to_deg(r4), rad_to_deg(l4)]
	f.fcs.slat_deg = 22.0
	if absf(rad_to_deg(ModelDrives.angle("slat_L1", {"drive": "slat_deg"}, f, w)) - 22.0) > 0.01:
		return "slat"
	f.gear.wow = true
	f.gear.compression.clear()
	return ""


func test_a320_model_builds_headless() -> String:
	var was: String = Session.setup.aircraft
	Session.setup.aircraft = "a320"  # the cockpit reads the panel of the current aircraft
	var n := FdmNode.new()
	n.fdm = FDM.new(_def())
	var m := AircraftModel.new()
	add_child(m)
	m.build(n)
	var err := ""
	var want: int = _def().section("model").surfaces.size()
	if m._pivots.size() != want or m._props.size() != 2:
		err = "pivots %d of %d, fans %d" % [m._pivots.size(), want, m._props.size()]
	elif m.cockpit == null or m.cockpit.interior == null or m.cockpit._quads.size() < 7:
		err = "cockpit quads %d" % (m.cockpit._quads.size() if m.cockpit else -1)
	elif not m._wheel_drives:
		err = "wheel drives"
	if err == "":
		m._animate_glb(n.fdm, 0.01)
	m.free()
	n.free()
	Session.setup.aircraft = was
	return err


## The parked aircraft sinks by the static spring deflection (0.30 m main / 0.13 m nose at 64 t); the leg pivots are
## raised by the contact compression, so the tyres rest on the ground (they used to sink 0.3 m into it).
func test_a320_tyres_rest_on_the_ground_when_parked() -> String:
	var was: String = Session.setup.aircraft
	Session.setup.aircraft = "a320"
	var n := FdmNode.new()
	n.fdm = FDM.new(_def())
	n.fdm.ground_height = func(_n: float, _e: float) -> float: return 0.0
	n.fdm.set_on_ground(0.0, 0.0, 0.0)
	for i in 360:
		n.fdm.step(1.0 / 120.0)
	var m := AircraftModel.new()
	add_child(m)
	m.build(n)
	m.transform = Transform3D(FdmNode.ned_to_render_basis(n.fdm.q), Vector3(0.0, -n.fdm.pos_d, 0.0))
	m._animate_glb(n.fdm, 0.01)
	var err := ""
	var comp: float = n.fdm.gear.compression.LEFT_MLG
	var worst := 0.0
	for w in ["MLGWheelsL", "MLGWheelsR", "NLGWheels"]:
		var mi := m.find_child(w, true, false) as MeshInstance3D
		var low := INF
		for si in mi.mesh.get_surface_count():
			for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				low = minf(low, (mi.global_transform * v).y)
		worst = maxf(worst, absf(low))
		print("    tyre %s bottom %+.3f m from the ground (main compression %.3f m)" % [w, low, comp])
	if comp < 0.2:
		err = "no static compression (%.3f)" % comp
	elif worst > 0.04:
		err = "a tyre is %.3f m off the ground" % worst
	m.free()
	n.free()
	Session.setup.aircraft = was
	return err


func test_a320_registration_plan_both_sides() -> String:
	var sec := _def().section("registration")
	var text := RegistrationPaint.text_for(sec)
	var p := RegistrationPaint.plan(sec, text)
	if text != "VT-ZZA" or p.size() != 2 or p[0].rotate != 0 or p[1].rotate != 180 or p[0].erase == p[1].erase:
		return "plan %s" % [p]
	var c := RegistrationPaint.plan(AircraftDef.load_def("c172").section("registration"), "VT-ABC")
	if c.size() != 2 or c[0].rotate != 0 or c[1].rotate != 0:
		return "c172 plan"
	return ""


func test_a320_limits_damage_ground() -> String:
	var d := _def()
	var l := d.section("limits")
	if l.vne_kias != 350.0 or l.g_pos != 2.5 or l.g_neg != -1.0 or l.vr_kias != 140.0 or l.vfe_kias[-1][1] != 177.0:
		return "limits"
	var g := GroundParams.ground(d)
	if g.stand_class != "gate" or g.min_runway_m != 1800.0 or g.cg_to_door_m <= 0.0 or g.tug_scale != 1.8:
		return "ground %s" % [g]
	if not d.section("damage").prop_hubs_m.is_empty() or GroundParams.pushback(d).radius_m != 30.0:
		return "damage / pushback"
	return ""


func test_a320_callouts_airliner_inputs() -> String:
	var s := CalloutLogic.new_state()
	var inp := {"ias": 0.0, "agl": 0.0, "vs": 0.0, "wow": true, "bank": 0.0, "throttle": 1.0, "alive_kt": 80.0, "v1_kt": 135.0, "rotate_kt": 140.0}
	var said := []
	for k in [60.0, 82.0, 120.0, 136.0, 141.0]:
		inp.ias = k
		for c in CalloutLogic.step(s, inp, 0.0):
			said.append(c[0])
	if said != ["Airspeed alive", "V one", "Rotate"]:
		return "takeoff calls %s" % [said]
	var h := {"ias": 140.0, "agl": 1100.0, "vs": -700.0, "wow": false, "bank": 0.0, "throttle": 0.3, "heights": [1000, 500, 100, 50, 40, 30, 20, 10]}
	var out := []
	for a in [1100.0, 990.0, 480.0, 95.0, 48.0, 39.0]:
		h.agl = a
		for c in CalloutLogic.step(s, h, 1.0):
			out.append(c[0])
	if out != ["One thousand", "Five hundred", "One hundred", "Fifty", "Forty"]:
		return "approach calls %s" % [out]
	return ""
