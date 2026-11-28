extends Node
## Probe: an A320 ILS approach from high and far out, flown step by step as the handbook tells a player (docs/site/index.html
## "An ILS approach from 10,000 ft"): an air start 20 nm out at 10,000 ft and 250 kt, clean, on the VABB 27 extended centreline;
## AP1 and A/THR, the FMGC's auto-tuned ILS, an open descent to 3,000 ft with the speedbrake, APPR and AP2, flaps and gear by the
## speeds, autoland, RETARD, roll out and autobrake to a stop. The crew is probe_a320_ils_steps.gd; every step prints OK or FAIL
## for what the player should see. Never writes the player's files. About 6 min of sim time, real time.
##   godot --audio-driver Dummy --fixed-fps 120 --path game res://tests/probe_a320_ils.tscn -- [options]   (windowed; or --headless)
## Options: --to=VABB --arr=27 --ft=10000 --nm=20 --kt=250 --wind=DIR/KT (0/0) --view=cockpit|chase (cockpit)
##   --shots=DIR (windowed: a PNG at each step and every 30 s, for a look; never into the repository) --max=sim s (900).
##   --kt=own: the start screen's In the air start (it has no speed slider): the A320's own 160 kt, gear down, CONF 2.
##   --managed: the trap (managed speed and flaps early, levels above the glide slope) and the recovery (V/S through the beam).
## Last line: ILS RESULT PASS|FAIL reason=..; exit code 0 = PASS.

const Steps := preload("res://tests/probe_a320_ils_steps.gd")
const State := preload("res://tests/probe_a320_state.gd")

var f: Node
var args := {}
var st := State.new()
var crew := Steps.new()
var dest_pos := Vector2.ZERO
var t := 0.0
var _ended := false
var _ready_ok := false
var _log := 0.0
var _shot_t := 0.0
var _shot_n := 0
var _last_step := ""
var _fma_last := ""
var _td := {}
var _disc0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Session.skip_menu = true
	Session.interactive_override = 0
	Session.save_path = "user://_probe_a320_ils_last_flight.json"
	TrainingLogic.save_path = "user://_probe_a320_ils_training.json"
	SituationStore.dir = "user://_probe_a320_ils_saves/"
	var cli := ["--aircraft=a320", "--airport=%s" % a_("to", "VABB"), "--runway=%s" % a_("arr", "27"), "--air=%s" % a_("ft", "10000"),
		"--air-nm=%s" % a_("nm", "20"), "--weather=clear", "--wind=%s" % a_("wind", "0/0")]
	if a_("kt", "250") != "own":  # own: the start screen's In the air (no speed slider): 160 kt, gear down, CONF 2
		cli.append("--air-kt=%s" % a_("kt", "250"))
	Session._parse_args(PackedStringArray(cli))
	Session.setup.route = {}
	Session.view = a_("view", "cockpit")
	crew.managed = args.has("managed")
	crew.own_start = a_("kt", "250") == "own"
	dest_pos = NavDatabase.new().position_of(a_("to", "VABB"))
	print("ILS air start %s %s, %s nm, %s ft, %s kt" % [a_("to", "VABB"), a_("arr", "27"), a_("nm", "20"), a_("ft", "10000"), a_("kt", "250")])
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
	if not st.setup(f, a_("to", "VABB"), a_("arr", "27")):
		_finish(false, "no arrival runway")
		return
	_ready_ok = true


func _physics_process(dt: float) -> void:
	if _ended or f == null or not f.is_node_ready():
		return
	if not _ready_ok:
		_setup_flight()
		if not _ready_ok:
			return
	t += dt
	if t < 2.0:
		_disc0 = int(Props.get_v("ap/disconnect_count", 0))
		return
	var s := _read(t - 2.0)
	crew.decide(s)
	_watch(s)
	if t >= _log:
		_log = t + (2.0 if s.ra < 500.0 else 10.0)
		print("ILS %7.1f %-8s ias %5.1f/%3.0f alt %6.0f path %6.0f ra %6.0f vs %6.0f hdg %5.1f dest %5.1f sb %.2f fl %d gear %d | %s | %s cross %.0f" % [
			s.t, crew.step, s.ias, s.spd_tgt_kt, s.alt_ft, s.path_ft, s.ra, s.vs, s.hdg, s.dest_nm, Props.get_f("controls/speedbrake"),
			int(Props.get_v("controls/flaps", 0)), int(Props.get_v("controls/gear", 0)), s.fma, s.ils_auto, s.cross])
	_shots(s)
	if s.crashed:
		_finish(false, "crashed")
	elif crew.step == "stopped":
		_finish(true, "")
	elif t > float(a_("max", "900")):
		_finish(false, "timeout in step %s" % crew.step)
	elif s.disc_count > _disc0 and crew.step != "rollout":
		_finish(false, "autopilot disconnected in step %s (FMA %s)" % [crew.step, s.fma])


func _read(tt: float) -> Dictionary:
	var s := st.read(tt)
	var p := st.fn.position_enu()
	s["alt_ft"] = AfInputs.indicated_alt_m() / 0.3048
	s["path_ft"] = State.path_ft(s.along) + st.field_m / 0.3048  # the 3 degree path, ft above sea level
	var cols := {"thr_fma": "thrust", "vert_fma": "vertical", "lat_fma": "lateral", "appr_fma": "approach", "misc_fma": "misc"}
	for k in cols:
		s[k] = str(Props.get_v("ap/fma/" + cols[k], ""))
	s["fma"] = " / ".join([s.thr_fma, s.vert_fma, s.lat_fma, s.appr_fma, s.misc_fma].map(func(x): return str(x).replace("\n", " ")))
	s["spd_tgt_kt"] = Props.get_f("ap/spd_target_kt")
	s["fcu_alt"] = Props.get_f("controls/fcu/alt_ft")
	s["dest_nm"] = -s.along / 1852.0
	s["ils_valid"] = Props.get_b("avionics/nav2/valid")
	s["ils_auto"] = "%s %.2f %s" % [Props.get_v("avionics/ils_auto/ident", ""), Props.get_f("controls/nav2/freq_mhz"),
		"valid" if s.ils_valid else "-"]
	s["disc_count"] = int(Props.get_v("ap/disconnect_count", 0))
	return s


func _watch(s: Dictionary) -> void:
	if s.fma != _fma_last:
		_fma_last = s.fma
		crew.say(s.t, "FMA %s  (%.1f nm, %.0f ft, %.0f ft above the path, %.0f kt, RA %.0f)" % [s.fma, s.dest_nm, s.alt_ft,
			s.alt_ft - s.path_ft, s.ias, s.ra])
	if s.wow and _td.is_empty():
		_td = {"along": s.along, "cross": s.cross, "vs": s.vs, "ias": s.ias, "pitch": s.pitch}


## Windowed with --shots: a picture at each new step and every 30 s (temporary, for a look; delete them after).
func _shots(s: Dictionary) -> void:
	if not args.has("shots") or DisplayServer.get_name() == "headless":
		return
	if crew.step != _last_step or s.t >= _shot_t:
		_shot_t = s.t + 30.0
		_shot_n += 1
		var path := "%s/%02d_%s_%03.0fs.png" % [a_("shots", ""), _shot_n, crew.step, s.t]
		get_viewport().get_texture().get_image().save_png(path)
	_last_step = crew.step


func _finish(ok: bool, why: String) -> void:
	_ended = true
	var reason := why
	var bad: Array = crew.checks.filter(func(c): return not c[1])
	if ok and not bad.is_empty():
		ok = false
		reason = "step %s: %s" % [bad[0][0], bad[0][2]]
	if ok and (_td.is_empty() or _td.along < 0.0 or _td.along > 1200.0 or absf(_td.cross) > 10.0):
		ok = false
		reason = "touchdown off the zone"
	if not _td.is_empty():
		print("ILS touchdown %.0f m past the threshold, %.1f m off the axis, %.0f fpm, %.0f kt, pitch %.1f; stopped %.0f m past the threshold" % [
			_td.along, _td.cross, _td.vs, _td.ias, _td.pitch, st.s.get("along", 0.0)])
	print("ILS checks: %d OK, %d FAIL" % [crew.checks.size() - bad.size(), bad.size()])
	for c in bad:
		print("ILS FAILED [%s] %s" % [c[0], c[2]])
	print("ILS RESULT %s%s (sim %.0f s)" % ["PASS" if ok else "FAIL", "" if ok else " reason=" + reason, t])
	get_tree().quit(0 if ok else 1)
