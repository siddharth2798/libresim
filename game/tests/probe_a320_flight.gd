extends Node
## Probe: a whole A320 flight on the autopilot in the real flight scene: runway start, planned route (the start screen's Route step:
## RouteBuilder.auto into Session.setup.route, taken into the flight by RouteSetup.apply as the menu does), takeoff by hand, then AP1 +
## AP2, NAV along the route, managed climb, cruise, the FMS top of descent, managed descent, APPR, LOC and G/S capture on the ILS
## the FMGC auto-tunes, autoland, roll out and autobrake to a stop. The crew (probe_a320_flight_pilot.gd) never sets a speed,
## altitude or heading. Headless, never writes the player's files. About real time (a VABB - VAPO flight is 20 to 30 min of wall time).
##   godot --headless --audio-driver Dummy --fixed-fps 120 --path game res://tests/probe_a320_flight.tscn -- [options]
## Options: --from=VABB --rwy=27 --to=VAPO --arr=28 --kind=vor|airway|direct (vor) --cruise=FT (14000) --wind=DIR/KT (0/0)
##   --max=sim s (3000) --wall=real s (3600) --log=s between lines (20).
##   --final: only the approach (the A320's own air start on final at --to / --arr, AP1 + AP2 and APPR at once), about 4 min: the
##   short form for windowed runs on each graphics preset and renderer (--quality=low|high..., --rendering-method ...).
## Last line: FLIGHT RESULT PASS|FAIL reason=..; exit code 0 = PASS.

const Pilot := preload("res://tests/probe_a320_flight_pilot.gd")
const State := preload("res://tests/probe_a320_state.gd")

var f: Node
var args := {}
var st := State.new()
var pilot := Pilot.new()
var db: NavDatabase
var dest_pos := Vector2.ZERO
var t := 0.0
var _ended := false
var _ready_ok := false
var _log := 0.0
var _wall0 := 0
var _fma_last := ""
var _td := {}
var _max_cross := 0.0
var _words := []
var _disc0 := 0  # disconnects before the crew engaged the AP (an air start)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Session.skip_menu = true
	Session.interactive_override = 0
	Session.save_path = "user://_probe_a320_flight_last_flight.json"
	TrainingLogic.save_path = "user://_probe_a320_flight_training.json"
	SituationStore.dir = "user://_probe_a320_flight_saves/"
	var wind := str(args.get("wind", "0/0"))
	db = NavDatabase.new()
	if args.has("final"):  # only the approach: the A320's own "on final" air start at the arrival runway, no route
		Session._parse_args(PackedStringArray(["--aircraft=a320", "--airport=%s" % a_("to", "VAPO"), "--runway=%s" % a_("arr", "28"),
			"--air", "--weather=clear", "--wind=%s" % wind]))
		Session.setup.route = {}
		pilot.phase = "final"
		dest_pos = db.position_of(a_("to", "VAPO"))
		print("FLIGHT final at %s %s" % [a_("to", "VAPO"), a_("arr", "28")])
		_start_flight()
		return
	Session._parse_args(PackedStringArray(["--aircraft=a320", "--airport=%s" % a_("from", "VABB"), "--runway=%s" % a_("rwy", "27"),
		"--weather=clear", "--wind=%s" % wind]))
	var cruise := float(a_("cruise", "14000"))
	var r := RouteBuilder.auto(a_("kind", "vor"), a_("from", "VABB"), a_("to", "VAPO"), db, cruise)
	if not r.ok:
		print("FLIGHT RESULT FAIL reason=route %s" % r.error)
		get_tree().quit(1)
		_ended = true
		return
	Session.setup.route = RouteSetup.repair({"dest": a_("to", "VAPO"), "arr_rwy": a_("arr", "28"), "wps": r.wps, "cruise_ft": cruise,
		"kind": a_("kind", "vor"), "air_at": -1})
	dest_pos = db.position_of(a_("to", "VAPO"))
	print("FLIGHT route %s -> %s via %s, cruise %.0f ft" % [a_("from", "VABB"), a_("to", "VAPO"), RouteSetup.idents(Session.setup.route), cruise])
	_start_flight()


func _start_flight() -> void:
	_wall0 = Time.get_ticks_msec()
	Engine.max_fps = 0
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func a_(k: String, d: String) -> String:
	return str(args.get(k, d))


func _setup_flight() -> void:
	for n in ["Controls", "JoystickControls"]:
		var c := f.get_node_or_null(n)
		if c:
			c.set_process(false)
			c.set_physics_process(false)
			c.set_process_unhandled_input(false)
			c.set_process_unhandled_key_input(false)
	if not st.setup(f, a_("to", "VAPO"), a_("arr", "28")):
		_finish(false, "no arrival runway")
		return
	_ready_ok = true
	print("FLIGHT start: GPS %s then %s, FCU alt %.0f, managed hdg %s vs %s, CRZ FL %s" % [Props.get_v("controls/gps/target"),
		Props.get_v("controls/gps/route_next"), Props.get_f("controls/fcu/alt_ft"), Props.get_b("controls/fcu/hdg_managed"),
		Props.get_b("controls/fcu/vs_managed"), Props.get_v("mcdu/init/cruise_fl")])


func _physics_process(dt: float) -> void:
	if _ended or f == null or not f.is_node_ready():
		return
	if not _ready_ok:
		_setup_flight()
		if not _ready_ok:
			return
	t += dt
	if t < 2.0:
		pilot.rwy_hdg = Props.get_f("fdm/heading_rad")  # the runway heading the flight started on
		_disc0 = int(Props.get_v("ap/disconnect_count", 0))
		return
	var s := _read(t - 2.0)
	pilot.decide(s)
	_watch(s)
	if t >= _log:
		_log = t + (2.0 if s.ra < 500.0 and pilot.phase in ["approach", "rollout"] else float(args.get("log", 20.0)))
		print("FLIGHT fps %d" % Engine.get_frames_per_second())
		print("FLIGHT %7.1f %-8s ias %5.1f alt %6.0f ra %6.0f vs %6.0f hdg %5.1f bnk %5.1f gps %-8s %5.1f nm dest %5.1f fcu %5.0f/%s fms %s tod %5.1f | %s | ils %s cross %.0f along %.0f" % [
			s.t, pilot.phase, s.ias, s.alt_ft, s.ra, s.vs, s.hdg, s.bank, s.gps_id, s.gps_nm, s.dest_nm, s.fcu_alt, s.spd_tgt, s.fms_phase,
			Props.get_f("avionics/fms/tod_nm"), s.fma, s.ils_auto, s.cross, s.along])
	if s.crashed:
		_finish(false, "crashed")
	elif pilot.phase == "stopped":
		_finish(true, "")
	elif t > float(args.get("max", 3000.0)) or (Time.get_ticks_msec() - _wall0) / 1000.0 > float(args.get("wall", 3600.0)):
		_finish(false, "timeout in phase %s" % pilot.phase)
	elif pilot.phase in ["climb", "cruise", "descent", "approach"] and s.disc_count > _disc0:
		_finish(false, "autopilot disconnected in %s (FMA %s)" % [pilot.phase, s.fma])


func _read(tt: float) -> Dictionary:
	var s := st.read(tt)
	var p := st.fn.position_enu()
	s["alt_ft"] = AfInputs.indicated_alt_m() / 0.3048
	s["thr_fma"] = str(Props.get_v("ap/fma/thrust", ""))
	s["vert_fma"] = str(Props.get_v("ap/fma/vertical", ""))
	s["lat_fma"] = str(Props.get_v("ap/fma/lateral", ""))
	s["fma"] = "%s / %s / %s / %s / %s" % [s.thr_fma.replace("\n", " "), s.vert_fma.replace("\n", " "), s.lat_fma.replace("\n", " "),
		str(Props.get_v("ap/fma/approach", "")).replace("\n", " "), str(Props.get_v("ap/fma/misc", "")).replace("\n", " ")]
	s["fms_phase"] = str(Props.get_v("avionics/fms/phase", ""))
	s["fcu_alt"] = Props.get_f("controls/fcu/alt_ft")
	s["spd_tgt_kt"] = Props.get_f("ap/spd_target_kt")
	s["spd_tgt"] = "%.0f" % s.spd_tgt_kt
	s["dest_nm"] = Vector2(p.x, p.y).distance_to(dest_pos) / 1852.0
	s["gps_id"] = str(Props.get_v("avionics/gps/ident", ""))
	s["gps_nm"] = Props.get_f("avionics/gps/dist_nm")
	s["ils_auto"] = "%s %.2f %s" % [Props.get_v("avionics/ils_auto/ident", ""), Props.get_f("controls/nav2/freq_mhz"),
		"valid" if Props.get_b("avionics/nav2/valid") else "-"]
	s["disc_count"] = int(Props.get_v("ap/disconnect_count", 0))
	return s


## FMA changes, the touchdown and the worst offset of the roll out.
func _watch(s: Dictionary) -> void:
	if s.fma != _fma_last:
		_fma_last = s.fma
		pilot.say(s.t, "FMA %s  (%.0f ft, %.0f kt, RA %.0f, pitch %.1f)" % [s.fma, s.alt_ft, s.ias, s.ra, s.pitch])
		for col in [s.thr_fma, s.vert_fma, s.lat_fma]:
			for w in str(col).split("\n", false):
				if not w in _words:
					_words.append(w)
	if s.wow and _td.is_empty() and pilot.phase in ["approach", "rollout"]:
		_td = {"along": s.along, "cross": s.cross, "vs": s.vs, "ias": s.ias, "pitch": s.pitch}
	if not _td.is_empty():
		_max_cross = maxf(_max_cross, absf(s.cross))


func _finish(ok: bool, why: String) -> void:
	_ended = true
	var reason := why
	if ok:
		reason = _check()
		ok = reason == ""
	print("FLIGHT modes seen: %s" % [_words])
	if not _td.is_empty():
		print("FLIGHT touchdown %.0f m past the threshold, %.1f m off the axis, %.0f fpm, %.0f kt, pitch %.1f; roll out worst %.1f m; stopped %.0f m past the threshold" % [
			_td.along, _td.cross, _td.vs, _td.ias, _td.pitch, _max_cross, st.s.get("along", 0.0)])
	print("FLIGHT RESULT %s%s (sim %.0f s, wall %.0f s)" % ["PASS" if ok else "FAIL", "" if ok else " reason=" + reason, t,
		(Time.get_ticks_msec() - _wall0) / 1000.0])
	get_tree().quit(0 if ok else 1)


func _check() -> String:
	var want := ["LOC", "G/S", "LAND", "FLARE", "ROLL OUT", "RETARD"] if args.has("final") else \
		["NAV", "CLB", "ALT CRZ", "DES", "LOC", "G/S", "LAND", "FLARE", "ROLL OUT", "RETARD"]
	for w in want:
		if not w in _words and not (w + "*") in _words:
			return "never saw %s" % w
	if _td.along < 0.0 or _td.along > 1200.0 or absf(_td.cross) > 10.0:
		return "touchdown off the zone"
	return ""
