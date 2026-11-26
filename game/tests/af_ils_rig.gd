class_name AfIlsRig
extends RefCounted
## Closed-loop rig of the autoland tests (tests/test_autoland*.gd) and of the glide slope capture tests: the REAL A320 (aircraft.json,
## its fly-by-wire law) in the FDM driven by a real FdmNode, the Autoflight node and NavRadios on an ILS station of the NavDatabase,
## over a flat runway at the threshold elevation. Wind and light / moderate turbulence (Turbulence, the Dryden filters the game
## uses) are put in the Props like world/weather.gd does. Nothing is scripted but the pilot's switches (FCU, flaps, gear, brakes).
## opts: nm (out on the course, 7), kias (140), flaps (lever detent, 5 = FULL), alt_ft (above the runway; default on the 3 deg path),
## offset_m (right of the axis, 0), wind_from_deg (or wind_rel_deg: from the right of the course) / wind_kt, turb (0..1), seed, ap2 (true), mass_kg (0 = as the aircraft is),
## spd_kt (the FCU speed, default kias), appr (true: press APPR), hdg_off_deg (heading error at the start, 0).

const KT := 0.514444
const FT := 0.3048
const NM := 1852.0
const DT := 1.0 / 120.0

var node: FdmNode
var f: FDM
var af: Autoflight
var radios: NavRadios
var s: Dictionary
var t := 0.0
var thr := Vector2.ZERO  # runway threshold, ENU
var course := 0.0  # true, rad
var ground_m := 0.0
var wind := Vector3.ZERO  # NED, m/s
var turb_level := 0.0
var turb := Turbulence.new()
var td := {}  # first touchdown: {t, along, cross, vs_fpm, pitch, gs_kt, cas_kt, bank, heading_err}
var max_cross := 0.0  # worst distance from the axis after touchdown
var crashed := false
var _snap := {}
var _prev_vs := 0.0
var _vs_hist: Array = []
var _was_wow := false
var brakes := true  # as a pilot does on the ground: autobrake MED, ground spoilers armed, idle reverse
var words := {"thrust": [], "vertical": [], "lateral": [], "approach": []}  # each FMA word in the order it first appeared (first line)


func _init(db: NavDatabase, station: Dictionary, o := {}) -> void:
	_snap = Props._p.duplicate(true)
	s = station
	course = deg_to_rad(float(s.course_true))
	thr = Vector2(s.threshold.x, s.threshold.y)
	ground_m = float(s.threshold.h)
	turb.rng.seed = int(o.get("seed", 1))
	turb_level = float(o.get("turb", 0.0))
	var from := deg_to_rad(float(o.get("wind_from_deg", 0.0)))
	if o.has("wind_rel_deg"):  # relative to the runway course: 0 head wind, 90 from the right, 180 tail wind
		from = course + deg_to_rad(float(o.wind_rel_deg))
	var wk := float(o.get("wind_kt", 0.0)) * KT
	wind = Vector3(-cos(from) * wk, -sin(from) * wk, 0.0)
	var def := AircraftDef.load_def("a320")
	f = FDM.new(def)
	f.ground_height = func(_n: float, _e: float) -> float: return ground_m
	node = FdmNode.new()
	node.fdm = f
	var nm := float(o.get("nm", 7.0))
	var kias := float(o.get("kias", 140.0))
	var axis := Vector2(sin(course), cos(course))
	var right := Vector2(cos(course), -sin(course))
	var p := thr - axis * nm * NM + right * float(o.get("offset_m", 0.0))
	var path_h := tan(deg_to_rad(float(s.gs_deg))) * nm * NM + 15.0  # the path at 15 m over the threshold
	var alt := ground_m + (float(o["alt_ft"]) * FT if o.has("alt_ft") else path_h)
	var flaps := int(o.get("flaps", 5))
	if float(o.get("mass_kg", 0.0)) > 0.0:
		_set_mass(float(o.mass_kg))  # before the trim, so the start is trimmed for this weight
	f.wind_ned = wind
	f.atmo.update(alt)
	f.fcs.flap_cmd = flaps
	f.fcs.snap_flaps()
	f.set_airborne(p.y, p.x, alt, course + deg_to_rad(float(o.get("hdg_off_deg", 0.0))), kias * KT)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 1
	f.gear.gear_pos = 1.0
	f.fcs.settle()
	f.trim_level_cas(kias * KT)
	for n in 2:
		Props.set_v("controls/engine_master_%d" % (n + 1), true)
		Props.set_v("controls/throttle_%d" % (n + 1), AfThrust.CL)  # the pilot's levers in the CL detent: A/THR flies the thrust
		Props.set_v("engines/%d/lever" % (n + 1), f.units[n].engine.throttle)
		Props.set_v("controls/reverse_%d" % (n + 1), 0.0)
	Props.set_v("controls/throttle", AfThrust.CL)
	Props.set_v("controls/gear", 1)
	Props.set_v("controls/flaps", flaps)
	Props.set_v("controls/pitch_trim", f.fcs.pitch_trim)
	Props.set_v("controls/baro/std", true)
	Props.set_v("engine/count", 2)
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("controls/autobrake", 0)
	for k in ["ap1", "ap2", "athr", "loc", "appr", "spd_managed", "hdg_managed", "vs_managed", "ap_disc", "athr_disc"]:
		Props.set_v("controls/fcu/" + k, false)
	Props.set_v("controls/fcu/fd", true)
	Props.set_v("controls/fcu/vert_select", "")
	Props.set_v("controls/fcu/spd_kt", float(o.get("spd_kt", kias)))
	Props.set_v("controls/fcu/hdg_deg", rad_to_deg(course) - AfInputs.VAR_DEG)
	Props.set_v("controls/fcu/alt_ft", (alt - ground_m) / FT + 1000.0)  # above: the glide slope is what descends
	Props.set_v("controls/fcu/vs_fpm", 0.0)
	for k in ["ap/athr_active", "ap/cmd/takeover", "fcs/alpha_floor", "failures/ap"]:
		Props.set_v(k, false)
	for k in ["ap/cmd/yaw", "ap/cmd/ground_pitch", "ap/cmd/nz_g", "ap/cmd/roll_rate_dps"]:
		Props.set_v(k, 0.0)
	Props.set_v("controls/nav2/freq_mhz", float(s.mhz))
	Props.set_v("controls/nav2/obs_deg", 270.0)
	Props.set_v("controls/nav1/freq_mhz", 116.6)
	radios = NavRadios.new()
	radios.db = db
	af = Autoflight.new()
	af.setup(def.section("limits"))
	af.db = db
	node._snap()
	_publish_wind(DT)
	node._publish()
	radios.update(0.1)
	if bool(o.get("appr", true)):
		Props.set_v("controls/fcu/appr", true)
	for k in ["ap1", "athr"]:
		Props.set_v("controls/fcu/" + k, true)
	if bool(o.get("ap2", true)):
		Props.set_v("controls/fcu/ap2", true)


func _set_mass(kg: float) -> void:
	var k := (kg - (f.mb.mass - f.mb.fuel_kg())) / maxf(f.mb.fuel_kg(), 1.0)
	for tk in f.mb.tanks:
		tk.contents_kg = maxf(float(tk.contents_kg) * k, 0.0)
	f.mb.update()


## The rig's nodes are never in the tree: free them, put the Props back.
func free_all() -> void:
	for n in [node, af, radios]:
		if is_instance_valid(n):
			n.free()
	Props._p = _snap


func _publish_wind(dt: float) -> void:
	var w := wind
	var pqr := Vector3.ZERO
	if turb_level > 0.0:
		var agl := f.agl
		var tw := turb.step(dt, agl, f.vt, Turbulence.sigma_w(turb_level, agl), wind, f.euler().z, 36.0)
		var taper := smoothstep(0.0, 6.0, agl - Props.get_f("fdm/wheel_depth_m", 0.0))  # no vertical wind through the ground
		w += Vector3(tw.x, tw.y, tw.z * taper)
		pqr = turb.pqr * taper
	Props.set_v("environment/wind_ned", w)
	Props.set_v("environment/gust_pqr", pqr)


func step() -> void:
	_publish_wind(DT)
	radios.update(DT)
	af.tick(DT)
	_prev_vs = Props.get_f("fdm/vs_mps")
	node._physics_process(DT)
	t += DT
	crashed = f.damage.crashed
	var wow := f.gear.wow
	if wow and brakes:
		Props.set_v("controls/autobrake", 2)
		Props.set_v("controls/speedbrake", 1.0)
		Props.set_v("controls/reverse_1", 0.1)
		Props.set_v("controls/reverse_2", 0.1)
	for c in words:
		var w := str(Props.get_v("ap/fma/" + c, "")).split("\n")[0]
		if w != "" and (words[c].is_empty() or words[c][-1] != w):
			words[c].append(w)
	if wow and not _was_wow and td.is_empty():
		var p := Vector2(f.pos_e, f.pos_n) - thr
		var axis := Vector2(sin(course), cos(course))
		td = {"t": t, "along": p.dot(axis), "cross": p.dot(Vector2(cos(course), -sin(course))), "vs_fpm": _prev_vs / FT * 60.0,
			"pitch": rad_to_deg(f.euler().y), "gs_kt": Props.get_f("fdm/groundspeed_mps") / KT, "cas_kt": f.cas / KT,
			"bank": rad_to_deg(f.euler().x), "heading_err": rad_to_deg(wrapf(f.euler().z - course, -PI, PI))}
	_was_wow = wow
	if not td.is_empty():
		max_cross = maxf(max_cross, absf(cross()))


func cross() -> float:
	var p := Vector2(f.pos_e, f.pos_n) - thr
	return p.dot(Vector2(cos(course), -sin(course)))


func along() -> float:
	return (Vector2(f.pos_e, f.pos_n) - thr).dot(Vector2(sin(course), cos(course)))


func ra_ft() -> float:
	return maxf(f.agl - Props.get_f("fdm/wheel_depth_m", 0.0), 0.0) / FT


func gs_kt() -> float:
	return Props.get_f("fdm/groundspeed_mps") / KT


func fma(col: String) -> String:
	return str(Props.get_v("ap/fma/" + col, "")).replace("\n", "/")


func fma_all() -> String:
	return "[%s][%s][%s][%s][%s]" % [fma("thrust"), fma("vertical"), fma("lateral"), fma("approach"), fma("misc")]


## Run until `until` returns true or `seconds` pass; `each` is called every tick after the step.
func run(seconds: float, until := Callable()) -> void:
	for k in int(seconds / DT):
		step()
		if crashed or (until.is_valid() and until.call() == true):
			return
