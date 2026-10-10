extends HBoxContainer
## Start screen page 3: weather (presets + custom), time of day and date, and wind,
## with the head / crosswind component for the chosen runway.

signal changed

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const TIMES := [["Dawn", 6.25], ["Morning", 9.0], ["Noon", 12.5], ["Afternoon", 15.5], ["Dusk", 18.6], ["Night", 21.5]]
const WINDS := [["Calm", 0, 0, 0.05], ["Light", 6, 0, 0.1], ["Moderate", 14, 20, 0.3], ["Strong", 22, 32, 0.55]]
const SLIDERS := {  # key: [label, min, max, step, format]
	"cloud_cover": ["Cloud cover", 0.0, 1.0, 0.05, "%d %%"],
	"cloud_base_ft": ["Cloud base (AMSL)", 800.0, 12000.0, 100.0, "%d ft"],
	"visibility_m": ["Visibility", 800.0, 40000.0, 200.0, "%.1f km"],
	"turbulence": ["Turbulence", 0.0, 1.0, 0.05, "%d %%"],
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
var _preset_btns := {}
var _xwind: Label
var _month: OptionButton
var _runways: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	var rw = Paths.load_json("runways.json")
	_runways = rw.runways if rw else []
	var weather := _column("Weather")
	var grid := GridContainer.new()
	grid.columns = 2
	weather.add_child(grid)
	var g := ButtonGroup.new()
	for n in Session.WEATHER:
		var b := Button.new()
		b.text = n
		b.toggle_mode = true
		b.button_group = g
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			Session.apply_weather_preset(n)
			_sync())
		grid.add_child(b)
		_preset_btns[n] = b
	for k in ["cloud_cover", "cloud_base_ft", "visibility_m", "turbulence", "qnh_hpa", "temp_c"]:
		_slider(weather, k, true)
	weather.add_child(MenuTheme.note("Monsoon = low overcast, poor visibility and gusty south-westerlies (rain is not drawn yet). Winter haze = Mumbai's smoggy Dec–Feb mornings."))
	var time := _column("Time & date")
	var tg := GridContainer.new()
	tg.columns = 3
	time.add_child(tg)
	for t in TIMES:
		var b := Button.new()
		b.text = t[0]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func(): _put("time_h", t[1]))
		tg.add_child(b)
	_slider(time, "time_h", false)
	_slider(time, "time_rate", false)
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
	var wg := GridContainer.new()
	wg.columns = 4
	wind.add_child(wg)
	for w in WINDS:
		var b := Button.new()
		b.text = w[0]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			Session.setup.wind_kt = float(w[1])
			Session.setup.gust_kt = float(w[2])
			Session.setup.turbulence = float(w[3])
			_sync())
		wg.add_child(b)
	for k in ["wind_dir_deg", "wind_kt", "gust_kt"]:
		_slider(wind, k, false)
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


func _column(title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	v.add_child(MenuTheme.heading(title))
	return v


func _slider(parent: Control, key: String, makes_custom: bool) -> void:
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
	sl.value_changed.connect(func(x):
		if makes_custom:
			Session.setup.weather = "Custom"
		_put(key, x))
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
			"cloud_cover", "turbulence": _val[k].text = f % int(x * 100.0)
			"visibility_m": _val[k].text = f % (x / 1000.0)
			_: _val[k].text = f % int(x)
	for n in _preset_btns:
		_preset_btns[n].set_pressed_no_signal(n == s.weather)
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
