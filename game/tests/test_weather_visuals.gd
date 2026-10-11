extends RefCounted
## Weather look (world/weather_visuals.gd, world/weather_fx.gd): presets -> rain / visibility /
## light, the visibility -> fog density formula, showers, and sunrise / sunset times.


func _preset(name: String) -> Dictionary:
	return Session.WEATHER[name]


func test_fog_density_is_meteorological_visibility() -> String:
	for vis in [1000.0, 5000.0, 20000.0]:
		var k := WeatherVisuals.fog_density(vis)
		if absf(k * vis - 3.0) > 0.01:  # -ln(0.05) = 2.996
			return "density * visibility = %.3f at %d m, want ~3.0" % [k * vis, int(vis)]
		var contrast := exp(-k * vis)
		if absf(contrast - 0.05) > 1e-4:
			return "contrast at the visibility distance %.4f, want 0.05" % contrast
	if WeatherVisuals.rain_visibility(5000.0, 0.0) != 5000.0:
		return "no rain must not change visibility"
	if WeatherVisuals.rain_visibility(5000.0, 1.0) > 3000.0:
		return "heavy rain should cut visibility well below 3 km from 5 km"
	return ""


func test_preset_precip() -> String:
	var want := {"Clear": 0.0, "Fair": 0.0, "Scattered": 0.0, "Winter haze": 0.0}
	for n in want:
		if float(_preset(n).get("precip", -1.0)) != want[n]:
			return "%s should be dry" % n
	var br := float(_preset("Broken").precip)
	var ov := float(_preset("Overcast").precip)
	var mo := float(_preset("Monsoon").precip)
	if not (br > 0.0 and br < ov and ov < mo and mo >= 0.8):
		return "rain should rise Broken < Overcast < Monsoon (heavy): %.2f %.2f %.2f" % [br, ov, mo]
	if not Session.WEATHER_KEYS.has("precip"):
		return "precip is not pushed to Props (WEATHER_KEYS)"
	return ""


func test_showers() -> String:
	# Broken: occasional showers -> sometimes dry, sometimes raining
	var p := float(_preset("Broken").precip)
	var wet := 0
	var n := 600
	for i in n:
		if WeatherVisuals.shower_rate(p, i * 10.0, 3.0) > 0.02:
			wet += 1
	if wet == 0 or wet == n:
		return "Broken showers should come and go (raining %d of %d samples)" % [wet, n]
	# Monsoon: steady heavy rain
	var mo := float(_preset("Monsoon").precip)
	for i in 100:
		if WeatherVisuals.shower_rate(mo, i * 37.0, 1.0) < 0.6:
			return "Monsoon rain should be steady and heavy"
	if WeatherVisuals.shower_rate(0.0, 100.0) != 0.0:
		return "no rain setting must give no rain"
	# no rain above the cloud tops
	var base := 400.0
	if WeatherFx.local_rate(mo, 0.0, 1.0, base + WeatherFx.CLOUD_THICK + 50.0, base) != 0.0:
		return "rain above the cloud tops"
	if WeatherFx.local_rate(mo, 0.0, 1.0, 100.0, base) < 0.6:
		return "no rain below the base"
	return ""


func test_light_by_cover() -> String:
	var fair := WeatherVisuals.light_scales(WeatherVisuals.sun_occlusion(float(_preset("Fair").cloud_cover)), 0.0)
	var ov := WeatherVisuals.light_scales(WeatherVisuals.sun_occlusion(float(_preset("Overcast").cloud_cover)), 0.3)
	var mo := WeatherVisuals.light_scales(WeatherVisuals.sun_occlusion(float(_preset("Monsoon").cloud_cover)), 0.9)
	if fair.sun < 0.99 or fair.shadow < 0.99:
		return "Fair should keep full sun and shadows: %s" % fair
	if ov.sun > 0.1 or ov.shadow > 0.05:
		return "Overcast: no hard sun / shadows, got %s" % ov
	if not (mo.dark < ov.dark and ov.dark < fair.dark):
		return "scene should dim Fair > Overcast > Monsoon: %s %s %s" % [fair.dark, ov.dark, mo.dark]
	if ov.ambient <= fair.ambient:
		return "diffuse (ambient) light should take over under the deck"
	if WeatherVisuals.sun_occlusion(1.0, 0.0) != 0.0:
		return "above the deck the sun should be out"
	var sky: Array = WeatherVisuals.overcast_sky(Color(0.25, 0.45, 0.85), Color(0.7, 0.78, 0.88), 1.0, 1.0, 1.0)
	var top: Color = sky[0]
	if absf(top.r - top.b) > 0.12:
		return "overcast sky should be grey, got %s" % top
	return ""


func test_rain_particles_scale_with_preset() -> String:
	var lo: int = Graphics.PRESETS.low.rain
	var med: int = Graphics.PRESETS.medium.rain
	var hi: int = Graphics.PRESETS.ultra.rain
	if not (lo < med and med < hi):
		return "rain particle budget should grow with the preset"
	if WeatherVisuals.rain_particles(med, 0.0) != 0 or WeatherVisuals.rain_particles(med, 1.0) != med:
		return "particle count should follow the rain rate"
	return ""


func test_sunrise_sunset_mid_february() -> String:
	# Mumbai, 14 Feb: sunrise ~07:10 IST, sunset ~18:40 IST (timeanddate.com)
	var rs := WeatherVisuals.sun_rise_set(45.0)
	if absf(rs.x - (7.0 + 10.0 / 60.0)) > 0.12:
		return "sunrise %.2f h, want ~7.17" % rs.x
	if absf(rs.y - (18.0 + 40.0 / 60.0)) > 0.12:
		return "sunset %.2f h, want ~18.67" % rs.y
	# 06:30 in February is still before civil dawn (sun > 6 deg down): genuinely dark
	var el := rad_to_deg(SkyTime.sun_position(6.5, 45.0).x)
	if el > -6.0:
		return "06:30 sun elevation %.1f deg: expected pre-dawn" % el
	# June: sunrise ~06:00 IST
	var jun := WeatherVisuals.sun_rise_set(172.0)
	if absf(jun.x - 6.0) > 0.15:
		return "June sunrise %.2f, want ~6.0" % jun.x
	return ""


func test_moon_phase_and_position() -> String:
	# 2026: full moon 3 Jan 10:03 UTC, new moon 17 Feb 12:01 UTC
	var full := NightSky.phase(15.5, 3.0)
	if absf(full - 0.5) > 0.03:
		return "3 Jan should be full moon, phase %.3f" % full
	var new_m := NightSky.phase(17.5, 48.0)
	if minf(new_m, 1.0 - new_m) > 0.03:
		return "17 Feb should be new moon, phase %.3f" % new_m
	if NightSky.illumination(0.5) < 0.99 or NightSky.illumination(0.0) > 0.01:
		return "illumination"
	# a full moon is up all night: high around local midnight, roughly opposite the sun
	var mp := NightSky.moon_position(0.5, 4.0)
	if rad_to_deg(mp.x) < 50.0:
		return "full moon at 00:30 IST should be high, elevation %.1f" % rad_to_deg(mp.x)
	return ""
