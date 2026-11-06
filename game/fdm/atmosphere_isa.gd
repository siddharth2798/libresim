class_name AtmosphereISA
extends RefCounted
## International Standard Atmosphere (troposphere) with temperature offset and
## sea-level pressure (QNH). Heights are geometric metres MSL (geopotential
## difference ignored below 4 km: < 0.1 %).

const T0 := 288.15
const P0 := 101325.0
const L := 0.0065
const R := 287.053
const G0 := 9.80665
const GAMMA := 1.4
const EXP := G0 / (R * L)  # 5.2559

var delta_t := 0.0     # K, ISA deviation (hot Pune afternoon ~ +15)
var humidity_k := 0.0  # virtual-temperature extra, applied to density only (not to the temperature icing reads)
var qnh_pa := P0       # sea-level pressure

# outputs of update()
var temperature := T0  # K
var pressure := P0     # Pa
var density := 1.225   # kg/m^3
var sound_speed := 340.294


func update(h: float) -> void:
	var t_std := T0 - L * h
	temperature = t_std + delta_t
	pressure = qnh_pa * pow(t_std / T0, EXP)
	density = pressure / (R * (temperature + maxf(humidity_k, 0.0)))
	sound_speed = sqrt(GAMMA * R * temperature)


## Pressure altitude (m) for a static pressure, standard datum.
static func pressure_altitude(p: float) -> float:
	return T0 / L * (1.0 - pow(p / P0, 1.0 / EXP))


## Indicated altitude for an altimeter set to kollsman_pa.
static func indicated_altitude(p: float, kollsman_pa: float) -> float:
	return T0 / L * (1.0 - pow(p / kollsman_pa, 1.0 / EXP))


## Virtual-temperature increment (K) from a dew point. 36/19 C at 1013 hPa is about +2.5 K.
static func virtual_extra_k(temp_c: float, dew_c: float, p_hpa: float) -> float:
	var e := minf(6.112 * exp(17.67 * dew_c / (dew_c + 243.5)), p_hpa * 0.5)
	var w := 0.622 * e / maxf(p_hpa - e, 1.0)
	return (temp_c + 273.15) * 0.608 * w


static func density_altitude(rho: float) -> float:
	return T0 / L * (1.0 - pow(rho / 1.225, 1.0 / (EXP - 1.0)))


## Calibrated airspeed from impact pressure (subsonic, compressible).
static func cas_from_qc(qc: float) -> float:
	return 340.294 * sqrt(5.0 * (pow(qc / P0 + 1.0, 2.0 / 7.0) - 1.0))
