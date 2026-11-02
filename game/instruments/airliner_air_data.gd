class_name AirlinerAirData
extends Node
## Air data computer of an airliner (ADR), in the units the PFD shows. Reads the FDM / atmosphere
## Props, publishes instruments/pfd/*:
##   ias_kt mach tas_kt trend_kt (speed in 10 s) vls_kt vsw_kt vmax_kt alt_ft (baro-corrected)
##   baro_hpa (the setting in use, 1013.25 in STD) baro_std vs_fpm ra_ft (radio altitude, -1 above 2500 ft)
##   valid (false with Props failures/adr: the PFD shows its red SPD / ALT / V/S flags)
## Inputs: fdm/{cas_mps, tas_mps, mach (optional), alt_m, vs_mps, agl_m, mass_kg, flap_deg, slat_deg,
## gear_pos}, atmosphere/{pressure_pa, temperature_k}; the pilot's setting: controls/baro/hpa (default
## weather/qnh_hpa) and controls/baro/std (bool). Speed limits: AirSpeeds with aircraft.json limits.speeds.

const TREND_TAU := 1.5  # s, acceleration filter
const RA_MAX_FT := 2500.0

var _spec := {}
var _prev_ias := NAN
var _accel := 0.0  # kt/s, filtered


func _ready() -> void:
	_spec = AirSpeeds.spec_of(AircraftDef.current().section_or("limits", {}).get("speeds", {}))


func _physics_process(dt: float) -> void:
	publish(dt)


func publish(dt: float) -> void:
	if _spec.is_empty():
		_spec = AirSpeeds.spec_of({})
	var ok := not Props.get_b("failures/adr")
	var ias := Units.mps_to_kt(Props.get_f("fdm/cas_mps"))
	var tas := Props.get_f("fdm/tas_mps")
	var p := Props.get_f("atmosphere/pressure_pa", 101325.0)
	var temp := Props.get_f("atmosphere/temperature_k", 288.15)
	var mach: float = Props.get_f("fdm/mach", tas / sqrt(1.4 * 287.05 * temp))
	if not is_nan(_prev_ias) and dt > 0.0:
		_accel = lerpf(_accel, (ias - _prev_ias) / dt, clampf(dt / TREND_TAU, 0.0, 1.0))
	_prev_ias = ias
	var std := Props.get_b("controls/baro/std")
	var qnh: float = Props.get_f("controls/baro/hpa", Props.get_f("weather/qnh_hpa", 1013.25))
	var baro := 1013.25 if std else qnh
	var alt_m := AtmosphereISA.indicated_altitude(p, baro * Units.HPA) if Props.has("atmosphere/pressure_pa") else Props.get_f("fdm/alt_m")
	var agl_ft := Units.m_to_ft(Props.get_f("fdm/agl_m", 1e5))
	var gear: Variant = Props.get_v("fdm/gear_pos", 1.0)
	var gear_down: bool = (gear.min() if gear is Array and not gear.is_empty() else float(gear)) > 0.5
	var ext := Props.get_f("fdm/slat_deg") + Props.get_f("fdm/flap_deg")
	var mk := AirSpeeds.markers(_spec, Props.get_f("fdm/mass_kg", float(_spec.ref_mass_kg)), ext, gear_down, p)
	Props.set_v("instruments/pfd/valid", ok)
	Props.set_v("instruments/pfd/ias_kt", ias if ok else 0.0)
	Props.set_v("instruments/pfd/mach", mach if ok else 0.0)
	Props.set_v("instruments/pfd/tas_kt", Units.mps_to_kt(tas) if ok else 0.0)
	Props.set_v("instruments/pfd/trend_kt", AirSpeeds.trend_kt(_accel) if ok else 0.0)
	Props.set_v("instruments/pfd/vls_kt", mk.vls)
	Props.set_v("instruments/pfd/vsw_kt", mk.vsw)
	Props.set_v("instruments/pfd/vmax_kt", mk.vmax)
	Props.set_v("instruments/pfd/alt_ft", Units.m_to_ft(alt_m) if ok else 0.0)
	Props.set_v("instruments/pfd/baro_hpa", baro)
	Props.set_v("instruments/pfd/baro_std", std)
	Props.set_v("instruments/pfd/vs_fpm", Units.mps_to_fpm(Props.get_f("fdm/vs_mps")) if ok else 0.0)
	Props.set_v("instruments/pfd/ra_ft", agl_ft if agl_ft <= RA_MAX_FT else -1.0)
