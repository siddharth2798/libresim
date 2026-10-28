extends Node
## Debug: a scripted A320 takeoff in the real flight scene, through the Props the controls write (levers
## TOGA, flaps 1+F, trim, steering by the rudder pedals, rotation to 12 deg by the side stick). Prints the
## roll distance, liftoff speed and the climb. Run:
##   godot --headless --path game res://tests/debug_a320_takeoff.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB
const KT := 0.514444
var f: Node
var t := 0.0
var _start := Vector3.ZERO
var _hdg := 0.0
var _lift_t := -1.0
var _next := 0.0
var _go := false
var _start_only := false


func _ready() -> void:
	_start_only = "--start" in OS.get_cmdline_user_args()
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _physics_process(dt: float) -> void:
	t += dt
	var fn: FdmNode = f.get_node("Fdm")
	if t < 3.0:
		return
	if _start_only:
		_engine_start(fn)
		return
	if not _go:
		_go = true
		for n in ["Controls", "JoystickControls"]:
			var c := f.get_node_or_null(n)
			if c:
				c.set_process(false)
				c.set_physics_process(false)
		_start = fn.position_enu()
		_hdg = Props.get_f("fdm/heading_rad")
		Props.set_v("controls/flaps", 2)
		Props.set_v("controls/pitch_trim", 0.15)
		Props.set_v("controls/parking_brake", false)
		Props.set_v("controls/brake_left", 0.0)
		Props.set_v("controls/brake_right", 0.0)
		print("TO start: engines running n1 %s, mass %.0f kg, hdg %.1f" % [fn.fdm.units.map(func(u): return snappedf(u.engine.n1, 0.1)), fn.fdm.mb.mass, rad_to_deg(_hdg)])
	var tt := t - 3.0
	var thr := minf(tt / 3.0, 1.0)  # 0 -> TOGA over 3 s
	Props.set_v("controls/throttle", thr)
	Props.set_v("controls/throttle_2", thr)
	var kias := Props.get_f("fdm/cas_mps") / KT
	var hdg := Props.get_f("fdm/heading_rad")
	var he := wrapf(hdg - _hdg, -PI, PI)
	var r: Vector3 = Props.get_v("fdm/body_rates", Vector3.ZERO)
	Props.set_v("controls/yaw", clampf(-2.0 * he - 1.0 * r.z, -0.3 if kias < 60.0 else -1.0, 0.3 if kias < 60.0 else 1.0))
	var pitch := rad_to_deg(Props.get_f("fdm/pitch_rad"))
	if kias > 142.0:
		Props.set_v("controls/pitch", clampf(0.30 + 0.12 * (12.0 - pitch) - 0.10 * rad_to_deg(r.y), -0.3, 0.8))
	var wow := Props.get_b("fdm/wow")
	if _lift_t < 0.0 and not wow and kias > 100.0:
		_lift_t = tt
		var d := (fn.position_enu() - _start).length()
		print("TO liftoff t %.1f s, roll %.0f m, %.0f kt, pitch %.1f" % [tt, d, kias, pitch])
	if tt >= _next:
		_next += 5.0
		print("TO t %5.1f kias %5.1f pitch %5.1f alt_agl %6.1f ft hdg_err %5.2f yaw %5.2f roll %5.1f dist %5.0f m n1 %s" % [tt, kias, pitch,
			Units.m_to_ft(Props.get_f("fdm/agl_m")), rad_to_deg(he), Props.get_f("controls/yaw"), rad_to_deg(Props.get_f("fdm/roll_rad")),
			(fn.position_enu() - _start).length(), fn.fdm.units.map(func(u): return snappedf(u.engine.n1, 0.1))])
	if tt > 60.0 or Props.get_b("damage/crashed"):
		print("TO end: crashed=%s gear_pos %.2f flaps %s" % [Props.get_b("damage/crashed"), fn.fdm.gear.gear_pos, str(Props.get_v("controls/flaps"))])
		get_tree().quit()


func _engine_start(fn: FdmNode) -> void:
	if t > 3.0 and t - 0.01 <= 3.0:
		Props.set_v("controls/engine_mode", 2)
		for i in 2:
			Props.set_v("controls/engine_master_%d" % (i + 1), true)
	if int(t * 10.0) % 50 == 0 and t - int(t) < 0.02:
		print("ST t %4.0f mode %s masters %s %s n1 %s n2 %s egt %s run %s" % [t, Props.get_v("controls/engine_mode"), Props.get_v("controls/engine_master_1"), Props.get_v("controls/engine_master_2"),
			fn.fdm.units.map(func(u): return snappedf(u.engine.n1, 0.01)), fn.fdm.units.map(func(u): return snappedf(u.engine.n2, 0.01)),
			fn.fdm.units.map(func(u): return snappedf(u.engine.get("egt") if u.engine.get("egt") != null else 0.0, 1.0)), fn.fdm.units.map(func(u): return u.engine.running)])
	if t > 70.0:
		get_tree().quit()
