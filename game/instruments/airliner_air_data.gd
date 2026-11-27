class_name AirlinerAirData
extends Node
## Air data computer of an airliner (ADR), in the units the PFD shows. Reads the FDM / atmosphere
## Props, publishes instruments/pfd/*:
##   ias_kt mach tas_kt trend_kt (speed in 10 s) vls_kt vsw_kt vmax_kt vfe_next_kt alt_ft (baro-corrected)
##   vfe_marks ([[kt, detent name], ...]: each flap detent's VFE, the red marks on the speed tape)
##   baro_hpa (the setting in use, 1013.25 in STD) baro_std vs_fpm ra_ft (radio altitude, -1 above 2500 ft)
##   valid (false with Props failures/adr: the PFD shows its red SPD / ALT / V/S flags)
## Inputs: fdm/{cas_mps, tas_mps, mach (optional), alt_m, vs_mps, agl_m, mass_kg, flap_deg, slat_deg,
## gear_pos}, atmosphere/{pressure_pa, temperature_k}; the pilot's setting: controls/baro/hpa (default
## weather/qnh_hpa) and controls/baro/std (bool). Speed limits: AirSpeeds with aircraft.json limits.speeds; its
## vfe_kt defaults to limits.vfe_kias when that is keyed by slat + flap (vfe_by "slat_flap"), so the PFD's Vmax and the
## damage model (fdm/damage.gd) use one table.

const TREND_TAU := 1.5  # s, acceleration filter
const RA_MAX_FT := 2500.0
const TICK_HZ := 30.0  # docs/USAGE.md "Tick rates"

var _tick := TickRate.new(TICK_HZ)

var _spec := {}
var _marks := []  # instruments/pfd/vfe_marks
var _prev_ias := NAN
var _accel := 0.0  # kt/s, filtered


func _ready() -> void:
	var def := AircraftDef.current()
	_spec = spec_for(def.section_or("limits", {}))
	var labels := []
	for d in def.config().get("controls", {}).get("flaps", {}).get("detents", []):
		labels.append(str(d.get("lever", "")) if d is Dictionary else str(d))
	_marks = AirSpeeds.vfe_marks(_spec, labels)


## AirSpeeds spec from aircraft.json "limits": its "speeds", with vfe_kt from vfe_kias when that is per detent.
static func spec_for(limits: Dictionary) -> Dictionary:
	var speeds: Dictionary = limits.get("speeds", {}).duplicate()
	if not speeds.has("vfe_kt") and str(limits.get("vfe_by", "")) == "slat_flap" and limits.has("vfe_kias"):
		speeds["vfe_kt"] = limits.vfe_kias
	return AirSpeeds.spec_of(speeds)


func _physics_process(dt: float) -> void:
	var h := _tick.step(dt)
	if h > 0.0:
		publish(h)


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
	var agl_ft := Units.m_to_ft(maxf(Props.get_f("fdm/agl_m", 1e5) - Props.get_f("fdm/wheel_depth_m", 0.0), 0.0))  # the wheels' height: 0 on the runway
	var gear: Variant = Props.get_v("fdm/gear_pos", 1.0)
	var gear_down: bool = (gear.min() if gear is Array and not gear.is_empty() else float(gear)) > 0.5
	var ext := Props.get_f("fdm/slat_deg") + Props.get_f("fdm/flap_deg")
	var lever := roundi(Props.get_f("fdm/flap_lever"))
	var mk := AirSpeeds.markers(_spec, Props.get_f("fdm/mass_kg", float(_spec.ref_mass_kg)), ext, gear_down, p)
	# The red band is the selected detent's Vfe at once, and stays at the surfaces' lower limit while they retract.
	var flap_limit := minf(AirSpeeds.vfe_selected(_spec, lever), AirSpeeds.table(_spec.vfe_kt, ext))
	Props.set_v("instruments/pfd/valid", ok)
	Props.set_v("instruments/pfd/ias_kt", ias if ok else 0.0)
	Props.set_v("instruments/pfd/mach", mach if ok else 0.0)
	Props.set_v("instruments/pfd/tas_kt", Units.mps_to_kt(tas) if ok else 0.0)
	Props.set_v("instruments/pfd/trend_kt", AirSpeeds.trend_kt(_accel) if ok else 0.0)
	Props.set_v("instruments/pfd/vls_kt", mk.vls)
	Props.set_v("instruments/pfd/vsw_kt", mk.vsw)
	Props.set_v("instruments/pfd/vmax_kt", AirSpeeds.envelope_max(_spec, flap_limit, gear_down, p))
	Props.set_v("instruments/pfd/vfe_next_kt", AirSpeeds.vfe_next(_spec, lever))
	Props.set_v("instruments/pfd/vfe_marks", _marks)
	Props.set_v("instruments/pfd/alt_ft", Units.m_to_ft(alt_m) if ok else 0.0)
	Props.set_v("instruments/pfd/baro_hpa", baro)
	Props.set_v("instruments/pfd/baro_std", std)
	Props.set_v("instruments/pfd/vs_fpm", Units.mps_to_fpm(Props.get_f("fdm/vs_mps")) if ok else 0.0)
	Props.set_v("instruments/pfd/ra_ft", agl_ft if agl_ft <= RA_MAX_FT else -1.0)
