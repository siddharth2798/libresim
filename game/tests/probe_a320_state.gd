extends RefCounted
## Probe helper of probe_a320_landing.gd: runway geometry and one flat dictionary of everything the scripted A320 pilot and the
## meter read each tick (from the Props the FDM publishes, plus the FDM's wheel compressions). SI inside, kt / ft / fpm / deg
## where the key says so. along = m past the threshold along the runway (negative before it), cross = m right of the centreline.

const KT := 0.514444
const FT := 0.3048
const PATH_DEG := 3.0
const AIM_M := 300.0  # the 3 deg path ends here, so it crosses the threshold at about 50 ft

var fn: FdmNode
var apt := ""
var ident := ""
var thr := Vector2.ZERO  # threshold (east, north), m
var fwd := Vector2.RIGHT
var hdg := 0.0  # runway true heading, deg
var length := 0.0
var width := 45.0
var field_m := 0.0  # terrain height at the threshold
var s := {}
var _prev_t := 0.0
var _gs_hist: Array = []  # [t, gs_mps] at about 10 Hz


## Finds the landing runway end `ident` of `apt` in the airport data and the field height under it.
func setup(f: Node, airport: String, runway: String) -> bool:
	fn = f.get_node("Fdm")
	apt = airport
	ident = runway
	for r in f.airports.data.runways:
		if r.airport != airport:
			continue
		for i in 2:
			if str(r.ends[i].ident) == runway or (runway == "" and i == 0):
				thr = Vector2(r.ends[i].x, r.ends[i].y)
				hdg = float(r.ends[i].heading_true)
				length = float(r.length)
				width = float(r.width)
				ident = str(r.ends[i].ident)
				break
		if hdg != 0.0 or length > 0.0:
			break
	if length <= 0.0:
		return false
	fwd = Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg)))
	field_m = f.terrain.height_at(thr.x, thr.y)
	return true


func _gear_h() -> float:
	var law: Object = fn.fdm.fcs.law
	return float(law.s._gear_h) if law != null else 4.0


## Height (ft) of the 3 degree path above the field at `along` m.
static func path_ft(along: float) -> float:
	return (AIM_M - along) * tan(deg_to_rad(PATH_DEG)) / FT


func read(t: float) -> Dictionary:
	var p := fn.position_enu()
	var d := Vector2(p.x, p.y) - thr
	var along := d.dot(fwd)
	var cross := d.x * fwd.y - d.y * fwd.x
	var gs: float = Props.get_f("fdm/groundspeed_mps")
	var vs: float = Props.get_f("fdm/vs_mps")
	var law: Object = fn.fdm.fcs.law
	var ra := float(law.s.ra_ft) if law != null else Props.get_f("fdm/agl_m") / FT
	var hw := (p.z - _gear_h() - field_m) / FT  # wheel height above the field, ft
	var thr_lever := 0.0
	var n1 := 0.0
	var thrust := 0.0
	var rev := 0.0
	var units: Array = fn.fdm.units
	for u in units:
		thr_lever += float(u.engine.lever)
		n1 += float(u.engine.n1) * 100.0
		thrust += float(u.engine.thrust_n)
		rev = maxf(rev, float(u.engine.reverser_pos))
	var n := float(maxi(units.size(), 1))
	var comp: Dictionary = fn.fdm.gear.compression
	var sp: Array = Props.get_v("fdm/spoiler", [])
	var rates: Vector3 = Props.get_v("fdm/body_rates", Vector3.ZERO)
	_gs_hist.append([t, gs])
	while _gs_hist.size() > 1 and float(_gs_hist[0][0]) < t - 1.0:
		_gs_hist.pop_front()
	s = {"t": t, "dt": t - _prev_t, "ias": Props.get_f("fdm/cas_mps") / KT, "gs": gs / KT, "gs_mps": gs, "ra": ra, "hw": hw,
		"vs": vs / FT * 60.0, "gamma": rad_to_deg(atan2(vs, maxf(gs, 0.1))),
		"pitch": rad_to_deg(Props.get_f("fdm/pitch_rad")), "bank": rad_to_deg(Props.get_f("fdm/roll_rad")),
		"hdg": rad_to_deg(Props.get_f("fdm/heading_rad")), "trk": rad_to_deg(Props.get_f("fdm/track_rad")),
		"alpha": rad_to_deg(Props.get_f("fdm/alpha_rad")), "nz": Props.get_f("fdm/load_factor"),
		"wow": Props.get_b("fdm/wow"), "along": along, "cross": cross, "dev_ft": hw - path_ft(along),
		"lever": thr_lever / n, "n1": n1 / n, "thrust_kn": thrust / n / 1000.0, "rev": rev,
		"flap_deg": Props.get_f("fdm/flap_deg"), "spoil": (sp.max() if not sp.is_empty() else 0.0),
		"ab_on": Props.get_b("fdm/autobrake_on"), "mass": Props.get_f("fdm/mass_kg"),
		"nose": float(comp.get("NOSE_LG", 0.0)) > 0.0,
		"main": float(comp.get("LEFT_MLG", 0.0)) > 0.0 or float(comp.get("RIGHT_MLG", 0.0)) > 0.0,
		"q": rad_to_deg(rates.y), "p": rad_to_deg(rates.x), "r": rad_to_deg(rates.z),
		"vls": Props.get_f("instruments/pfd/vls_kt"), "alpha_prot": Props.get_f("fcs/alpha_prot_deg"), "alpha_max": Props.get_f("fcs/alpha_max_deg"),
		"crashed": Props.get_b("damage/crashed"), "decel": decel()}
	_prev_t = t
	return s


## Deceleration (m/s^2) over the last second of ground speed.
func decel() -> float:
	if _gs_hist.size() < 2:
		return 0.0
	var a: Array = _gs_hist[0]
	var b: Array = _gs_hist[_gs_hist.size() - 1]
	return (float(a[1]) - float(b[1])) / maxf(float(b[0]) - float(a[0]), 0.1)
