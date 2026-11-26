extends Node
## Debug: an A320 air start lined up on an ILS in the real flight scene; APPR, AP1 (+AP2) and A/THR through the FCU Props, then one
## report line per second (FMA, ILS deviations, altitude, sink rate, radio altitude, lateral offset) until the aircraft stops or
## leaves the runway. Muted, headless is fine:
##   godot --headless --audio-driver Dummy --path game res://tests/debug_autoland.tscn -- --aircraft=a320 --airport=VAPO --runway=28 \
##     --air --air-nm=8 [--ap2=0] [--fast=4] [--ils-kt=140] [--from=-1] [--wind=270,12] [--every=1]
## --from=<ft> is read as "start report lines below this radio altitude every 0.25 s" (default 300 ft).
const KT := 0.514444
var f: Node
var t := 0.0
var _step := 0
var _ap2 := true
var _kt := 140.0
var _every := 1.0
var _next := 0.0
var _fine_ft := 300.0
var _landed_t := -1.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fast="):
			Engine.time_scale = float(a.substr(7))
		elif a.begins_with("--ap2="):
			_ap2 = float(a.substr(6)) > 0.0
		elif a.begins_with("--ils-kt="):
			_kt = float(a.substr(9))
		elif a.begins_with("--every="):
			_every = float(a.substr(8))
		elif a.begins_with("--from="):
			_fine_ft = float(a.substr(7))
	Session.skip_menu = true
	Session.interactive_override = 0
	Session.save_path = "user://_debug_autoland_last_flight.json"
	TrainingLogic.save_path = "user://_debug_autoland_training.json"
	SituationStore.dir = "user://_debug_autoland_saves/"
	Session._parse_args(PackedStringArray(OS.get_cmdline_user_args()))
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _fma() -> String:
	var s := ""
	for c in ["thrust", "vertical", "lateral", "approach", "misc"]:
		s += "[%s]" % str(Props.get_v("ap/fma/" + c, "")).replace("\n", "/")
	return s


func _line(what: String) -> void:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	print("%-10s t %5.1f | %s | CAS %3.0f gs %3.0f alt %5.0f ft ra %5.1f ft vs %5.0f fpm pitch %5.1f | N2 gs %d loc %d | wow %d | xy %.0f %.0f" % [what, t,
		_fma(), Props.get_f("fdm/cas_mps") / KT, Props.get_f("fdm/groundspeed_mps") / KT, Units.m_to_ft(Props.get_f("fdm/alt_m")),
		Units.m_to_ft(Props.get_f("fdm/agl_m")), Props.get_f("fdm/vs_mps") / Units.FPM, rad_to_deg(Props.get_f("fdm/pitch_rad")),
		int(Props.get_b("avionics/nav2/gs_valid")), int(Props.get_b("avionics/nav2/valid")), int(Props.get_b("fdm/wow")), p.x, p.y])


func _physics_process(dt: float) -> void:
	t += dt
	if t < 4.0:
		return
	var ra := Units.m_to_ft(Props.get_f("fdm/agl_m"))
	if _step == 0:
		for n in ["Controls", "JoystickControls"]:
			var c := f.get_node_or_null(n)
			if c:
				c.set_process(false)
				c.set_physics_process(false)
		_line("start")
		print("NAV2 %.2f %s kind %s" % [Props.get_f("controls/nav2/freq_mhz"), Props.get_v("avionics/nav2/ident", ""), Props.get_v("avionics/nav2/kind", "")])
		Props.set_v("controls/flaps", 5)  # CONF FULL: the autoland needs CONF 3 or FULL
		Props.set_v("controls/fcu/spd_kt", _kt)
		Props.set_v("controls/fcu/appr", true)
		Props.set_v("controls/fcu/ap1", true)
		if _ap2:
			Props.set_v("controls/fcu/ap2", true)
		Props.set_v("controls/fcu/athr", true)
		_step = 1
	var every := 0.25 if ra < _fine_ft else _every
	if t >= _next:
		_next = t + every
		_line("")
	if Props.get_b("fdm/wow"):  # as a pilot would: autobrake, ground spoilers armed, reverse idle
		Props.set_v("controls/autobrake", 2)
		Props.set_v("controls/speedbrake", 1.0)
		Props.set_v("controls/reverse_1", 0.1)
		Props.set_v("controls/reverse_2", 0.1)
	if Props.get_b("fdm/wow") and _landed_t < 0.0:
		_landed_t = t
		_line("TOUCHDOWN")
	if (_landed_t > 0.0 and (t - _landed_t > 40.0 or Props.get_f("fdm/groundspeed_mps") < 3.0)) or t > 900.0 or Props.get_b("damage/crashed"):
		print("end: crashed=%s" % Props.get_b("damage/crashed"))
		get_tree().quit()
