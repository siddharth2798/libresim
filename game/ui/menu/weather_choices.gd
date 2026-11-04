class_name WeatherChoices
extends RefCounted
## The choices of the Weather & time step (ui/menu/conditions_page.gd): preset tables, the slider
## table, the one-line note of each weather preset, how a slider value reads, and which preset
## row entry a Session.setup matches. Pure data and maths, no nodes.

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## Dawn / Dusk (-1 / -2) follow the real sunrise / sunset for the chosen month (WeatherVisuals.sun_rise_set).
const TIMES := [["Dawn", -1.0], ["Morning", 9.0], ["Noon", 12.5], ["Afternoon", 15.5], ["Dusk", -2.0], ["Night", 21.5]]
const WINDS := [["Calm", 0, 0, 0.05], ["Light", 6, 0, 0.1], ["Moderate", 14, 20, 0.3], ["Strong", 22, 32, 0.55]]
const SLIDERS := {  # key: [label, min, max, step, format, hover text]
	"cloud_cover": ["Cloud cover", 0.0, 1.0, 0.05, "%d %%", ""],
	"cloud_base_ft": ["Cloud base", 800.0, 12000.0, 100.0, "%d ft", "Cloud base height above sea level."],
	"visibility_m": ["Visibility", 800.0, 40000.0, 200.0, "%.1f km", ""],
	"precip": ["Rain", 0.0, 1.0, 0.05, "%d %%", "Broken = passing showers, Overcast = drizzle, Monsoon = heavy rain."],
	"turbulence": ["Turbulence", 0.0, 1.0, 0.05, "%d %%", ""],
	"convection": ["Thermals", 0.0, 1.0, 0.05, "%d %%", "The sun lifts the air under cumulus and sinks it between. Not at night, weak over water."],
	"storms": ["Storm cells", 0.0, 1.0, 0.05, "%d %%", "Microbursts with outflow shear. Only in heavy, monsoon-like rain."],
	"icing": ["Icing", 0.0, 1.0, 0.05, "%d %%", "Supercooled water in cloud. Ice forms between +2 and -20 °C: above about 5,000 m in the tropics. C172: pitot heat only; A320: anti-ice."],
	"qnh_hpa": ["QNH", 990.0, 1035.0, 1.0, "%d hPa", ""],
	"temp_c": ["Temperature", 5.0, 45.0, 1.0, "%d °C", "Sea-level temperature."],
	"time_h": ["Time (IST)", 0.0, 24.0, 0.25, "", "Sun and moon follow the date and time."],
	"time_rate": ["Time rate", 0.0, 60.0, 1.0, "%dx", "How fast the clock runs in flight. 0x freezes it."],
	"wind_dir_deg": ["Wind from", 0.0, 360.0, 10.0, "%03d °", ""],
	"wind_kt": ["Wind speed", 0.0, 40.0, 1.0, "%d kt", ""],
	"gust_kt": ["Gusts to", 0.0, 50.0, 1.0, "%d kt", ""],
}
const WEATHER_TIP := "Broken = passing showers, Overcast = drizzle, Monsoon = heavy rain under a low deck with gusty south-westerlies. Winter haze = Mumbai's smoggy Dec-Feb mornings."
const WIND_TIP := "Surface wind follows a log profile into the wind aloft. Wind over the Ghats gives ridge lift on the windward side and sink and turbulence in the lee."
const NOTES := {  # one line under the weather presets (the chosen design's card text)
	"Clear": "40 km, no cloud",
	"Fair": "20 km, few cumulus",
	"Scattered": "Cloud at 3,000 ft",
	"Broken": "Passing showers",
	"Overcast": "Drizzle, low deck",
	"Winter haze": "Mumbai's smoggy Dec-Feb mornings",
	"Monsoon": "Heavy rain, gusty SW winds",
}


## Time for a TIMES entry: Dawn = sunrise, Dusk = sunset (to the nearest 5 min) for the date.
static func preset_time(h: float, day: float) -> float:
	if h >= 0.0:
		return h
	var rs := DayMath.sun_times(day)
	return snappedf(rs.x if h == -1.0 else rs.y, 1.0 / 12.0)


static func time_value(name: String) -> float:
	for t in TIMES:
		if t[0] == name:
			return t[1]
	return 12.0


## The text of a slider's value label ("12:30" for the clock, "40.0 km", "35 %").
static func value_text(key: String, x: float) -> String:
	var f: String = SLIDERS[key][4]
	match key:
		"time_h": return DayMath.clock(x)
		"cloud_cover", "turbulence", "precip", "icing", "convection", "storms": return f % int(x * 100.0)
		"visibility_m": return f % (x / 1000.0)
	return f % int(x)


## Which weather preset the values in `s` (a Session.setup) match, or "" for custom values.
## The highlight is derived from the values, so it can never lie after a slider, a field or
## a loaded setup changed them. Weather ignores turbulence (the wind presets set it too), icing,
## thermals and storms (old setups have none).
static func weather_match(s: Dictionary) -> String:
	for n in Session.WEATHER:
		var ok := true
		for k in Session.WEATHER[n]:
			if k not in ["turbulence", "icing", "convection", "storms"] and absf(float(s.get(k, 0.0)) - float(Session.WEATHER[n][k])) > 0.001:
				ok = false
		if ok:
			return n
	return ""


static func time_match(s: Dictionary) -> String:
	for t in TIMES:
		if absf(float(s.time_h) - preset_time(t[1], float(s.day_of_year))) < 0.01:
			return t[0]
	return ""


static func wind_match(s: Dictionary) -> String:
	for w in WINDS:
		if absf(float(s.wind_kt) - w[1]) < 0.01 and absf(float(s.gust_kt) - w[2]) < 0.01 and absf(float(s.turbulence) - w[3]) < 0.001:
			return w[0]
	return ""


## The line under the weather presets: the preset's note, or why nothing is highlighted.
static func weather_note(match_name: String) -> String:
	if match_name == "":
		return "Custom: you changed the values (More weather)."
	return str(NOTES.get(match_name, ""))
