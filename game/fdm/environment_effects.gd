class_name EnvironmentEffects
extends RefCounted
## What ice and rain do to the aircraft, applied from FdmNode each tick (no logic in fdm.gd): airframe
## ice raises drag, lowers the lift near the stall (CLmax) and brings the stall alpha down; heavy rain
## costs a little lift and adds a little drag; engine inlet ice and bleed air scale the power (piston) or
## thrust (turbine) and raise a turbine's EGT. Everything is neutral at level 0 (active = false: Aero and
## the engines then give exactly the clean-air numbers).
## The levels come from systems/icing.gd (Props icing/airframe, icing/engine_<n>, icing/bleed_penalty_<n>)
## and the local rain rate (environment/precip); the per-aircraft factors from aircraft.json "icing"
## (Icing.params). Aero.evaluate calls shape_forces(); update() / apply() set the engine fields.
## Effects at full airframe ice (C172 numbers): CD0 + 0.011 (about +35 %), lift near the stall x(1 - 0.22 - up
## to 0.09 past the stall alpha), stall alpha x0.89 (together about -26 % CLmax, +16 % stall speed), lift slope -3 %.

const RAIN_FROM := 0.6  # environment/precip above which rain affects the airframe
const SLOPE_K := 0.15  # lift-slope loss at full ice, as a fraction of clmax_k
const ALPHA_K := 0.5  # stall alpha loss at full ice, as a fraction of clmax_k
const POST_STALL_K := 0.4  # extra lift loss past the stall alpha, as a fraction of the CLmax loss

var active := false  # any effect non-neutral: Aero applies shape_forces
var cl_loss := 0.0  # uniform lift loss (fraction)
var stall_loss := 0.0  # extra lift loss near and beyond the stall alpha (fraction)
var alpha_max_scale := 1.0
var cd_add := 0.0  # drag coefficient added on the wing area
var rain := 0.0  # 0..1, the heavy-rain amount of the last apply()
var _p: Dictionary
var _alpha_max0 := -1.0  # the aircraft's own alpha_max, remembered at the first apply


func _init(params := {}) -> void:
	_p = Icing.DEFAULTS.duplicate(true)
	_p.merge(params, true)


## Force (D, Y, L) in lbf in wind axes with ice and rain applied. q_s = qbar * wing area (lbf).
func shape_forces(fw: Vector3, alpha: float, alpha_max: float, q_s: float) -> Vector3:
	var x := alpha / maxf(alpha_max, 0.05)
	var stall := stall_loss * smoothstep(0.5, 1.0, x) + POST_STALL_K * stall_loss * smoothstep(1.0, 1.3, x)
	fw.z *= (1.0 - cl_loss) * (1.0 - stall)
	fw.x += cd_add * q_s
	return fw


## Read the levels from Props and apply them to the FDM's aero and engines.
func update(f: FDM) -> void:
	var ice: Array = []
	var bleed: Array = []
	for i in f.units.size():
		ice.append(Props.get_f("icing/engine_%d" % (i + 1)))
		bleed.append(Props.get_f("icing/bleed_penalty_%d" % (i + 1)))
	apply(f, Props.get_f("icing/airframe"), Props.get_f("environment/precip"), ice, bleed)


## airframe: ice level 0..1; precip: local rain rate 0..1; engine_ice / bleed: per engine (0..1 / fraction).
func apply(f: FDM, airframe: float, precip: float, engine_ice := [], bleed := []) -> void:
	rain = smoothstep(RAIN_FROM, 1.0, precip)
	var k: float = _p.clmax_k * airframe
	cl_loss = _p.rain_cl_k * rain + SLOPE_K * k
	stall_loss = k
	alpha_max_scale = 1.0 - ALPHA_K * k
	cd_add = _p.drag_k * airframe + _p.rain_cd_k * rain
	active = cl_loss != 0.0 or stall_loss != 0.0 or cd_add != 0.0
	if _alpha_max0 < 0.0:
		_alpha_max0 = f.aero.alpha_max
	f.aero.alpha_max = _alpha_max0 * alpha_max_scale  # the stall warning follows
	f.aero.effects = self
	for i in f.units.size():
		var e := f.units[i].engine
		var eice: float = engine_ice[i] if i < engine_ice.size() else 0.0
		var b: float = bleed[i] if i < bleed.size() else 0.0
		e.power_scale = (1.0 - _p.power_loss_k * eice) * (1.0 - b)
		e.egt_add_k = _p.egt_k * eice
		e.n1_scale = 1.0 - _p.rain_n1_k * rain
