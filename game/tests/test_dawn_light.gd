extends RefCounted
## Dawn and dusk light (world/dawn_light.gd and its users SkyTime, NightSky, Atmosphere, the sky shader): a low sun is
## dim, the night exposure lift ends at sunrise, the auto exposure does not brighten a dawn back to day, stars and lit
## cirrus follow the sun. Midday (sun 58 deg, 12:20 IST on day 45) and night (below -12 deg) stay as they were.
## Before this fix sunrise was shown with exposure 1.67 (night lift 1.26 x auto exposure 1.33) against 1.0 at noon.


## Highest total exposure the scene can get: NightSky's lift x the auto-exposure ceiling.
static func _exposure_ceiling(el: float) -> float:
	return lerpf(1.0, NightSky.NIGHT_EXPOSURE, DawnLight.night_weight(el)) * DawnLight.ae_max(el)


func test_low_sun_is_dim() -> String:
	# clear-sky direct sun relative to high sun: ~3 % at 1 deg, ~25 % at 5, ~50 % at 10 (it was 17 %, 50 %, 92 %)
	var hi := DawnLight.sun_energy(60.0)
	for c in [[1.0, 0.0, 0.05], [5.0, 0.18, 0.32], [10.0, 0.42, 0.6], [20.0, 0.7, 0.85]]:
		var r := DawnLight.sun_energy(c[0]) / hi
		if r < c[1] or r > c[2]:
			return "sun at %d deg should give %.2f..%.2f of high-sun light, got %.3f" % [int(c[0]), c[1], c[2], r]
	var prev := 0.0
	for el in [-2.0, -1.0, 0.0, 1.0, 2.0, 4.0, 8.0, 15.0, 30.0, 45.0, 70.0]:
		var e := DawnLight.sun_energy(el)
		if e < prev:
			return "sun energy must not fall as the sun rises (%.1f deg)" % el
		prev = e
	return "" if DawnLight.sun_energy(-1.0) == 0.0 else "no direct sun once the disc has set"


func test_exposure_is_not_lifted_at_dawn() -> String:
	if DawnLight.night_weight(0.0) != 0.0 or DawnLight.night_weight(5.0) != 0.0:
		return "the night exposure lift must be gone by sunrise"
	var rise := _exposure_ceiling(0.0)
	var after := _exposure_ceiling(4.0)
	if rise > 1.3 or after > 1.3:
		return "sunrise / +4 deg may be exposed at most 1.3x (was 1.67 / 1.6), got %.2f / %.2f" % [rise, after]
	# from night to sunrise the exposure only falls: the eye leaves night vision as the sky brightens
	var prev := INF
	for el in [-14.0, -11.0, -9.0, -7.0, -5.0, -3.0, -1.0, 0.0]:
		var c := _exposure_ceiling(el)
		if c > prev + 1e-6:
			return "exposure ceiling rose at %.0f deg (%.2f after %.2f)" % [el, c, prev]
		prev = c
	return ""


func test_twilight_sky_and_stars_fade_with_the_sun() -> String:
	if Atmosphere.twilight_gain(-6.0) > 0.2:
		return "civil-twilight sky should be at most 0.2 of the sunrise sky (was 0.3), got %.2f" % Atmosphere.twilight_gain(-6.0)
	if DawnLight.star_weight(0.0) != 0.0 or DawnLight.star_weight(-3.0) != 0.0:
		return "no stars at or just before sunrise"
	if DawnLight.star_weight(-7.0) >= DawnLight.star_weight(-10.0):
		return "stars should come out as the sun sinks"
	if DawnLight.cirrus_light(-7.0) > 0.05 or DawnLight.cirrus_light(0.0) > 0.3:
		return "cirrus before the sun reaches them should not glow (%.2f at -7, %.2f at 0)" % [
			DawnLight.cirrus_light(-7.0), DawnLight.cirrus_light(0.0)]
	return ""


func test_midday_and_night_unchanged() -> String:
	for el in [45.0, 58.0, 85.0]:
		if not is_equal_approx(DawnLight.sun_energy(el), DawnLight.SUN_NOON) or DawnLight.night_weight(el) != 0.0:
			return "midday sun / exposure changed at %d deg" % int(el)
		if DawnLight.ae_max(el) != AutoExposure.MAX or not is_equal_approx(DawnLight.cirrus_light(el), 1.0):
			return "midday auto exposure ceiling or cirrus changed at %d deg" % int(el)
	for el in [-12.0, -20.0, -60.0]:
		if DawnLight.night_weight(el) != 1.0 or DawnLight.star_weight(el) != 1.0 or DawnLight.sun_energy(el) != 0.0:
			return "night changed at %d deg" % int(el)
		if not is_equal_approx(DawnLight.ae_max(el), AutoExposure.MAX_NIGHT):
			return "night auto exposure ceiling changed at %d deg" % int(el)
	# the cap never lowers a clear noon's own target, and keeps the old night cap
	var noon := AutoExposure.scene_luminance(1.3, 0.85, 0.0, 0.7, 0.38, 0.0)
	if AutoExposure.target_for(noon, 0.0, DawnLight.ae_max(58.0)) != AutoExposure.target_for(noon):
		return "noon auto exposure changed"
	return ""


## The scene code reads these curves (a structure check: the renderer cannot run here).
func test_scene_uses_the_dawn_curves() -> String:
	var st := FileAccess.get_file_as_string("res://world/sky_time.gd")
	var ns := FileAccess.get_file_as_string("res://world/night_sky.gd")
	var sh := FileAccess.get_file_as_string("res://world/sky_clouds.gdshader")
	if not st.contains("DawnLight.sun_energy(el_deg)") or not st.contains("DawnLight.ae_max(el_deg)"):
		return "SkyTime does not take the sun energy / exposure ceiling from DawnLight"
	if not st.contains("stage(\"cirrus_light\", DawnLight.cirrus_light(el_deg))"):
		return "SkyTime does not stage cirrus_light"
	if not ns.contains("DawnLight.night_weight(sun_el)") or not ns.contains("DawnLight.star_weight(sun_el)"):
		return "NightSky does not take the exposure lift / stars from the sun elevation"
	if not sh.contains("uniform float cirrus_light") or sh.contains("(0.04 + 0.96 * day)"):
		return "the sky shader still lights cirrus by `day`"
	return ""
