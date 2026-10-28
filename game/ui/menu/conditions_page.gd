extends HBoxContainer
## Start screen page 3: weather (presets + custom), time of day and date, and wind,
## with the head / crosswind component for the chosen runway.

signal changed

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## Dawn / Dusk (-1 / -2) follow the real sunrise / sunset for the chosen month (WeatherVisuals.sun_rise_set).
const TIMES := [["Dawn", -1.0], ["Morning", 9.0], ["Noon", 12.5], ["Afternoon", 15.5], ["Dusk", -2.0], ["Night", 21.5]]
const WINDS := [["Calm", 0, 0, 0.05], ["Light", 6, 0, 0.1], ["Moderate", 14, 20, 0.3], ["Strong", 22, 32, 0.55]]
const SLIDERS := {  # key: [label, min, max, step, format]
	"cloud_cover": ["Cloud cover", 0.0, 1.0, 0.05, "%d %%"],
	"cloud_base_ft": ["Cloud base (AMSL)", 800.0, 12000.0, 100.0, "%d ft"],
	"visibility_m": ["Visibility", 800.0, 40000.0, 200.0, "%.1f km"],
	"precip": ["Rain", 0.0, 1.0, 0.05, "%d %%"],
	"turbulence": ["Turbulence", 0.0, 1.0, 0.05, "%d %%"],
	"convection": ["Thermals (day heating)", 0.0, 1.0, 0.05, "%d %%"],
	"storms": ["Storm cells (heavy rain only)", 0.0, 1.0, 0.05, "%d %%"],
	"icing": ["Icing (supercooled water)", 0.0, 1.0, 0.05, "%d %%"],
	"qnh_hpa": ["QNH", 990.0, 1035.0, 1.0, "%d hPa"],
	"temp_c": ["Temperature (sea level)", 5.0, 45.0, 1.0, "%d °C"],
	"time_h": ["Time of day (IST)", 0.0, 24.0, 0.25, ""],
	"time_rate": ["Time passes", 0.0, 60.0, 1.0, "%dx"],
	"wind_dir_deg": ["Wind from", 0.0, 360.0, 10.0, "%03d °"],
	"wind_kt": ["Wind speed", 0.0, 40.0, 1.0, "%d kt"],
	"gust_kt": ["Gusts to", 0.0, 50.0, 1.0, "%d kt"],
}

var _sl := {}
var _val := {}
var _weather_row: PresetRow
var _time_row: PresetRow
var _wind_row: PresetRow
var _xwind: Label
var _month: OptionButton
var _runways: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	var rw = Paths.load_json("runways.json")
	_runways = rw.runways if rw else []
	var weather := _column("Weather")
	_weather_row = PresetRow.new().setup(Session.WEATHER.keys(), 2)
	_weather_row.picked.connect(func(n):
		Session.apply_weather_preset(n)
		_sync())
	weather.add_child(_weather_row)
	for k in ["cloud_cover", "cloud_base_ft", "visibility_m", "precip", "turbulence", "convection", "storms", "icing", "qnh_hpa", "temp_c"]:
		_slider(weather, k)
	weather.add_child(MenuTheme.note("Rain: Broken = passing showers, Overcast = drizzle, Monsoon = heavy rain under a low deck with gusty south-westerlies (and the odd lightning flash). Winter haze = Mumbai's smoggy Dec–Feb mornings. Thermals: the sun lifts the air under cumulus and sinks it between (not at night, weak over water); storm cells (microbursts with outflow shear) only occur in heavy monsoon-like rain. Icing: ice forms in cloud where the air is between +2 and −20 °C, which in the tropics means above about 5,000 m (FL165); the C172 only has pitot heat, the A320 has anti-ice."))
	var time := _column("Time & date")
	_time_row = PresetRow.new().setup(TIMES.map(func(x): return x[0]), 3)
	_time_row.picked.connect(func(n): _put("time_h", preset_time(_time_value(n), float(Session.setup.day_of_year))))
	time.add_child(_time_row)
	_slider(time, "time_h")
	_slider(time, "time_rate")
	var mh := HBoxContainer.new()
	time.add_child(mh)
	var ml := Label.new()
	ml.text = "Month"
	ml.size_flags_horizontal = SIZE_EXPAND_FILL
	mh.add_child(ml)
	_month = OptionButton.new()
	for m in MONTHS:
		_month.add_item(m)
	_month.item_selected.connect(func(i): _put("day_of_year", 15.0 + 30.4 * i))
	mh.add_child(_month)
	time.add_child(MenuTheme.note("Sun and moon positions are computed for the date and time; 0x freezes the clock."))
	var wind := _column("Wind")
	_wind_row = PresetRow.new().setup(WINDS.map(func(x): return x[0]), 4)
	_wind_row.picked.connect(func(n):
		for w in WINDS:
			if w[0] == n:
				Session.setup.wind_kt = float(w[1])
				Session.setup.gust_kt = float(w[2])
				Session.setup.turbulence = float(w[3])
		_sync())
	wind.add_child(_wind_row)
	for k in ["wind_dir_deg", "wind_kt", "gust_kt"]:
		_slider(wind, k)
	var xb := Button.new()
	xb.text = "Make it a 90° crosswind"
	xb.pressed.connect(func():
		var h := _runway_heading()
		if h >= 0.0:
			_put("wind_dir_deg", snappedf(fposmod(h + 90.0, 360.0), 10.0)))
	wind.add_child(xb)
	_xwind = Label.new()
	_xwind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wind.add_child(_xwind)
	wind.add_child(MenuTheme.note("Surface wind follows a log profile into the wind aloft (veered 10°, ~1.6x). Wind over the Ghats gives ridge lift on the windward side and sink + turbulence in the lee. C172S max demonstrated crosswind: 15 kt."))
	visibility_changed.connect(func(): if visible: _sync())
	_sync()


## Time for a TIMES entry: Dawn = sunrise, Dusk = sunset (to the nearest 5 min) for the date.
static func preset_time(h: float, day: float) -> float:
	if h >= 0.0:
		return h
	var rs := WeatherVisuals.sun_rise_set(day)
	return snappedf(rs.x if h == -1.0 else rs.y, 1.0 / 12.0)


static func _time_value(name: String) -> float:
	for t in TIMES:
		if t[0] == name:
			return t[1]
	return 12.0


## Which preset row entry the values in `s` (a Session.setup) match, or "" for custom values.
## The highlight is derived from the values, so it can never lie after a slider, a field or
## a loaded setup changed them. Weather ignores turbulence (the wind presets set it too), icing, thermals and storms (old setups have none).
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


func _column(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	v.add_child(MenuTheme.heading(title))
	return v


func _slider(parent: Control, key: String) -> void:
	var d: Array = SLIDERS[key]
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = d[0]
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(l)
	var v := Label.new()
	hb.add_child(v)
	var sl := HSlider.new()
	sl.min_value = d[1]
	sl.max_value = d[2]
	sl.step = d[3]
	sl.value_changed.connect(func(x): _put(key, x))  # _sync re-derives which preset still matches
	parent.add_child(sl)
	_sl[key] = sl
	_val[key] = v


func _put(key: String, v: float) -> void:
	Session.setup[key] = v
	_sync()


func _runway_heading() -> float:
	var s: Dictionary = Session.setup
	for r in _runways:
		if r.airport == s.airport:
			for e in r.ends:
				if e.ident == s.runway or s.runway == "":
					return float(e.heading_true)
	return -1.0


func _sync() -> void:
	var s: Dictionary = Session.setup
	for k in _sl:
		var x := float(s[k])
		(_sl[k] as HSlider).set_value_no_signal(x)
		var f: String = SLIDERS[k][4]
		match k:
			"time_h": _val[k].text = "%02d:%02d" % [int(x), int(fmod(x, 1.0) * 60.0)]
			"cloud_cover", "turbulence", "precip", "icing", "convection", "storms": _val[k].text = f % int(x * 100.0)
			"visibility_m": _val[k].text = f % (x / 1000.0)
			_: _val[k].text = f % int(x)
	var wx := weather_match(s)
	s.weather = wx if wx != "" else "Custom"
	_weather_row.select(wx)
	_time_row.select(time_match(s))
	_wind_row.select(wind_match(s))
	_month.select(clampi(int((float(s.day_of_year) - 1.0) / 30.4), 0, 11))
	var h := _runway_heading()
	if h >= 0.0:
		var rel := deg_to_rad(float(s.wind_dir_deg) - h)
		var head := float(s.wind_kt) * cos(rel)
		var cross := float(s.wind_kt) * sin(rel)
		_xwind.text = "Runway %s %s: %s %d kt, crosswind %d kt from the %s" % [s.airport, s.runway,
			"headwind" if head >= 0.0 else "TAILWIND", int(absf(head)), int(absf(cross)), "right" if cross >= 0.0 else "left"]
		_xwind.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if absf(cross) > 15.0 or head < -5.0 else MenuTheme.TEXT)
	changed.emit()
