extends HBoxContainer
## Start screen page 3: weather, time of day and wind. Always shown: weather presets (with a line about the chosen one), time of
## day (presets, day strip, time slider, month), wind (presets, direction and speed sliders, the wind dial against the chosen
## runway with its head / crosswind line). The fine controls (clouds, visibility, rain, turbulence, thermals, storms, icing,
## gusts, QNH, temperature, time rate) sit behind "More weather", which stays as left for the session. Everything is read from and
## written to Session.setup. Choices and preset matching: weather_choices.gd; controls: wind_dial.gd / day_strip.gd.

signal changed

const MONTHS := WeatherChoices.MONTHS
const TIMES := WeatherChoices.TIMES
const WINDS := WeatherChoices.WINDS
const SLIDERS := WeatherChoices.SLIDERS
const LABEL_W := 100.0  # slider label / value widths: three columns of sliders fit the page panel
const VALUE_W := 56.0

static var _more_open := false  # "More weather" stays open or closed for the session

var _sl := {}
var _val := {}
var _weather_row: PresetRow
var _time_row: PresetRow
var _wind_row: PresetRow
var _weather_note: Label
var _xwind: Label
var _dial: WindDial
var _strip: DayStrip
var _xbtn: Button
var _month: OptionButton
var _more: Control
var _more_btn: Button


func _ready() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	root.add_child(top)
	_build_weather(_column(top, "Weather", WeatherChoices.WEATHER_TIP))
	_build_time(_column(top, "Time of day"))
	_build_wind(_column(top, "Wind", WeatherChoices.WIND_TIP, true))
	_more_btn = Button.new()
	_more_btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_more_btn.pressed.connect(func(): _show_more(not _more_open))
	root.add_child(_more_btn)
	_more = HBoxContainer.new()
	_more.add_theme_constant_override("separation", 20)
	root.add_child(_more)
	for col in [["Sky", ["cloud_cover", "cloud_base_ft", "visibility_m", "precip"]],
			["Air", ["turbulence", "convection", "storms", "icing"]],
			["More", ["gust_kt", "qnh_hpa", "temp_c", "time_rate"]]]:
		var c := _column(_more, col[0])
		for k in col[1]:
			_slider(c, k)
	_show_more(_more_open)
	visibility_changed.connect(func(): if visible: _sync())
	_sync()


func _build_weather(col: VBoxContainer) -> void:
	_weather_row = PresetRow.new().setup(Session.WEATHER.keys(), 2)
	_weather_row.picked.connect(func(n):
		Session.apply_weather_preset(n)
		_sync())
	col.add_child(_weather_row)
	_weather_note = MenuTheme.note("")
	col.add_child(_weather_note)


func _build_time(col: VBoxContainer) -> void:
	_time_row = PresetRow.new().setup(TIMES.map(func(x): return x[0]), 3)
	_time_row.picked.connect(func(n): _put("time_h", WeatherChoices.preset_time(WeatherChoices.time_value(n), float(Session.setup.day_of_year))))
	col.add_child(_time_row)
	_strip = DayStrip.new()
	_strip.time_picked.connect(func(h): _put("time_h", h))
	col.add_child(_strip)
	_slider(col, "time_h")
	_month_row(col)


func _build_wind(col: VBoxContainer) -> void:
	_wind_row = PresetRow.new().setup(WINDS.map(func(x): return x[0]), 4)
	_wind_row.picked.connect(func(n):
		for w in WINDS:
			if w[0] == n:
				Session.setup.wind_kt = float(w[1])
				Session.setup.gust_kt = float(w[2])
				Session.setup.turbulence = float(w[3])
		_sync())
	col.add_child(_wind_row)
	for k in ["wind_dir_deg", "wind_kt"]:
		_slider(col, k)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	col.add_child(hb)
	_dial = WindDial.new()
	_dial.direction_picked.connect(func(d): _put("wind_dir_deg", d))
	hb.add_child(_dial)
	_xwind = Label.new()
	_xwind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xwind.size_flags_horizontal = SIZE_EXPAND_FILL
	_xwind.size_flags_vertical = SIZE_SHRINK_CENTER
	_xwind.custom_minimum_size = Vector2(100, 0)
	hb.add_child(_xwind)


func _month_row(parent: Control) -> void:
	var mh := HBoxContainer.new()
	parent.add_child(mh)
	var ml := Label.new()
	ml.text = "Month"
	ml.size_flags_horizontal = SIZE_EXPAND_FILL
	SliderRow.tip_on(ml, "Moves sunrise and sunset, and the sun's height.")
	mh.add_child(ml)
	_month = OptionButton.new()
	for m in MONTHS:
		_month.add_item(m)
	_month.item_selected.connect(func(i): _put("day_of_year", 15.0 + 30.4 * i))
	SliderRow.tip_on(_month, "Moves sunrise and sunset, and the sun's height.")
	mh.add_child(_month)


func _show_more(open: bool) -> void:
	_more_open = open
	_more.visible = open
	_more_btn.text = "▼  Fewer options" if open else "▶  More weather: clouds, visibility, rain, turbulence, gusts…"


## Time for a TIMES entry: Dawn = sunrise, Dusk = sunset (to the nearest 5 min) for the date.
static func preset_time(h: float, day: float) -> float:
	return WeatherChoices.preset_time(h, day)


## Which preset row entry the values in `s` (a Session.setup) match, or "" for custom values
## (see WeatherChoices; start_flow's rail and chips use these too).
static func weather_match(s: Dictionary) -> String:
	return WeatherChoices.weather_match(s)


static func time_match(s: Dictionary) -> String:
	return WeatherChoices.time_match(s)


static func wind_match(s: Dictionary) -> String:
	return WeatherChoices.wind_match(s)


## A titled column. `xwind` adds the "90° crosswind" button at the right of the title.
func _column(parent: Control, title: String, tip := "", xwind := false) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
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
	_xbtn = Button.new()
	_xbtn.text = "90° crosswind"
	_xbtn.add_theme_font_size_override("font_size", 14)
	_xbtn.pressed.connect(func():
		var rwy := _runway()
		if not rwy.is_empty():
			_put("wind_dir_deg", fposmod(snappedf(float(rwy.heading_deg) + 90.0, 10.0), 360.0)))
	hb.add_child(_xbtn)
	v.add_child(hb)
	return v


func _slider(parent: Control, key: String) -> void:
	var d: Array = SLIDERS[key]
	var row := SliderRow.new().setup(d[0], d[1], d[2], d[3], d[5], LABEL_W, VALUE_W)
	row.slider.value_changed.connect(func(x): _put(key, x))  # _sync re-derives which preset still matches
	parent.add_child(row)
	_sl[key] = row.slider
	_val[key] = row.value_label


func _put(key: String, v: float) -> void:
	Session.setup[key] = v
	_sync()


## The runway the flight uses ({ident, length_m, heading_deg}), {} on a stand start (no runway then).
func _runway() -> Dictionary:
	if str(Session.setup.get("start", "runway")) == "stand":
		return {}
	return SetupChecks.runway_of(Session.setup)


func _sync() -> void:
	var s: Dictionary = Session.setup
	for k in _sl:
		var x := float(s[k])
		(_sl[k] as HSlider).set_value_no_signal(x)
		_val[k].text = WeatherChoices.value_text(k, x)
	var wx := WeatherChoices.weather_match(s)
	s.weather = wx if wx != "" else "Custom"
	_weather_row.select(wx)
	_weather_note.text = WeatherChoices.weather_note(wx)
	_time_row.select(WeatherChoices.time_match(s))
	_wind_row.select(WeatherChoices.wind_match(s))
	_month.select(clampi(int((float(s.day_of_year) - 1.0) / 30.4), 0, 11))
	_strip.set_state(float(s.time_h), float(s.day_of_year))
	_sync_wind(s)
	changed.emit()


## The dial and the wind line for the chosen runway and aircraft (limits.max_crosswind_kt).
func _sync_wind(s: Dictionary) -> void:
	var rwy := _runway()
	var has := not rwy.is_empty()
	var limit := WindMath.limit_kt(str(s.get("aircraft", AircraftDef.DEFAULT_ID)))
	var heading := float(rwy.heading_deg) if has else -1.0
	var ident := str(rwy.ident) if has else ""
	_dial.set_state(float(s.wind_dir_deg), float(s.wind_kt), float(s.gust_kt), heading, ident, limit)
	var comp := WindMath.components(float(s.wind_dir_deg), float(s.wind_kt), heading) if has else Vector2.ZERO
	_xwind.text = WindMath.line(ident, float(s.wind_dir_deg), float(s.wind_kt), comp, has)
	var lv := _dial.level()
	_xwind.add_theme_color_override("font_color", MenuTheme.TEXT if lv == WindMath.Level.OK else WindMath.color(lv))
	_xbtn.disabled = not has
	SliderRow.tip_on(_xwind, "Wind components on the chosen runway. Amber near, red above this aircraft's crosswind limit (%d kt) or with a tailwind above %d kt." % [roundi(limit), roundi(SetupChecks.TAILWIND_KT)])
	_xbtn.tooltip_text = "Turn the wind to blow straight across the chosen runway." if has else "A stand start has no runway."
