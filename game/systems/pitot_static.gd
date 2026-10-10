class_name PitotStatic
extends Node
## Pitot-static system: pitot (total) and static pressures seen by the
## instruments, with C172S position error and failure modes:
##   failures/pitot_blocked  - pitot + drain blocked: pitot pressure frozen (ASI acts as altimeter)
##   failures/static_blocked - static port blocked: static pressure frozen
##   systems/alternate_static - cabin static source: reads ~ -0.1 inHg low (higher alt/IAS)
## Publishes systems/pitot_static/{pitot_pa, static_pa}.

const ALT_STATIC_DP := -0.1 * 3386.389  # cabin pressure slightly below ambient

## C172S POH airspeed calibration (flaps up): KCAS -> KIAS correction (kt), by KCAS
const POS_ERR_KCAS := [50.0, 60.0, 70.0, 80.0, 100.0, 120.0, 140.0, 160.0]
const POS_ERR_DKT := [-6.0, -3.0, -1.0, 0.0, 1.0, 1.0, 1.0, 1.0]

var _pitot_frozen := 0.0
var _static_frozen := 0.0


func _physics_process(_dt: float) -> void:
	var p := Props.get_f("atmosphere/pressure_pa", 101325.0)
	var cas := Props.get_f("fdm/cas_mps")
	var tas := Props.get_f("fdm/tas_mps")
	var alpha := absf(Props.get_f("fdm/alpha_rad"))
	# Indicated (instrument) airspeed incl. position error, converted back to impact pressure.
	var kcas := cas / Units.KT
	var dkt := _interp(kcas, POS_ERR_KCAS, POS_ERR_DKT) if kcas > 20.0 else 0.0
	var ias := maxf(cas + dkt * Units.KT, 0.0)
	# pitot loses pressure at large angles of attack / sideslip (cos^2 law, crude)
	ias *= clampf(cos(alpha) ** 2, 0.0, 1.0)
	var qc := _qc_from_cas(ias)
	var stat := p + (ALT_STATIC_DP if Props.get_b("systems/alternate_static") else 0.0)
	if Props.get_b("failures/static_blocked"):
		if _static_frozen == 0.0:
			_static_frozen = stat
		stat = _static_frozen
	else:
		_static_frozen = 0.0
	var pitot := p + qc
	if Props.get_b("failures/pitot_blocked"):
		if _pitot_frozen == 0.0:
			_pitot_frozen = pitot
		pitot = _pitot_frozen
	else:
		_pitot_frozen = 0.0
	Props.set_v("systems/pitot_static/pitot_pa", pitot)
	Props.set_v("systems/pitot_static/static_pa", stat)
	Props.set_v("systems/pitot_static/oat_k", Props.get_f("atmosphere/temperature_k", 288.15) + 0.5 * tas * tas / 1005.0 * 0.8)


static func _qc_from_cas(cas: float) -> float:
	var m := cas / 340.294
	return 101325.0 * (pow(1.0 + 0.2 * m * m, 3.5) - 1.0)


static func _interp(x: float, xs: Array, ys: Array) -> float:
	if x <= xs[0]:
		return ys[0]
	for i in range(1, xs.size()):
		if x <= xs[i]:
			return lerpf(ys[i - 1], ys[i], (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
	return ys[-1]
