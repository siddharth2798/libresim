class_name AutoExposure
extends RefCounted
## Eye-like auto exposure for the Mobile renderer (CameraAttributes auto exposure is Forward+ only).
## An estimate of how bright the view is (sunlit or shaded ground, sky, where the camera looks) goes
## through a gentle power law to an exposure multiplier, smoothed with an eye-like time constant:
## it brightens slowly when the scene gets dark (2.4 s) and darkens faster when it gets bright (0.9 s).
## SkyTime multiplies the result into Environment.tonemap_exposure after NightSky's night boost and
## before the sun-glare pull, so the three stack instead of fighting. Off (value eases to 1) on Low.

const REF_LUM := 0.30  # estimated luminance of a clear noon with a level view: multiplier 1
const STRENGTH := 0.3  # 0 = fixed exposure, 1 = full normalisation (the eye does not normalise fully)
const MIN := 0.8
const MAX := 1.5
const MAX_NIGHT := 1.2  # NightSky already lifts the exposure by 45 % at night: little extra headroom then
const T_BRIGHTEN := 2.4  # s, adapting to a darker scene
const T_DARKEN := 0.9  # s, adapting to a brighter scene

var value := 1.0
var _started := false


## Rough luminance of the view. sun_e: direct light energy on the ground (already dimmed by cloud
## cover), sun_up: sin of the sun elevation, blocked: 0..1 how much a cloud over the aircraft shades the
## sun, ambient_e: ambient energy, sky_lum: mean sky luminance, pitch_sin: sin of the camera pitch.
static func scene_luminance(sun_e: float, sun_up: float, blocked: float, ambient_e: float, sky_lum: float, pitch_sin: float) -> float:
	var ground_e := sun_e * maxf(sun_up, 0.0) * (1.0 - 0.85 * clampf(blocked, 0.0, 1.0)) + ambient_e * 0.5
	var sky_frac := clampf(0.5 + 0.6 * pitch_sin, 0.1, 0.9)  # looking up fills the view with sky
	return maxf(lerpf(0.2 * ground_e, sky_lum, sky_frac), 1e-4)


## Exposure multiplier the eye would settle on for a luminance. night: 0 day .. 1 night.
static func target_for(lum: float, night := 0.0) -> float:
	return clampf(pow(REF_LUM / lum, STRENGTH), MIN, lerpf(MAX, MAX_NIGHT, clampf(night, 0.0, 1.0)))


## Advance by dt towards `target` (1.0 when switched off). The first call jumps there.
func step(dt: float, target: float) -> float:
	if not _started:
		_started = true
		value = target
		return value
	var tau := T_BRIGHTEN if target > value else T_DARKEN
	value = exp(lerpf(log(value), log(target), 1.0 - exp(-dt / tau)))
	return value
