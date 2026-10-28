class_name IcingRates
extends RefCounted
## The numbers behind systems/icing.gd, as pure functions (rates are ice level per second, 0..1 scale).
## Supercooled liquid water exists in cloud between about +2 and -20 C static air temperature: most of it
## near -5 to -15 C, none (ice crystals) far below. Stratiform layers carry less liquid than cumulus, and
## storm cells more. Freezing rain / drizzle (precipitation below 0 C) is its own, fast source.

const BAND_TOP_C := 2.0  # warmest static temperature with any accretion
const BAND_BOTTOM_C := -20.0
const CLOUD_MIN := 0.05  # environment/ac_cloud_density above which the aircraft is in cloud
const AIRFRAME_S := 300.0  # seconds to full airframe ice in dense cumulus, availability 1, at 80 m/s
const FREEZING_RAIN_S := 120.0  # seconds to full ice in steady freezing rain
const LIQUID := {"stratiform": 0.4, "cumulus": 1.0, "storm": 1.5}  # liquid-water factor by cloud kind
const SUBLIMATION_S := 1800.0  # clear, cold air: ice goes away this slowly
const WARM_MELT_S := 150.0  # at +5 C and above
const HOT_MELT_S := 60.0  # at +15 C and above, on top of the above


## 0..1: how much supercooled liquid the air at static temperature t_c can hold.
static func temp_factor(t_c: float) -> float:
	if t_c > BAND_TOP_C or t_c < BAND_BOTTOM_C:
		return 0.0
	if t_c > 0.0:
		return 0.3 * (BAND_TOP_C - t_c) / BAND_TOP_C  # marginal just above freezing
	if t_c > -3.0:
		return lerpf(0.3, 1.0, -t_c / 3.0)
	if t_c >= -15.0:
		return 1.0
	return lerpf(1.0, 0.25, (-15.0 - t_c) / 5.0)


## Airspeed factor on the accretion rate (catch rate grows with speed, bounded).
static func speed_factor(tas_mps: float) -> float:
	return clampf(tas_mps / 80.0, 0.4, 1.8)


## Ice level per second in cloud: density 0..1, kind, availability (weather icing + storm), temperature, speed.
static func cloud_rate(density: float, kind: String, avail: float, t_c: float, tas_mps: float) -> float:
	if density <= CLOUD_MIN or avail <= 0.0:
		return 0.0
	return density * LIQUID.get(kind, LIQUID.stratiform) * avail * temp_factor(t_c) * speed_factor(tas_mps) / AIRFRAME_S


## Ice level per second in freezing rain: precip 0..1 (local rate), temperature.
static func freezing_rate(precip: float, t_c: float, tas_mps: float) -> float:
	if precip <= 0.02 or t_c >= 0.0 or t_c < -15.0:
		return 0.0
	return precip * minf(-t_c / 2.0, 1.0) * speed_factor(tas_mps) / FREEZING_RAIN_S


## Ice level lost per second: slow sublimation when not accreting, plus melting above freezing.
static func melt_rate(t_c: float, accreting: bool) -> float:
	var r := 0.0 if accreting else 1.0 / SUBLIMATION_S
	r += clampf(t_c / 5.0, 0.0, 1.0) / WARM_MELT_S
	r += clampf((t_c - 5.0) / 10.0, 0.0, 1.0) / HOT_MELT_S
	return r
