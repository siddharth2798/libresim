class_name Aero
extends RefCounted
## Evaluates the JSBSim-derived aero model (aircraft/c172/c172_aero.json, built by
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


func _init(path: String, metrics: Dictionary) -> void:
	var a: Dictionary = Paths.load_res_json(path)
	_functions = a.functions
	_axes = a.axes
	alpha_max = a.alpha_limits_rad.max
	hyst_min = a.stall_hysteresis.min
	hyst_max = a.stall_hysteresis.max
	ctx["metrics/Sw-sqft"] = metrics.wing_area_m2 / (FT * FT)
	ctx["metrics/bw-ft"] = metrics.wingspan_m / FT
	ctx["metrics/cbarw-ft"] = metrics.chord_m / FT


## s: Dictionary of SI inputs (see FDM._aero_inputs). Returns [force_wind_lbf
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
	for f in _functions:
		ctx[f.name] = _eval(f.f)
	var sums := {}
	for axis in _axes:
		var total := 0.0
		for f in _axes[axis]:
			var v := _eval(f.f)
			coeffs[f.name] = v
			total += v
		sums[axis] = total
	return [Vector3(sums.DRAG, sums.SIDE, sums.LIFT), Vector3(sums.ROLL, sums.PITCH, sums.YAW)]


func _eval(e: Variant) -> float:
	if e is float or e is int:
		return e
	if e.has("p"):
		return ctx.get(e.p, 0.0)
	if e.has("op"):
		var args: Array = e.args
		match e.op:
			"product":
				var r := 1.0
				for x in args:
					r *= _eval(x)
				return r
			"sum":
				var r := 0.0
				for x in args:
					r += _eval(x)
				return r
			"difference":
				return _eval(args[0]) - _eval(args[1])
			"quotient":
				return _eval(args[0]) / _eval(args[1])
			"abs":
				return absf(_eval(args[0]))
			"min":
				return minf(_eval(args[0]), _eval(args[1]))
			"max":
				return maxf(_eval(args[0]), _eval(args[1]))
	return Table.lookup(e.table, ctx)
