class_name DawnLight
extends RefCounted
## How the light and the eye's adaptation follow the sun elevation (deg) through dawn and dusk. Pure functions, used by
## SkyTime (sun energy, auto-exposure ceiling, cirrus light) and NightSky (night exposure lift, stars).
## Real dawn, clear tropical air: direct sun is ~3 % of its high-sun strength at 1 deg, 25 % at 5, half at 10 (air mass);
## the ground gets ~700 lux at sunrise and ~3 lux at -6 deg against ~100 000 at noon. The eye adapts to night and to shade,
## but not to a low sun: a dawn scene looks dimmer than day. So the night exposure lift ends at sunrise (not at +8 deg as
## when it followed SkyTime's `day`), and the auto exposure may brighten a low-sun scene only a little.
## Above SUN_REF_EL nothing here differs from before, so midday is unchanged; below -11 deg night is unchanged.

const SUN_NOON := 1.3  # DirectionalLight energy with the sun high
const SUN_K := 0.147  # broadband extinction per air mass: 25 % of high-sun direct light at 5 deg, 51 % at 10, 76 % at 20
const SUN_REF_EL := 45.0  # transmission normalised here; from it up the energy is SUN_NOON
const NIGHT_FROM_EL := -1.0  # the night exposure lift starts as the sun sinks below this ...
const NIGHT_FULL_EL := -11.0  # ... and is complete here (dark-adapted eye)
const STARS_FROM_EL := -3.0  # the brightest stars appear (dawn: the last ones fade)
const STARS_FULL_EL := -11.0
const AE_DAWN := 1.25  # auto-exposure ceiling with the sun on the horizon (AutoExposure.MAX 1.5 by day, MAX_NIGHT at night)
const AE_DAY_FROM_EL := 3.0  # the ceiling rises from AE_DAWN here to AutoExposure.MAX at AE_DAY_FULL_EL
const AE_DAY_FULL_EL := 20.0
const CIRRUS_LEAD_DEG := 3.0  # cirrus (~9 km up) see the sun about 3 deg before the ground does


## Relative air mass (Kasten & Young 1989); 1 overhead, ~38 at the horizon.
static func air_mass(el_deg: float) -> float:
	var e := maxf(el_deg, 0.0)
	return 1.0 / (sin(deg_to_rad(e)) + 0.50572 * pow(e + 6.07995, -1.6364))


## Direct sun light energy: SUN_NOON high up, dimmed by the air mass near the horizon, gone once the disc is below it.
static func sun_energy(el_deg: float) -> float:
	var t := exp(-SUN_K * (air_mass(el_deg) - air_mass(SUN_REF_EL)))
	return SUN_NOON * minf(t, 1.0) * clampf((el_deg + 1.0) / 1.5, 0.0, 1.0)


## 0 day .. 1 night: weight of NightSky's exposure lift. 0 from sunrise up.
static func night_weight(el_deg: float) -> float:
	return smoothstep(NIGHT_FROM_EL, NIGHT_FULL_EL, el_deg)


## 0 .. 1 star visibility from the sun alone (NightSky squares it, then applies cloud and moonlight).
static func star_weight(el_deg: float) -> float:
	return smoothstep(STARS_FROM_EL, STARS_FULL_EL, el_deg)


## Highest auto-exposure multiplier the eye may reach at this sun elevation.
static func ae_max(el_deg: float) -> float:
	var day_max := lerpf(AE_DAWN, AutoExposure.MAX, smoothstep(AE_DAY_FROM_EL, AE_DAY_FULL_EL, el_deg))
	return lerpf(day_max, AutoExposure.MAX_NIGHT, night_weight(el_deg))


## Brightness of sunlit cirrus (sky shader uniform cirrus_light): 1 by day, 0.04 (sky light only) once the sun has set
## for the cirrus layer too; follows the sun energy the layer gets, not SkyTime's `day`.
static func cirrus_light(el_deg: float) -> float:
	return 0.04 + 0.96 * sun_energy(el_deg + CIRRUS_LEAD_DEG) / SUN_NOON
