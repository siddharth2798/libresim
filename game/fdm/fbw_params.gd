class_name FbwParams
extends RefCounted
## Parameters of the Airbus-style fly-by-wire law (aircraft.json "fcs", every key optional: only what
## differs from DEFAULTS needs spelling out; nested dictionaries merge key by key). Angles in degrees
## and speeds in knots here, because that is how the manuals quote them; the law converts to SI.
## Gains are "surface degrees per rad/s (or rad) of error" at the reference dynamic pressure Q_REF and
## scale with Q_REF / qbar (control effectiveness grows with q-bar). Tuned against tools/a320_reference.json.

const DEFAULTS := {
	"law": "airbus_fbw",
	"stick_deadzone": 0.02,
	"takeover": 0.1,  # sidestick deflection that disconnects the autopilot
	"q_ref_pa": 10000.0,  # about 250 kt CAS at sea level
	"sched_min": 0.35, "sched_max": 3.5,
	"nz_max": 2.5, "nz_max_flaps": 2.0, "nz_min": -1.0, "nz_min_flaps": 0.0,
	"pitch_limit_deg": [-15.0, 30.0],
	"vmo_kt": 350.0, "mmo": 0.82,
	"ground_blend_s": 1.0,  # ground <-> flight blend at liftoff / touchdown
	"ground_gain": [[0.0, 1.0], [60.0, 1.0], [140.0, 0.6], [220.0, 0.4]],  # direct elevator vs CAS (kt) while rolling
	"flare": {"ra_ft": 50.0, "full_ft": 15.0, "bias_g": 0.10, "max_lever": 0.35},
	"pitch": {"kn": 2.0, "ki": 0.0, "kq": 80.0, "kiq": 120.0, "q_max_dps": 12.0, "trim_k": 6.0, "trim_dead_deg": 0.05,
		"k_alpha": 2.5, "alpha_lead_s": 0.5, "k_theta": 1.2},
	"roll": {"rate_dps": 15.0, "kp": 55.0, "ki": 60.0, "kff": 40.0, "k_bank": 1.6, "hold_deg": 33.0, "limit_deg": 67.0,
		"limit_prot_deg": 45.0, "taper_deg": 5.0, "level_deg": 2.5, "spoiler_start": 0.3, "spoiler_max_deg": 35.0},
	"yaw": {"k_r": 25.0, "k_beta": 40.0, "limit_deg": 8.0, "travel_kt": [[0.0, 25.0], [160.0, 25.0], [380.0, 3.4]]},
	"alpha_deg": {  # per configuration (slat, flap deg): protection, max and stall angle of attack, JSBSim A320
		"rows": [[0.0, 0.0, 8.6, 11.56, 13.84], [18.0, 0.0, 11.5, 13.74, 14.24], [18.0, 10.0, 11.3, 13.8, 14.4],
			[22.0, 15.0, 11.0, 13.89, 14.79], [22.0, 20.0, 11.0, 14.07, 15.0], [27.0, 35.0, 10.5, 14.08, 15.01]],
		"floor_frac": 0.5, "warn_frac": 0.35, "lag_s": 1.0},
	"speed_prot": {"above_vmo_kt": 6.0, "above_mmo": 0.01, "mach_kt": 600.0, "bias_g_per_kt": 0.05, "bias_max_g": 0.5, "fade_kt": 12.0},
}

var d: Dictionary


## The parameters of an aircraft: DEFAULTS under its aircraft.json "fcs" section, speed limits from "limits".
static func from_def(def: AircraftDef) -> FbwParams:
	var p := FbwParams.new()
	p.d = DEFAULTS.duplicate(true)
	_merge(p.d, def.section("fcs"))
	var lim: Dictionary = def.section("limits")
	var sp: Dictionary = lim.get("speeds", {})
	var own: Dictionary = def.section("fcs")
	if not own.has("vmo_kt"):
		p.d.vmo_kt = float(sp.get("vmo_kt", lim.get("vne_kias", p.d.vmo_kt)))
	if not own.has("mmo"):
		p.d.mmo = float(sp.get("mmo", p.d.mmo))
	return p


static func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if dst.get(k) is Dictionary and src[k] is Dictionary:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]


func f(key: String) -> float:
	return float(d[key])


## Piecewise linear table [[x, y], ...] (sorted by x), clamped at both ends.
static func interp(tab: Array, x: float) -> float:
	if x <= float(tab[0][0]):
		return float(tab[0][1])
	for i in range(1, tab.size()):
		if x <= float(tab[i][0]):
			var x0: float = tab[i - 1][0]
			var y0: float = tab[i - 1][1]
			return y0 + (float(tab[i][1]) - y0) * (x - x0) / (float(tab[i][0]) - x0)
	return float(tab[-1][1])
