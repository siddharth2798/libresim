extends RefCounted
## Analytic sky (world/atmosphere.gd): colour against sun elevation, the sun's own colour, the
## twilight fade, and that the sky shader and SkyTime's haze colour come from the same model.


static func _sun(el_deg: float) -> Vector3:
	return Vector3(0.0, sin(deg_to_rad(el_deg)), -cos(deg_to_rad(el_deg)))


static func _sky(dir: Vector3, el_deg: float) -> Color:
	return Atmosphere.sky(dir.normalized(), _sun(el_deg), 1.0, Atmosphere.twilight_gain(el_deg))


func test_noon_sky_is_blue_overhead_and_paler_at_the_horizon() -> String:
	var zen := _sky(Vector3.UP, 60.0)
	var hor := _sky(Vector3(0.0, 0.02, 1.0), 60.0)  # away from the sun
	if not (zen.b > 2.5 * zen.r and zen.b > 1.3 * zen.g):
		return "zenith should be a deep blue, got %s" % zen
	var zen_sat := (zen.b - zen.r) / zen.b
	var hor_sat := (hor.b - hor.r) / hor.b
	if hor_sat >= zen_sat - 0.15:
		return "horizon should be paler than the zenith (%.2f vs %.2f)" % [hor_sat, zen_sat]
	if hor.get_luminance() <= zen.get_luminance():
		return "horizon should be brighter than the zenith"
	return ""


func test_low_sun_is_orange_near_the_sun_and_blue_opposite() -> String:
	var near := _sky(Vector3(0.0, 0.02, -1.0), 3.0)  # towards the sun
	var away := _sky(Vector3(0.0, 0.02, 1.0), 3.0)
	if not (near.r > near.g and near.g > near.b and near.r > 2.0 * near.b):
		return "sunset glow should be orange-red, got %s" % near
	if away.b / maxf(away.r, 1e-4) <= near.b / maxf(near.r, 1e-4):
		return "the anti-solar horizon should be bluer than the sun side"
	var noon := _sky(Vector3(0.0, 0.02, -1.0), 60.0)
	if near.r / near.b <= 2.0 * noon.r / noon.b:
		return "low sun should redden the horizon far more than a high sun"
	return ""


func test_sun_colour_reddens_towards_the_horizon() -> String:
	var prev := 2.0
	for el in [60.0, 30.0, 15.0, 8.0, 3.0, 1.0, 0.0]:
		var c := Atmosphere.sun_color(el)
		var ratio := c.b / c.r
		if ratio > prev + 1e-4:
			return "sun colour should redden monotonically (b/r %.2f at %d deg after %.2f)" % [ratio, int(el), prev]
		prev = ratio
	var hi := Atmosphere.sun_color(60.0)
	var lo := Atmosphere.sun_color(2.0)
	if hi.b < 0.8 or hi.r < 0.99:
		return "high sun should be near white: %s" % hi
	if lo.g > 0.65 or lo.b > 0.3:
		return "sun at 2 deg should be orange: %s" % lo
	return ""


func test_twilight_gain_fades_to_night() -> String:
	if Atmosphere.twilight_gain(10.0) != 1.0 or Atmosphere.twilight_gain(0.0) != 1.0:
		return "gain must be 1 with the sun up"
	var prev := 1.0
	for el in [-1.0, -3.0, -6.0, -9.0, -12.0]:
		var g := Atmosphere.twilight_gain(el)
		if g > prev:
			return "twilight gain must not rise as the sun sinks (%d deg)" % int(el)
		prev = g
	if Atmosphere.twilight_gain(-12.0) > 1e-4:
		return "no model light left at -12 deg"
	# below the horizon the sky is still lit (sun on the horizon) and not NaN
	var c := _sky(Vector3(0.3, 0.3, -1.0), -3.0)
	if is_nan(c.r) or c.get_luminance() <= 0.0:
		return "civil twilight sky should be lit, got %s" % c
	return ""


func test_aerosol_follows_visibility() -> String:
	var a := Atmosphere.aerosol_for_visibility(40000.0)
	var b := Atmosphere.aerosol_for_visibility(8000.0)
	var c := Atmosphere.aerosol_for_visibility(1000.0)
	if not (a < b and b < c and c <= 10.0 and a >= 0.5):
		return "aerosol should grow as visibility drops: %.2f %.2f %.2f" % [a, b, c]
	var clear := Atmosphere.sky(Vector3(0.0, 0.5, 1.0), _sun(50.0), a, 1.0)
	var hazy := Atmosphere.sky(Vector3(0.0, 0.5, 1.0), _sun(50.0), c, 1.0)
	var sat := func(x: Color) -> float: return (x.b - x.r) / x.b
	if sat.call(hazy) >= sat.call(clear):
		return "haze should whiten the sky"
	return ""


func test_sky_time_haze_matches_the_model() -> String:
	# SkyTime derives its clear-sky horizon (the fog colour) from Atmosphere: sun-lit horizon
	# azimuths stay clear of the sun and the luminance is capped.
	var st := SkyTime.new()
	var sun := _sun(6.0)
	var a: Array = st._atmosphere(sun, 6.0, 30000.0)
	st.free()
	var top: Color = a[0]
	var hor: Color = a[1]
	var want_top := Atmosphere.sky(Vector3.UP, sun, Atmosphere.aerosol_for_visibility(30000.0), 1.0)
	if absf(top.b - want_top.b) > 1e-4:
		return "zenith from SkyTime differs from Atmosphere"
	if hor.get_luminance() > 0.91:
		return "fog horizon colour should be capped, luminance %.2f" % hor.get_luminance()
	return ""
