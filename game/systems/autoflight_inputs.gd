class_name AfInputs
extends RefCounted
## What the autoflight sees on one tick, in SI (m, s, rad, m/s). read() fills it from Props; tests fill
## the fields directly. The FCU set-points are converted from pilot units here (the only place).
## From Props: fdm/{cas_mps, tas_mps, mach, vs_mps, agl_m, position_enu, pitch_rad, roll_rad,
## heading_rad (true), track_rad (true), groundspeed_mps, wow, gear_pos, flap_lever, flap_deg, slat_deg,
## mass_kg, alpha_rad}, atmosphere/pressure_pa, controls/baro/{hpa, std}, controls/throttle[_n] (the pilot's
## levers), engines/<n>/lever, controls/flex_temp_c, fcs/alpha_floor and ap/cmd/takeover (from the control
## law), systems/electrical/avionics_powered, failures/ap, avionics/nav{1,2}/{kind, valid, gs_valid},
## avionics/gps/{valid, brg_mag, dist_nm, xtk_nm}, controls/fcu/*.
## The ILS geometry (course, antenna positions, glide path angle) comes from a NavDatabase `db` (set by the
## wiring, as for Gps); the radios only say whether the signals are received.

const VAR_DEG := -0.3  # magnetic variation, as in avionics/gps.gd and instruments/adirs.gd (mag = true - VAR)
const G := 9.80665

var dt := 0.0
var cas := 0.0
var tas := 0.0
var mach := 0.0
var alt_m := 0.0  # indicated (baro-corrected, like the PFD and the FCU selection)
var vs_mps := 0.0
var ra_m := 1.0e5  # radio altitude (height above the ground)
var pos := Vector3.ZERO  # ENU, z = true MSL height
var pitch := 0.0
var roll := 0.0
var heading := 0.0  # true
var track := 0.0  # true
var gs_mps := 0.0  # ground speed
var alpha := 0.0
var mass_kg := 64000.0
var pressure_pa := 101325.0
var wow := false
var gear_down := true
var flap_lever := 0
var ext_deg := 0.0  # slat + flap deflection
var lever := 0.0  # the pilot's thrust levers (highest of the engines), 0..1 detent scale
var engine_lever := 0.0  # where the engines are now (mean engines/<n>/lever), for a bumpless A/THR engage
var flex_c := 0.0
var alpha_floor := false  # from the control law
var takeover := false  # from the control law: sidestick moved beyond the threshold
var powered := true
var ap_failed := false
var ils := {}  # {course, loc: Vector2, gs_pos: Vector2, gs_h, gs_rad, gs_valid} or empty
var gps := {}  # {brg (true rad), dist, xtk} or empty
var f := {  # FCU, SI. Flags are the pilot's requests (the buttons).
	"spd": 128.6, "hdg": 0.0, "alt": 3048.0, "vs": 0.0,
	"ap1": false, "ap2": false, "athr": false, "loc": false, "appr": false, "fd": true,
	"spd_mgd": false, "hdg_mgd": false, "vs_mgd": false, "ap_disc": false, "athr_disc": false, "select": "",
}


func read(delta: float, db: NavDatabase) -> void:
	dt = delta
	cas = Props.get_f("fdm/cas_mps")
	tas = Props.get_f("fdm/tas_mps")
	mach = Props.get_f("fdm/mach")
	vs_mps = Props.get_f("fdm/vs_mps")
	ra_m = Props.get_f("fdm/agl_m", 1.0e5)
	pos = Props.get_v("fdm/position_enu", Vector3.ZERO)
	pitch = Props.get_f("fdm/pitch_rad")
	roll = Props.get_f("fdm/roll_rad")
	heading = Props.get_f("fdm/heading_rad")
	track = Props.get_f("fdm/track_rad")
	gs_mps = Props.get_f("fdm/groundspeed_mps")
	alpha = Props.get_f("fdm/alpha_rad")
	mass_kg = Props.get_f("fdm/mass_kg", 64000.0)
	pressure_pa = Props.get_f("atmosphere/pressure_pa", 101325.0)
	wow = Props.get_b("fdm/wow")
	var gp: Variant = Props.get_v("fdm/gear_pos", 1.0)
	gear_down = (gp.min() if gp is Array and not gp.is_empty() else float(gp)) > 0.5
	flap_lever = int(Props.get_v("fdm/flap_lever", 0))
	ext_deg = Props.get_f("fdm/slat_deg") + Props.get_f("fdm/flap_deg")
	alt_m = indicated_alt_m()
	flex_c = Props.get_f("controls/flex_temp_c")
	alpha_floor = Props.get_b("fcs/alpha_floor")
	takeover = Props.get_b("ap/cmd/takeover")
	powered = Props.get_b("systems/electrical/avionics_powered", true)
	ap_failed = Props.get_b("failures/ap")
	_levers()
	_nav(db)
	_fcu()


## Baro-corrected altitude like instruments/airliner_air_data.gd (QNH of the weather, or STD).
static func indicated_alt_m() -> float:
	if not Props.has("atmosphere/pressure_pa"):
		return Props.get_f("fdm/alt_m")
	var baro := 1013.25 if Props.get_b("controls/baro/std") else Props.get_f("controls/baro/hpa", Props.get_f("weather/qnh_hpa", 1013.25))
	return AtmosphereISA.indicated_altitude(Props.get_f("atmosphere/pressure_pa"), baro * Units.HPA)


func _levers() -> void:
	var n := maxi(int(Props.get_v("engine/count", 2)), 1)
	lever = 0.0
	engine_lever = 0.0
	for k in n:
		var own := "controls/throttle_%d" % (k + 1)
		lever = maxf(lever, Props.get_f(own if Props.has(own) else "controls/throttle"))
		engine_lever += Props.get_f("engines/%d/lever" % (k + 1), lever)
	engine_lever /= n


func _nav(db: NavDatabase) -> void:
	ils = {}
	if db != null:
		for n in [2, 1]:  # the PFD shows NAV2 first
			var b := "avionics/nav%d/" % n
			if str(Props.get_v(b + "kind", "")) != "ILS" or not Props.get_b(b + "valid"):
				continue
			var st := db.nav_station(Props.get_f("controls/nav%d/freq_mhz" % n), Vector2(pos.x, pos.y))
			if st.get("kind", "") != "ILS":
				continue
			var s: Dictionary = st.s
			ils = {"course": deg_to_rad(s.course_true), "loc": Vector2(s.loc.x, s.loc.y), "gs_pos": Vector2(s.gs.x, s.gs.y),
				"gs_h": float(s.gs.h), "gs_rad": deg_to_rad(s.gs_deg), "gs_valid": Props.get_b(b + "gs_valid")}
			break
	gps = {}
	if Props.get_b("avionics/gps/valid") and Props.get_v("avionics/gps/ident", "") != "":
		gps = {"brg": deg_to_rad(Props.get_f("avionics/gps/brg_mag") + VAR_DEG), "dist": Props.get_f("avionics/gps/dist_nm") * Units.NM,
			"xtk": Props.get_f("avionics/gps/xtk_nm") * Units.NM}


func _fcu() -> void:
	f.spd = Units.kt_to_mps(Props.get_f("controls/fcu/spd_kt", 250.0))
	f.hdg = deg_to_rad(Props.get_f("controls/fcu/hdg_deg") + VAR_DEG)
	f.alt = Units.ft_to_m(Props.get_f("controls/fcu/alt_ft", 10000.0))
	f.vs = Props.get_f("controls/fcu/vs_fpm") * Units.FPM
	for k in ["ap1", "ap2", "athr", "loc", "appr", "spd_managed", "hdg_managed", "vs_managed"]:
		f[k.replace("_managed", "_mgd")] = Props.get_b("controls/fcu/" + k)
	f.fd = Props.get_b("controls/fcu/fd", true)
	f.ap_disc = Props.get_b("controls/fcu/ap_disc")
	f.athr_disc = Props.get_b("controls/fcu/athr_disc")
	f.select = str(Props.get_v("controls/fcu/vert_select", ""))


## Lateral offset from the localizer course, m, + = aircraft right of the course.
func loc_offset_m() -> float:
	var c: float = ils.course
	var d := Vector2(pos.x, pos.y) - ils.loc as Vector2
	return d.dot(Vector2(cos(c), -sin(c)))


## Height above the glide path, m (+ = above), along the path through the glide slope antenna.
func gs_error_m() -> float:
	var gd := Vector2(pos.x, pos.y).distance_to(ils.gs_pos)
	return pos.z - (float(ils.gs_h) + tan(ils.gs_rad) * gd)


## Flight path angle from the vertical speed (rad).
func gamma() -> float:
	return asin(clampf(vs_mps / maxf(tas, 20.0), -0.5, 0.5))
