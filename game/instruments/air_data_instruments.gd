class_name AirDataInstruments
extends Node
## Pressure instruments fed by the pitot-static system:
##   ASI  (kt)  from pitot - static, small needle lag
##   Altimeter (ft) from static pressure and the Kollsman setting, ~0.3 s lag
##   VSI (fpm) from the rate of change of static pressure, with the diaphragm/
##        calibrated-leak lag (~6 s to settle)
## Kollsman knob: Props "instruments/altimeter/kollsman_inhg" (UI writes it).

const VSI_TAU := 2.0  # s, first-order; ~6 s to 95 %
const ALT_TAU := 0.3
const ASI_TAU := 0.15

var _alt := 0.0
var _vsi := 0.0
var _asi := 0.0
var _prev_palt := NAN


func _ready() -> void:
	if not Props.has("instruments/altimeter/kollsman_inhg"):
		Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)


func _physics_process(dt: float) -> void:
	var pitot := Props.get_f("systems/pitot_static/pitot_pa", 101325.0)
	var stat := Props.get_f("systems/pitot_static/static_pa", 101325.0)
	var qc := maxf(pitot - stat, 0.0)
	var ias_kt := Units.mps_to_kt(AtmosphereISA.cas_from_qc(qc))
	_asi = lerpf(_asi, ias_kt, clampf(dt / ASI_TAU, 0.0, 1.0))

	var kollsman := Props.get_f("instruments/altimeter/kollsman_inhg") * Units.INHG
	var alt_ft := Units.m_to_ft(AtmosphereISA.indicated_altitude(stat, kollsman))
	if is_nan(_prev_palt):
		_alt = alt_ft
		_prev_palt = alt_ft
	_alt = lerpf(_alt, alt_ft, clampf(dt / ALT_TAU, 0.0, 1.0))
	var rate := (alt_ft - _prev_palt) / dt * 60.0  # fpm
	_prev_palt = alt_ft
	_vsi = lerpf(_vsi, rate, clampf(dt / VSI_TAU, 0.0, 1.0))

	Props.set_v("instruments/asi_kt", _asi)
	Props.set_v("instruments/altimeter_ft", _alt)
	Props.set_v("instruments/vsi_fpm", clampf(_vsi, -2000.0, 2000.0))
