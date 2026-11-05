extends Node
## Probe: a scripted LANDING of the A320 from the default "In the air" start (aircraft.json start.air: 2,200 ft, 7 nm out, 160 KIAS,
## gear down, CONF 2), flown through the same Props the cockpit controls write (probe_a320_pilot.gd), measured by probe_a320_meter.gd.
## Headless, never writes the player's files. One run is a few minutes of wall time.
##   godot --headless --audio-driver Dummy --fixed-fps 120 --path game res://tests/probe_a320_landing.tscn -- [options]
## Options: --autobrake=lo|med|max|off (med)  --reverse=0|1|2 (1 idle reverse, 2 max reverse until 90 kt)  --wind=DIR/KT[Ggust]
##   (270/0)  --seed=N (airspeed-needle noise, 1)  --airport=VABB --runway=27  --idle  (idle-thrust descent instead: normal approach to 1,500 ft, then levers
##   at idle, pitch holds Vapp; max 160 s)  --max=sim s (700)  --wall=real s (900)  --quiet (no progress lines)  --p_<gain>=v (pilot gain, see P).
## Last lines: LANDING RESULT PASS|FAIL reason=.. then a key-number table. Exit code 0 = PASS, 1 = FAIL. `--idle` prints IDLE DESCENT ...

const Pilot := preload("res://tests/probe_a320_pilot.gd")
const State := preload("res://tests/probe_a320_state.gd")
const Meter := preload("res://tests/probe_a320_meter.gd")
const Report := preload("res://tests/probe_a320_report.gd")
const DEFAULTS := {"aircraft": "a320", "airport": "VABB", "runway": "27", "air": "", "wind": "270/0", "weather": "clear"}
const PROBE_KEYS := ["autobrake", "reverse", "seed", "idle", "max", "wall", "quiet", "log"]

var f: Node
var args := {}
var st := State.new()
var pilot := Pilot.new()
var meter := Meter.new()
var t := 0.0
var _ended := false
var _log := 0.0
var _wall0 := 0
var _ready_ok := false
var _idle_g: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Session.skip_menu = true
	Session.interactive_override = 0
	Session.save_path = "user://_probe_a320_landing_last_flight.json"
	TrainingLogic.save_path = "user://_probe_a320_landing_training.json"
	SituationStore.dir = "user://_probe_a320_landing_saves/"
	var flight_args := PackedStringArray()
	var merged := DEFAULTS.duplicate()
	for k in args:
		if not str(k) in PROBE_KEYS and not str(k).begins_with("p_"):
			merged[k] = args[k]
	for k in merged:
		flight_args.append("--%s%s" % [k, ("=" + str(merged[k])) if str(merged[k]) != "" else ""])
	Session._parse_args(flight_args)
	pilot.autobrake = {"off": 0, "lo": 1, "med": 2, "max": 3}.get(str(args.get("autobrake", "med")).to_lower(), 2)
	pilot.reverse = int(args.get("reverse", 1))
	pilot.idle_mode = args.has("idle")
	pilot.rng.seed = int(args.get("seed", 1))
	for k in args:
		if str(k).begins_with("p_"):
			pilot.P[str(k).substr(2)] = float(args[k])
	_wall0 = Time.get_ticks_msec()
	Engine.max_fps = 0
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _setup_flight() -> void:
	for n in ["Controls", "JoystickControls"]:
		var c := f.get_node_or_null(n)
		if c:
			c.set_process(false)
			c.set_physics_process(false)
			c.set_process_unhandled_input(false)
			c.set_process_unhandled_key_input(false)
	if not st.setup(f, Session.setup.airport, str(Session.setup.runway)):
		print("LANDING RESULT FAIL reason=no_runway %s %s" % [Session.setup.airport, Session.setup.runway])
		get_tree().quit(1)
		_ended = true
		return
	pilot.rwy_hdg = st.hdg
	_ready_ok = true
	print("LANDING start: %s %s hdg %.1f len %.0f m wide %.0f m, field %.0f m, wind %03d/%d, autobrake %d reverse %d, aircraft %s" % [
		st.apt, st.ident, st.hdg, st.length, st.width, st.field_m, int(Session.setup.wind_dir_deg), int(Session.setup.wind_kt),
		pilot.autobrake, pilot.reverse, Session.setup.aircraft])


func _physics_process(dt: float) -> void:
	if _ended or f == null or not f.is_node_ready():
		return
	if not _ready_ok:
		_setup_flight()
		if not _ready_ok:
			return
	t += dt
	var s := st.read(t)
	if t < 0.05:
		return
	if t < 0.1:
		pilot.start(s)
	_wind_vapp(s)
	meter.sample(s)
	pilot.decide(s, dt)
	if not args.has("quiet") and t >= _log:
		_log = t + (1.0 if (s.ra < 120.0 or s.wow) else float(args.get("log", 5.0)))
		print("LAND %5.1f %-8s ias %5.1f gs %5.1f ra %5.0f vs %5.0f fpa %5.2f hdg %5.1f pit %5.2f alp %5.2f bnk %5.1f trk %5.1f along %6.0f cr %5.1f dev %5.0f lev %.2f n1 %4.1f th %4.1f fl %4.1f sp %3.0f ab %d rev %.1f dec %.2f %s" % [
			t, pilot.phase, s.ias, s.gs, s.ra, s.vs, s.gamma, s.hdg, s.pitch, s.alpha, s.bank, s.trk, s.along, s.cross, s.dev_ft, s.lever,
			s.n1, s.thrust_kn, s.flap_deg, s.spoil, int(s.ab_on), s.rev, s.decel, "WOW" if s.wow else ""])
	if pilot.idle_mode and pilot.phase == "idle":
		_idle_g.append([s.gamma, s.n1, s.thrust_kn, s.ias, s.vs, s.pitch, s.alpha, s.lever])
	var stopped: bool = pilot.phase == "stopped" and t - meter.td.get("t", t) > 8.0
	var idle_done: bool = pilot.idle_mode and (s.ra < 600.0 or t > 160.0)
	if s.crashed or stopped or idle_done or t > float(args.get("max", 700.0)) or \
			(Time.get_ticks_msec() - _wall0) / 1000.0 > float(args.get("wall", 900.0)):
		_ended = true
		_end(s)


## Vapp = Vls + 5 kt, or Vls + a third of the headwind component (5..15 kt): as the FMGC computes it.
func _wind_vapp(s: Dictionary) -> void:
	if s.vls < 80.0:
		return
	var rel := deg_to_rad(float(Session.setup.wind_dir_deg) - st.hdg)
	var head := float(Session.setup.wind_kt) * cos(rel)
	pilot.vapp = s.vls + clampf(head / 3.0, 5.0, 15.0)


func _end(s: Dictionary) -> void:
	for l in pilot.log:
		print(l)
	var code := Report.print_all(self, s)
	get_tree().quit(code)
