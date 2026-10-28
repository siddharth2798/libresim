class_name FdmAirlinerProps
extends RefCounted
## The Props side of the airliner parts of the FDM (FdmNode calls read() before every physics tick and
## publish() after it); everything is skipped for aircraft without these parts, so the C172's Props
## stay as they were.
## Reads:  controls/gear (1 down) controls/speedbrake controls/autobrake (0..3) controls/tiller
##   controls/engine_master_<n> controls/engine_mode (0 NORM, 1 CRANK, 2 IGN/START) controls/reverse_<n>
##   controls/flex_temp_c controls/lights/landing failures/engine_fire[_<n>] systems/hydraulics/antiskid
##   (absent = on)
## Publishes (turbofan engines, n = 1-based): engines/<n>/n1 n2 egt_k ff oil thrust_n running reverser
##   lever, (legacy engine/* stay engine 1's); fdm/slat_deg fdm/spoiler (per panel) fdm/spoiler_left_deg
##   fdm/spoiler_right_deg fdm/speedbrake fdm/gear_pos fdm/gear_state fdm/door_pos fdm/mach
##   fdm/stabilizer_deg fdm/flap_lever fdm/autobrake_on fdm/ground_speed_mps


static func read(f: FDM) -> void:
	var c := f.fcs
	if c is AirlinerControls:
		c.gear_cmd = 1 if Props.get_v("controls/gear", 1) else 0
		c.speedbrake_cmd = Props.get_f("controls/speedbrake")
		c.landing_light_l = 1.0 if Props.get_b("controls/lights/landing") else 0.0
		c.landing_light_r = c.landing_light_l
	var g := f.gear
	if g is RetractableGear:
		g.autobrake_mode = int(Props.get_v("controls/autobrake", 0))
		g.tiller = Props.get_f("controls/tiller")
		g.antiskid = Props.get_b("systems/hydraulics/antiskid", true)
	var mode: int = Props.get_v("controls/engine_mode", 0)
	for i in f.units.size():
		var e := f.units[i].engine
		if not e is EngineTurbineFadec:
			continue
		var n := i + 1
		e.master = Props.get_b("controls/engine_master_%d" % n)
		e.reverse = Props.get_f("controls/reverse_%d" % n)
		e.flex_temp_c = Props.get_f("controls/flex_temp_c")
		e.flap_lever = c.flap_cmd
		e.starter = (mode == 2 and e.master) or (mode == 1 and not e.master)
		var sfx := "" if i == 0 else "_%d" % n
		e.fire = Props.get_b("failures/engine_fire" + sfx)


static func publish(f: FDM) -> void:
	for i in f.units.size():
		var e := f.units[i].engine
		if not e is EngineTurbineFadec:
			continue
		var b := "engines/%d/" % (i + 1)
		Props.set_v(b + "n1", e.n1 * 100.0)
		Props.set_v(b + "n2", e.n2 * 100.0)
		Props.set_v(b + "ff", e.fuel_flow_kgs)
		Props.set_v(b + "oil", e.oil_press_pa)
		Props.set_v(b + "reverser", e.reverser_pos)
		Props.set_v(b + "lever", e.lever)
	var c := f.fcs
	if c is AirlinerControls:
		Props.set_v("fdm/mach", f.mach)
		Props.set_v("fdm/slat_deg", c.slat_deg)
		Props.set_v("fdm/spoiler", c.spoiler.duplicate())
		Props.set_v("fdm/spoiler_left_deg", c.aero_ctx().get("fcs/spoiler-left-deg", 0.0))
		Props.set_v("fdm/spoiler_right_deg", c.aero_ctx().get("fcs/spoiler-right-deg", 0.0))
		Props.set_v("fdm/speedbrake", c.speedbrake)
		Props.set_v("fdm/stabilizer_deg", c.stabilizer_deg)
		Props.set_v("fdm/flap_lever", c.flap_cmd)
	var g := f.gear
	if g is RetractableGear:
		Props.set_v("fdm/gear_pos", g.gear_pos)
		Props.set_v("fdm/gear_state", g.gear_state)
		Props.set_v("fdm/door_pos", g.door_pos)
		Props.set_v("fdm/autobrake_on", g.autobrake_on)
		Props.set_v("fdm/ground_speed_mps", g.ground_speed)


## After a trimmed airborne start: the engine levers the trim found, per engine.
static func after_trim(f: FDM) -> void:
	if not f.fcs is AirlinerControls:
		return
	for i in f.units.size():
		Props.set_v("controls/throttle_%d" % (i + 1), f.units[i].engine.throttle)
	Props.set_v("controls/pitch_trim", f.fcs.pitch_trim)
