extends Node
## Debug: an A320 flight in the real flight scene through the Props the controls write: takeoff with the levers at TOGA (A/THR arms
## by the levers), AP1 on, the levers back to CL (A/THR active), a climb, then the SPD/MACH button and a selected Mach held at
## altitude. One report line every 10 s (FCU windows, FMA, speeds, Mach). Muted, headless is fine:
##   godot --headless --audio-driver Dummy --path game res://tests/debug_athr_loop.tscn -- --aircraft=a320 --airport=VABB [--fast=4] [--mach=0.74] [--alt=26000]
const KT := 0.514444
var f: Node
var t := 0.0
var _step := 0
var _next := 0.0
var _mach := 0.74
var _alt := 26000.0  # level-off altitude, ft
var _hdg := 0.0
var _toga_arm := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fast="):
			Engine.time_scale = float(a.substr(7))
		elif a.begins_with("--mach="):
			_mach = float(a.substr(7))
		elif a.begins_with("--alt="):
			_alt = float(a.substr(6))
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _lever(v: float) -> void:
	for p in ["controls/throttle", "controls/throttle_1", "controls/throttle_2"]:
		Props.set_v(p, v)


func _fma() -> String:
	var s := ""
	for c in ["thrust", "vertical", "lateral", "misc"]:
		s += "[%s]" % str(Props.get_v("ap/fma/" + c, "")).replace("\n", "/")
	return s


func _line(what: String) -> void:
	var a := FcuWindows.spd()
	print("%-18s t %5.0f | SPD %s%s %s | FMA %s | A/THR armed %d active %d lamp %d | CAS %3.0f kt M %.3f alt %5.0f ft vs %5.0f lever %.2f cmd %.2f" % [what, t,
		a.text, "." if a.dot else "", a.label, _fma(), int(Props.get_b("ap/athr")), int(Props.get_b("ap/athr_active")),
		int(Props.get_b("controls/fcu/athr")), Props.get_f("fdm/cas_mps") / KT, Props.get_f("fdm/mach"),
		Units.m_to_ft(Props.get_f("fdm/alt_m")), Props.get_f("fdm/vs_mps") / Units.FPM, Props.get_f("controls/throttle_1"),
		Props.get_f("ap/cmd/lever_1")])


func _physics_process(dt: float) -> void:
	t += dt
	if t < 3.0:
		return
	var fn: FdmNode = f.get_node("Fdm")
	var kias := Props.get_f("fdm/cas_mps") / KT
	var agl := Units.m_to_ft(Props.get_f("fdm/agl_m"))
	var r: Vector3 = Props.get_v("fdm/body_rates", Vector3.ZERO)
	var pitch := rad_to_deg(Props.get_f("fdm/pitch_rad"))
	if _step == 0:  # takeoff set-up: hand the levers to this script
		for n in ["Controls", "JoystickControls"]:
			var c := f.get_node_or_null(n)
			if c:
				c.set_process(false)
				c.set_physics_process(false)
		_hdg = Props.get_f("fdm/heading_rad")
		Props.set_v("controls/flaps", 2)
		Props.set_v("controls/pitch_trim", 0.15)
		Props.set_v("controls/parking_brake", false)
		Props.set_v("controls/fcu/spd_kt", 250.0)
		Props.set_v("controls/fcu/alt_ft", 12000.0)
		_line("levers at idle")
		_lever(0.0)
		_step = 1
		_next = t + 1.0
	if _step >= 1 and _step <= 2:
		var he := wrapf(Props.get_f("fdm/heading_rad") - _hdg, -PI, PI)
		Props.set_v("controls/yaw", clampf(-2.0 * he - 1.0 * r.z, -0.3 if kias < 60.0 else -1.0, 0.3 if kias < 60.0 else 1.0))
		if kias > 142.0 and Props.get_b("fdm/wow") or (_step == 2 and agl < 400.0):
			Props.set_v("controls/pitch", clampf(0.30 + 0.12 * (12.0 - pitch) - 0.10 * rad_to_deg(r.y), -0.3, 0.8))
	if _step == 1 and t > _next:
		_lever(1.0)  # TOGA: A/THR arms by the levers, MAN TOGA
		_line("levers to TOGA")
		_step = 2
	elif _step == 2 and agl > 250.0:
		Props.set_v("controls/pitch", 0.0)
		Props.set_v("controls/fcu/ap1", true)
		_line("AP1 pressed")
		_step = 3
	elif _step == 3 and agl > 1650.0:
		_line("above 1500 ft")  # LVR CLB flashes
		_lever(AfThrust.CL)
		_step = 4
		_next = t + 3.0
	elif _step == 4 and t > _next:
		_line("levers at CL")
		Props.set_v("controls/flaps", 0)
		Props.set_v("controls/fcu/alt_ft", _alt)
		Props.set_v("controls/fcu/vert_select", "OPEN")  # pull ALT: open climb
		Props.set_v("controls/fcu/spd_kt", 290.0)
		_step = 5
	elif _step == 5 and Units.m_to_ft(Props.get_f("fdm/alt_m")) > _alt - 5000.0:
		_line("before SPD/MACH")
		Props.set_v("controls/fcu/spd_mach", true)  # the button: the window converts 290 kt to Mach here
		_step = 6
		_next = t + 1.0
	elif _step == 6 and t > _next:
		_line("after SPD/MACH")
		Props.set_v("controls/fcu/mach_sel", _mach)  # the knob turned to the Mach to hold
		_step = 7
	elif _step == 7 and Units.m_to_ft(Props.get_f("fdm/alt_m")) > _alt - 200.0:
		_line("level at altitude")
		_step = 8
		_next = t + 90.0
	elif _step == 8 and t > _next:
		_line("Mach hold 90 s later")
		Props.set_v("controls/fcu/spd_mach", false)
		_step = 9
		_next = t + 2.0
	elif _step == 9 and t > _next:
		_line("back to knots")
		get_tree().quit()
	if t >= _next and _step in [3, 5, 7]:
		_next = t + 10.0
		_line("climbing")
	if t > 1500.0 or Props.get_b("damage/crashed"):
		print("end: crashed=%s" % Props.get_b("damage/crashed"))
		get_tree().quit()
