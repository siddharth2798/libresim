extends SceneTree
## Flies scripted manoeuvres in our FDM and writes time histories for
## tools/18_compare_fdm.py, which flies the same scripts in JSBSim c172p and plots both.
##   godot --headless --path game -s res://tests/fdm_compare.gd [-- --out=/tmp/fdm_compare]
## The control laws here are mirrored line for line in tools/18_compare_fdm.py (class Pilot);
## change both together. Pilot conventions: pitch +1 = yoke aft, roll +1 = right, yaw +1 = right pedal.
## Load: the c172p default (pilot 180 lb in the left seat, 100 lb fuel per tank), the game's solo default.

const DT := 1.0 / 120.0  # control/log rate; the FDM runs 2 sub-steps per tick like FdmNode
const KT := 0.514444
const FT := 0.3048

var f: FDM
var rows: Array = []
var t := 0.0
var ip := 0.0  # pitch-hold integrator
var isp := 0.0  # speed-hold integrator
var u := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
var out_dir := "/tmp/fdm_compare"
var h0 := 0.0  # CG height above the runway sitting on the gear (m)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var g := FDM.new()
	g.set_on_ground(0, 0, 0)
	h0 = -g.pos_d
	for m in ["hands_off", "takeoff", "climb", "aileron_step", "elevator_doublet", "rudder_doublet",
			"stall_clean", "stall_flaps", "glide", "landing", "crosswind_takeoff"]:
		call("m_" + m)
		_save(m)
	print("fdm_compare: wrote %s/ours_*.csv" % out_dir)
	quit()


# --- set-up ------------------------------------------------------------------

func _new() -> void:
	f = FDM.new()  # config default load = JSBSim c172p default
	rows = []
	t = 0.0
	ip = 0.0
	isp = 0.0
	u = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}


func setup_air(alt_ft: float, kcas: float, flaps := 0) -> void:
	_new()
	f.fcs.flap_cmd = flaps
	f.fcs.flap_deg = [0.0, 10.0, 20.0, 30.0][flaps]
	f.engine.mixture = 1.0
	var tas := kcas * KT
	for i in 3:  # trim at TAS, then correct TAS so CAS hits the target
		f.set_airborne(0, 0, alt_ft * FT, 0.0, tas)
		f.prop.rpm = 2300.0
		f.trim_level(tas)
		f.step(1e-4)
		tas *= kcas * KT / f.cas
	f.time = 0.0


func setup_ground() -> void:
	_new()
	f.set_on_ground(0, 0, 0)
	f.engine.mixture = 1.0
	f.prop.rpm = 1000.0
	f.fcs.pitch_trim = 0.0
	f.gear.brake_left = 1.0
	f.gear.brake_right = 1.0
	for i in 240:  # settle on the gear, brakes on
		_tick()
	f.gear.brake_left = 0.0
	f.gear.brake_right = 0.0
	rows = []
	t = 0.0


# --- shared pilot laws (mirror of Pilot in tools/18_compare_fdm.py) ----------

func wings_level() -> void:
	u.roll = clampf(-2.0 * f.euler().x - 0.5 * f.w_b.x, -1.0, 1.0)


func pitch_hold(theta_t: float) -> void:
	var err := theta_t - f.euler().y
	ip = clampf(ip + err * DT, -2.0, 2.0)
	u.pitch = clampf(3.0 * err + 1.5 * ip - 0.6 * f.w_b.y, -1.0, 1.0)


func speed_hold(kcas: float) -> void:
	var e := f.cas - kcas * KT
	isp = clampf(isp + e * DT, -100.0, 100.0)
	pitch_hold(clampf(0.03 * e + 0.006 * isp, -0.3, 0.35))


func heading_hold(psi_t: float) -> void:
	var e := wrapf(psi_t - f.euler().z, -PI, PI)
	u.yaw = clampf(3.0 * e - 0.5 * f.w_b.z, -1.0, 1.0)


# --- stepping and logging -----------------------------------------------------

func _tick() -> void:
	f.fcs.pitch = u.pitch
	f.fcs.roll = u.roll
	f.fcs.yaw = u.yaw
	f.step(DT * 0.5)
	f.step(DT * 0.5)
	t += DT


func run(seconds: float, law: Callable) -> void:
	var n := int(round(seconds / DT))
	for i in n:
		_log()
		if law.call() == true:
			return
		_tick()


func _log() -> void:
	var e := f.euler()
	var v := f.velocity_ned()
	rows.append([t, -f.pos_d / FT, f.agl / FT, f.cas / KT, f.vt / KT, rad_to_deg(e.x), rad_to_deg(e.y),
		rad_to_deg(e.z), rad_to_deg(f.alpha), rad_to_deg(f.beta), rad_to_deg(f.w_b.x), rad_to_deg(f.w_b.y),
		rad_to_deg(f.w_b.z), -v.z / FT * 60.0, f.prop.rpm, f.pos_n / FT, f.pos_e / FT, int(f.gear.wow),
		u.pitch, u.roll, u.yaw, f.engine.throttle, f.fcs.pitch_trim, f.engine.power_w / 745.7])


func _save(name: String) -> void:
	var fa := FileAccess.open("%s/ours_%s.csv" % [out_dir, name], FileAccess.WRITE)
	fa.store_line("t,alt_ft,agl_ft,kcas,ktas,phi,theta,psi,alpha,beta,p,q,r,vs_fpm,rpm,x_ft,y_ft,wow,pitch,roll,yaw,throttle,trim,hp")
	for r in rows:
		fa.store_line(",".join(r.map(func(x): return "%.5f" % x)))
	fa.close()


# --- manoeuvres (same scripts in tools/18_compare_fdm.py) --------------------

func m_hands_off() -> void:  # trimmed cruise 1500 ft / 100 KIAS, hands off 60 s
	setup_air(1500, 100)
	run(60.0, func(): return false)


func m_climb() -> void:  # Vy 74 KIAS, full throttle, from 1000 ft
	setup_air(1000, 74)
	f.engine.throttle = 1.0
	run(60.0, func(): speed_hold(74); wings_level(); return false)


func m_aileron_step() -> void:  # half right aileron 1..4 s, elevator at trim
	setup_air(1500, 100)
	run(6.0, func(): u.roll = 0.5 if t >= 1.0 and t < 4.0 else 0.0; return false)


func m_elevator_doublet() -> void:  # +-0.2 doublet, then hands off in pitch (phugoid)
	setup_air(1500, 100)
	run(120.0, func():
		u.pitch = 0.2 if t >= 1.0 and t < 2.0 else (-0.2 if t >= 2.0 and t < 3.0 else 0.0)
		wings_level()
		return false)


func m_rudder_doublet() -> void:  # +-0.5 rudder doublet, ailerons free (dutch roll)
	setup_air(1500, 100)
	run(15.0, func():
		u.yaw = 0.5 if t >= 1.0 and t < 2.0 else (-0.5 if t >= 2.0 and t < 3.0 else 0.0)
		return false)


func _stall(flaps: int, kcas: float) -> void:  # idle, yoke ramps aft 4 %/s from trim
	setup_air(3000, kcas, flaps)
	f.engine.throttle = 0.0
	run(40.0, func(): u.pitch = clampf(0.04 * t, 0.0, 1.0); wings_level(); return false)


func m_stall_clean() -> void:
	_stall(0, 70.0)


func m_stall_flaps() -> void:
	_stall(3, 60.0)


func m_glide() -> void:  # idle, hold 68 KIAS (best glide)
	setup_air(3000, 68)
	f.engine.throttle = 0.0
	run(90.0, func(): speed_hold(68); wings_level(); heading_hold(0.0); return false)


func _takeoff_law(xwind: bool) -> bool:
	f.engine.throttle = 1.0
	heading_hold(0.0)
	if f.cas < 55.0 * KT and f.agl - h0 < 1.0:
		u.pitch = 0.0
		u.roll = clampf(0.6 * (1.0 - f.cas / (60.0 * KT)), 0.0, 1.0) if xwind else 0.0
	else:
		pitch_hold(deg_to_rad(8.0))
		wings_level()
	return f.agl - h0 > 50.0 * FT


func m_takeoff() -> void:  # flaps up, full power, rotate at 55 KIAS to 8 deg
	setup_ground()
	run(60.0, func(): return _takeoff_law(false))


func m_crosswind_takeoff() -> void:  # 10 kt from the right (090)
	setup_ground()
	f.wind_ned = Vector3(0.0, -10.0 * KT, 0.0)
	run(60.0, func(): return _takeoff_law(true))


func m_landing() -> void:  # 50 ft, 61 KIAS, flaps 30, idle; flare at 20 ft; brakes after touchdown
	setup_air(50.0 + h0 / FT, 61, 3)
	f.engine.throttle = 0.0
	var td := [-1.0]
	run(90.0, func():
		heading_hold(0.0)
		if td[0] < 0.0 and f.gear.wow:
			td[0] = t
		if td[0] < 0.0:
			wings_level()
			var h := f.agl - h0
			if h > 20.0 * FT:
				speed_hold(61)
			else:  # flare: sink rate proportional to height
				var vs := -f.velocity_ned().z
				var vs_t := -0.3 - 0.25 * maxf(h, 0.0)
				pitch_hold(clampf(f.euler().y + 0.08 * (vs_t - vs), -0.1, 0.25))
		else:
			u.roll = 0.0
			u.pitch = 1.0 if t - td[0] < 1.0 else 0.3
			var b := 1.0 if t - td[0] > 1.0 else 0.0
			f.gear.brake_left = b
			f.gear.brake_right = b
		return td[0] > 0.0 and f.vt < 1.0 and t - td[0] > 2.0)
