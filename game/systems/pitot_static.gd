class_name PitotStatic
extends Node
## Pitot-static system: pitot (total) and static pressures seen by the
## instruments, with position error and failure modes:
##   failures/pitot_blocked  - pitot + drain blocked: pitot pressure frozen (ASI acts as altimeter)
##   failures/static_blocked - static port blocked: static pressure frozen
##   systems/alternate_static - cabin static source: reads ~ -0.1 inHg low (higher alt/IAS)
## Publishes systems/pitot_static/{pitot_pa, static_pa}.

const ALT_STATIC_DP := -0.1 * 3386.389  # cabin pressure slightly below ambient

## Airspeed calibration (flaps up): KCAS -> KIAS correction (kt), by KCAS. Comes from the aircraft's
## aircraft.json "systems.pitot_static": {"pos_err_kcas": [...], "pos_err_dkt": [...]} (C172S POH);
## without it there is no position error.
var _err_kcas: Array = []
var _err_dkt: Array = []
var _loaded := false

var _pitot_frozen := 0.0
var _static_frozen := 0.0


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)


func _load_def() -> void:
	_loaded = true
	var ps: Dictionary = AircraftDef.current().section("systems").get("pitot_static", {})
	_err_kcas = ps.get("pos_err_kcas", [])
	_err_dkt = ps.get("pos_err_dkt", [])


## Saved with a flight situation (core/situation_systems.gd).
func save_key() -> String:
	return "pitot_static"


func save_state() -> Dictionary:
	return {"pitot_frozen": _pitot_frozen, "static_frozen": _static_frozen}


func load_state(d: Dictionary) -> void:
	_pitot_frozen = float(d.get("pitot_frozen", _pitot_frozen))
	_static_frozen = float(d.get("static_frozen", _static_frozen))


func _physics_process(_dt: float) -> void:
	if not _loaded:
		_load_def()
	var p := Props.get_f("atmosphere/pressure_pa", 101325.0)
	var cas := Props.get_f("fdm/cas_mps")
	var tas := Props.get_f("fdm/tas_mps")
	var alpha := absf(Props.get_f("fdm/alpha_rad"))
	# Indicated (instrument) airspeed incl. position error, converted back to impact pressure.
	var kcas := cas / Units.KT
	var dkt := _interp(kcas, _err_kcas, _err_dkt) if kcas > 20.0 and not _err_kcas.is_empty() else 0.0
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
