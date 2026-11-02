extends Node
## Debug: a "user-like" landing. Flies the landing lesson's runway in the real flight scene with the real
## KeyboardControls: the pilot (play_landing_pilot.gd) only holds / releases keys (Input.parse_input_event)
## and decides every 0.1 s from what a pilot can see (airspeed, altitude AGL, vertical speed, attitude,
## track, runway position and the 3 deg path picture) like a student: pitch holds speed, power holds the
## path, trim off the stick, flaps by distance, flare by vertical speed, brakes after the nose is down.
## It also checks the PAPI of the landing runway end (play_landing_papi.gd): the 4 units are there on the
## left, abeam the glide-slope point (or 300 m past the threshold), and the reading the pilot's eye sees
## (camera position, "WWRR" outer unit first) is the one worked out from the elevation angle to each unit,
## sampled at 4.5 / 3 / 2 / 1 / 0.5 nm and once a second. A PAPI fault fails the run.
## Headless only; the run never writes the player's files (Session.interactive() is false for a test scene).
##
## Run (one run is about a minute):
##   godot --headless --fixed-fps 120 --path game res://tests/play_landing.tscn -- --lesson=landing,off [options]
## Options: --seed=N (airspeed-needle noise, default 1)  --nm=4.5 --ft=1500 --kt=90 (start; --ft follows --nm
##   on the 3 deg path if not given)  --vref=65  --wind=220/12G18 (dir/kt[Ggust], default the lesson's 280/4)
##   --turb=0.3  --max=400 (sim seconds)  --wall=900 (real seconds)  --papi-need=WWWW|RRRR (that reading must
##   be seen: use it with a deliberately high / low start)  --p_<gain>=value (a gain of the pilot, see P in
##   play_landing_pilot.gd)
## Verified: 5 seeds x calm / 220/12G18 turb 0.15, at the lesson start and at --nm=4.5 --ft=1700 (turb 0.3 is beyond a student).
## PAPI is OK when the layout is right, every reading equals the worked-out one, and on the path (+-0.2 deg) WWRR
## is seen at least half of the time (the unit settings are +-0.17 deg wide).
## Last line: PLAY RESULT PASS|FAIL reason=.. touchdown_ias=.. vs_fpm=.. along_m=.. cross_m=.. bounces=.. papi=OK|FAIL ..
##   Exit code 0 = PASS, 1 = FAIL.
## Sweep (calm, crosswind, off-nominal starts, high / low PAPI starts):
##   for s in 1 2 3 4 5; do for w in "" "--wind=220/12G18 --turb=0.3"; do
##     godot --headless --fixed-fps 120 --path game res://tests/play_landing.tscn -- --lesson=landing,off --seed=$s $w \
##       | grep "PLAY RESULT"; done; done
##   ... -- --lesson=landing,off --nm=4.5 --ft=1700 --seed=2                     (farther out and higher)
##   ... -- --lesson=landing,off --ft=1300 --papi-need=WWWW   /   --ft=700 --papi-need=RRRR   (high / low)

const Pilot := preload("res://tests/play_landing_pilot.gd")
const PapiCheck := preload("res://tests/play_landing_papi.gd")

var f: Node
var ts: TrainingSession
var args := {}
var t := 0.0
var s := {}
var pilot := Pilot.new()
var papi := PapiCheck.new()
var td := {}  # first touchdown record
var bounces := 0
var _next := 0.0
var _log := 0.0
var _was_wow := false
var _ended := false
var _rwy_w := 30.0
var _wall0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	pilot.rng = RandomNumberGenerator.new()
	pilot.rng.seed = int(args.get("seed", 1))
	pilot.vref = float(args.get("vref", 65.0))
	for k in args:
		if str(k).begins_with("p_"):
			pilot.P[str(k).substr(2)] = float(args[k])  # a tuning hook
	_wall0 = Time.get_ticks_msec()
	Engine.max_fps = 0
	if args.has("nm"):
		Session.setup.air_nm = float(args.nm)
		if not args.has("ft"):
			Session.setup.air_ft = roundf(float(args.nm) * 318.0 / 100.0) * 100.0
	if args.has("ft"):
		Session.setup.air_ft = float(args.ft)
	if args.has("kt"):
		Session.setup.air_kt = float(args.kt)
	if args.has("wind"):
		Session._wind(str(args.wind))  # the lesson owns the weather, so this comes after it
	if args.has("turb"):
		Session.setup.turbulence = float(args.turb)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	ts = f.get_node("Training")
	await get_tree().physics_frame
	await get_tree().physics_frame
	pilot.rwy_hdg = float(ts._rw.hdg)
	Props.set_v("controls/mixture", 1.0)
	for r in ts.airports.data.runways:
		if r.airport == Session.setup.airport and str(Session.setup.runway) in [str(r.ends[0].ident), str(r.ends[1].ident)]:
			_rwy_w = float(r.width)
	print("PLAY start: %s rwy %s hdg %.0f, %.0f ft %.1f nm %.0f kt, wind %03d/%d G%d seed %d" % [Session.setup.airport,
		Session.setup.runway, pilot.rwy_hdg, Session.setup.air_ft, Session.setup.air_nm, Session.setup.air_kt,
		int(Session.setup.wind_dir_deg), int(Session.setup.wind_kt), int(Session.setup.gust_kt), int(args.get("seed", 1))])


## Where the pilot's eyes are: the active camera (what the PAPI shader sees), else the aircraft.
func _eye() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam:
		return FloatingOrigin.to_world(cam.global_position)
	return s.pos + Vector3(0, 0, 1.2)


func _physics_process(dt: float) -> void:
	if ts == null or ts.run.is_empty() or _ended:
		return
	t += dt
	s = ts._snapshot()
	var wow: bool = s.wow > 0.5
	if wow and not _was_wow:
		if td.is_empty():
			td = {"t": t, "ias": s.ias, "vs": s.vs, "pitch": s.pitch, "along": s.along, "cross": s.cross, "bank": s.bank}
			print("PLAY TOUCHDOWN t=%.1f ias %.0f kt  vs %.0f fpm  pitch %.1f  bank %.1f  along %.0f m  cross %.1f m" % [t, s.ias, s.vs, s.pitch, s.bank, s.along, s.cross])
		else:
			bounces += 1
			print("PLAY re-touch t=%.1f ias %.0f vs %.0f pitch %.1f (bounce %d)" % [t, s.ias, s.vs, s.pitch, bounces])
	_was_wow = wow
	if t >= _log:
		_log = t + (0.5 if s.agl < 60.0 or wow else 5.0)
		print("PLAY t=%5.1f ias %5.1f agl %5.0f vs %5.0f pitch %5.1f bank %5.1f hdg %5.1f thr %.2f flaps %d stick %+.2f trim %+.2f | along %6.0f cross %6.1f gp %+.2f %s %s" % [t, s.ias, s.agl, s.vs, s.pitch, s.bank, s.hdg,
			s.throttle, int(s.flaps), s.pitch_in, Props.get_f("controls/pitch_trim"), s.along, s.cross, s.gp_dev, "WOW" if wow else "", pilot.dbg])
	if t >= _next:
		_next = t + Pilot.TICK
		pilot.decide(s, t)
		if papi.units.is_empty():
			papi.find(f, ts)  # the lights are built a moment after the start
		else:
			papi.tick(s, _eye(), t)
	if Props.get_b("damage/crashed") or ts.result_kind != "" or t > float(args.get("max", 400.0)) \
			or (Time.get_ticks_msec() - _wall0) / 1000.0 > float(args.get("wall", 900.0)):
		_ended = true
		_end()


func _end() -> void:
	pilot.release_all()
	var crashed := Props.get_b("damage/crashed")
	print("PLAY END t=%.1f crashed=%s events=%s kind=%s bounces=%d" % [t, crashed, Props.get_v("damage/events", []), ts.result_kind, bounces])
	if not ts.run.aborted.is_empty():
		print("PLAY ABORT: %s" % ts.run.aborted.reason)
	var reason := ""
	if crashed:
		reason = "crashed"
	elif td.is_empty():
		reason = "no_touchdown_timeout" if t > float(args.get("max", 400.0)) else "no_touchdown"
	elif td.along < 0.0 or td.along > float(ts._rw.length) - 100.0 or absf(td.cross) > _rwy_w * 0.5:
		reason = "touchdown_off_runway"
	elif bounces > 3:
		reason = "too_many_bounces"
	elif not ts.run.aborted.is_empty():
		reason = "lesson_aborted"
	elif ts.result_kind != "complete":
		reason = "lesson_%s" % (ts.result_kind if ts.result_kind != "" else "timeout")
	var pv: Array = papi.verdict(str(args.get("papi-need", "")))
	if reason == "" and not pv[0]:
		reason = "papi"
	var ok := reason == ""
	print("PLAY RESULT %s reason=%s touchdown_ias=%.0f vs_fpm=%.0f along_m=%.0f cross_m=%.1f bounces=%d papi=%s %s" % [
		"PASS" if ok else "FAIL", reason if reason != "" else "landed_and_rolled_out", td.get("ias", 0.0), td.get("vs", 0.0),
		td.get("along", 0.0), td.get("cross", 0.0), bounces, "OK" if pv[0] else "FAIL", pv[1]])
	get_tree().quit(0 if ok else 1)
