extends HBoxContainer
## Start screen page 3: weather, time of day and wind. The essentials (presets, time of day,
## wind direction / speed, the head / crosswind for the chosen runway) are always shown; the
## fine controls (clouds, visibility, rain, turbulence, thermals, storms, icing, gusts, QNH,
## temperature, time rate, month) sit behind "More weather", which stays as the player left it
## for the rest of the session.

signal changed

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

static var _more_open := false  # "More weather" stays open or closed for the session

var _sl := {}
var _val := {}
var _weather_row: PresetRow
var _time_row: PresetRow
var _wind_row: PresetRow
var _xwind: Label
var _month: OptionButton
var _runways: Array = []
var _more: Control
var _month_box: Control  # the month row (under Time of day), part of More weather
var _more_btn: Button


func _ready() -> void:
	var rw = Paths.load_json("runways.json")
	_runways = rw.runways if rw else []
	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	root.add_child(top)
	var weather := _column(top, "Weather", WEATHER_TIP)
	_weather_row = PresetRow.new().setup(Session.WEATHER.keys(), 3)
	_weather_row.picked.connect(func(n):
		Session.apply_weather_preset(n)
		_sync())
	weather.add_child(_weather_row)
	var time := _column(top, "Time of day")
	_time_row = PresetRow.new().setup(TIMES.map(func(x): return x[0]), 3)
	_time_row.picked.connect(func(n): _put("time_h", preset_time(_time_value(n), float(Session.setup.day_of_year))))
	time.add_child(_time_row)
	_slider(time, "time_h")
	_month_box = _month_row(time)  # shown with More weather
	var wind := _column(top, "Wind", WIND_TIP, true)
	_wind_row = PresetRow.new().setup(WINDS.map(func(x): return x[0]), 4)
	_wind_row.picked.connect(func(n):
		for w in WINDS:
			if w[0] == n:
				Session.setup.wind_kt = float(w[1])
				Session.setup.gust_kt = float(w[2])
				Session.setup.turbulence = float(w[3])
		_sync())
	wind.add_child(_wind_row)
	for k in ["wind_dir_deg", "wind_kt"]:
		_slider(wind, k)
	_xwind = Label.new()
	_xwind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	SliderRow.tip_on(_xwind, "Wind components on the chosen runway. Red above 15 kt crosswind (C172S maximum demonstrated) or with a tailwind.")
	wind.add_child(_xwind)
	_more_btn = Button.new()
	_more_btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_more_btn.pressed.connect(func(): _show_more(not _more_open))
	root.add_child(_more_btn)
	_more = HBoxContainer.new()
	_more.add_theme_constant_override("separation", 28)
	root.add_child(_more)
	var sky := _column(_more, "Sky")
	for k in ["cloud_cover", "cloud_base_ft", "visibility_m", "precip"]:
		_slider(sky, k)
	var air := _column(_more, "Air")
	for k in ["turbulence", "convection", "storms", "icing"]:
		_slider(air, k)
	var other := _column(_more, "More")
	for k in ["gust_kt", "qnh_hpa", "temp_c", "time_rate"]:
		_slider(other, k)
	_show_more(_more_open)
	visibility_changed.connect(func(): if visible: _sync())
	_sync()


func _month_row(parent: Control) -> Control:
	var mh := HBoxContainer.new()
	parent.add_child(mh)
	var ml := Label.new()
	ml.text = "Month"
	ml.size_flags_horizontal = SIZE_EXPAND_FILL
	mh.add_child(ml)
	_month = OptionButton.new()
	for m in MONTHS:
		_month.add_item(m)
	_month.item_selected.connect(func(i): _put("day_of_year", 15.0 + 30.4 * i))
	SliderRow.tip_on(_month, "Moves sunrise and sunset, and the sun's height.")
	mh.add_child(_month)
	return mh


func _show_more(open: bool) -> void:
	_more_open = open
	_more.visible = open
	_month_box.visible = open
	_more_btn.text = "▼  Fewer options" if open else "▶  More weather: clouds, visibility, rain, turbulence, gusts…"


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


## A titled column. `xwind` adds the "90° crosswind" button at the right of the title.
func _column(parent: Control, title: String, tip := "", xwind := false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	parent.add_child(v)
	var h := MenuTheme.heading(title)
	if tip != "":
		SliderRow.tip_on(h, tip)
	if not xwind:
		v.add_child(h)
		return v
	var hb := HBoxContainer.new()
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(h)
	var xb := Button.new()
	xb.text = "90° crosswind"
	xb.tooltip_text = "Turn the wind to blow straight across the chosen runway."
	xb.add_theme_font_size_override("font_size", 14)
	xb.pressed.connect(func():
		var rh := _runway_heading()
		if rh >= 0.0:
			_put("wind_dir_deg", snappedf(fposmod(rh + 90.0, 360.0), 10.0)))
	hb.add_child(xb)
	v.add_child(hb)
	return v


func _slider(parent: Control, key: String) -> void:
	var d: Array = SLIDERS[key]
	var row := SliderRow.new().setup(d[0], d[1], d[2], d[3], d[5])
	row.slider.value_changed.connect(func(x): _put(key, x))  # _sync re-derives which preset still matches
	parent.add_child(row)
	_sl[key] = row.slider
	_val[key] = row.value_label


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
		_xwind.text = "Rwy %s: %s %d kt, crosswind %d kt %s" % [s.runway,
			"headwind" if head >= 0.0 else "TAILWIND", int(absf(head)), int(absf(cross)), "right" if cross >= 0.0 else "left"]
		_xwind.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if absf(cross) > 15.0 or head < -5.0 else MenuTheme.TEXT)
	changed.emit()
