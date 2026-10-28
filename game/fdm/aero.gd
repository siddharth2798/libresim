class_name Aero
extends RefCounted
## Evaluates the JSBSim-derived aero model (aircraft/<id>/aero.json, built by
## tools/06_jsbsim_to_json.py). Expressions use JSBSim names and imperial units;
## this class converts in and out so the rest of the FDM stays SI.

const FT := 0.3048
const LBF := 4.4482216
const PSF := 47.880259
const SLUG_FT3 := 515.378818

var _functions: Array = []
var _axes: Dictionary = {}
var alpha_max := 0.28
var hyst_min := 0.09
var hyst_max := 0.36
var stall_hyst := 0.0
var ctx := {}  # JSBSim property name -> value, filled each step
var coeffs := {}  # last value of each named term (debug / instruments)
var _clsq := 0.0  # aero/cl-squared: JSBSim derives it from the lift of the previous evaluation

## Tests (and aircraft that opt in) set this: a property name the context does not hold is then an
## error (Expr.unknown + push_error) instead of silently 0.0, which the C172 keeps.
static var strict: bool:
	get:
		return Expr.strict
	set(v):
		Expr.strict = v


func _init(path: String, metrics: Dictionary) -> void:
	var a: Dictionary = Paths.load_res_json(path)
	_functions = a.functions
	_axes = a.axes
	if a.get("alpha_limits_rad") != null:  # the A320 FDE has none: defaults
		alpha_max = a.alpha_limits_rad.max
	if a.get("stall_hysteresis") != null:
		hyst_min = a.stall_hysteresis.min
		hyst_max = a.stall_hysteresis.max
	var props: Dictionary = a.get("properties", {})  # inputs nobody drives (ice/wingL ...): their defaults
	for k in props:
		ctx[k] = props[k]
	ctx["metrics/Sw-sqft"] = metrics.wing_area_m2 / (FT * FT)
	ctx["metrics/bw-ft"] = metrics.wingspan_m / FT
	ctx["metrics/cbarw-ft"] = metrics.chord_m / FT


## s: Dictionary of SI inputs (see FDM._aero_inputs); optional keys for jets: mach, temperature (K),
## ctx (JSBSim-named values from FlightControls.aero_ctx: surface final-deg, flap / slat / spoiler / gear
## position, landing-light drag inputs). Returns [force_wind_lbf
## (D, Y, L), moment_body_lbft (l, m, n)] in imperial; FDM converts.
func evaluate(s: Dictionary) -> Array:
	var v_fps: float = s.vt / FT
	var alpha: float = s.alpha
	if alpha > hyst_max:
		stall_hyst = 1.0
	elif alpha < hyst_min:
		stall_hyst = 0.0
	ctx["aero/alpha-rad"] = alpha
	ctx["aero/alphadot-rad_sec"] = s.alphadot
	ctx["aero/beta-rad"] = s.beta
	ctx["aero/mag-beta-rad"] = absf(s.beta)
	ctx["aero/qbar-psf"] = s.qbar / PSF
	ctx["aero/bi2vel"] = ctx["metrics/bw-ft"] / (2.0 * v_fps) if v_fps > 1.0 else 0.0
	ctx["aero/ci2vel"] = ctx["metrics/cbarw-ft"] / (2.0 * v_fps) if v_fps > 1.0 else 0.0
	ctx["aero/h_b-mac-ft"] = s.agl / (ctx["metrics/bw-ft"] * FT)
	ctx["aero/stall-hyst-norm"] = stall_hyst
	ctx["atmosphere/rho-slugs_ft3"] = s.rho / SLUG_FT3
	ctx["velocities/u-aero-fps"] = s.u / FT
	ctx["velocities/p-aero-rad_sec"] = s.p
	ctx["velocities/q-aero-rad_sec"] = s.q
	ctx["velocities/r-aero-rad_sec"] = s.r
	ctx["propulsion/engine/prop-induced-velocity_fps"] = s.v_induced / FT
	ctx["fcs/elevator-pos-rad"] = s.elevator
	ctx["fcs/mag-elevator-pos-rad"] = absf(s.elevator)
	ctx["fcs/left-aileron-pos-rad"] = s.aileron
	ctx["fcs/rudder-pos-rad"] = s.rudder
	ctx["fcs/flap-pos-deg"] = s.flap_deg
	ctx["aero/alpha-deg"] = rad_to_deg(alpha)
	ctx["aero/beta-deg"] = rad_to_deg(s.beta)
	ctx["aero/qbarUW-psf"] = ctx["aero/qbar-psf"] * cos(s.beta) * cos(s.beta)  # u and w only, no v
	ctx["aero/cl-squared"] = _clsq
	ctx["velocities/mach"] = s.get("mach", 0.0)
	ctx["aero/Re"] = _reynolds(s)
	var extra: Dictionary = s.get("ctx", {})
	if not extra.is_empty():
		ctx.merge(extra, true)
	for f in _functions:
		ctx[f.name] = Expr.eval(f.f, ctx)
	var sums := {}
	for axis in _axes:
		var total := 0.0
		for f in _axes[axis]:
			var v := Expr.eval(f.f, ctx)
			coeffs[f.name] = v
			total += v
		sums[axis] = total
	var q_s: float = ctx["aero/qbar-psf"] * ctx["metrics/Sw-sqft"]
	_clsq = pow(sums.LIFT / q_s, 2.0) if q_s > 1e-6 else 0.0
	return [Vector3(sums.DRAG, sums.SIDE, sums.LIFT), Vector3(sums.ROLL, sums.PITCH, sums.YAW)]


## Reynolds number on the mean chord: V * c / nu, Sutherland viscosity.
func _reynolds(s: Dictionary) -> float:
	var t: float = s.get("temperature", 288.15)
	var mu := 1.458e-6 * pow(t, 1.5) / (t + 110.4)  # Pa s
	return s.vt * ctx["metrics/cbarw-ft"] * FT * s.rho / mu
