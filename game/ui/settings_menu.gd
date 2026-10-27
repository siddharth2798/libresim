extends PanelContainer
## F10: in-flight settings — graphics, weather and time of day. Every control
## edits a Props path directly, so changes apply immediately.

const SLIDERS := [
	# [label, prop, min, max, step, unit]
	["Time of day (IST)", "weather/time_h", 0.0, 24.0, 0.25, "h"],
	["Time rate", "weather/time_rate", 0.0, 60.0, 1.0, "x"],
	["Wind from", "weather/wind_dir_deg", 0.0, 360.0, 10.0, "°"],
	["Wind (surface)", "weather/wind_kt", 0.0, 40.0, 1.0, "kt"],
	["Gusts to", "weather/gust_kt", 0.0, 50.0, 1.0, "kt"],
	["Wind aloft from", "weather/aloft_dir_deg", 0.0, 360.0, 10.0, "°"],
	["Wind aloft", "weather/aloft_kt", 0.0, 60.0, 1.0, "kt"],
	["Turbulence", "weather/turbulence", 0.0, 1.0, 0.05, ""],
	["Visibility", "weather/visibility_m", 500.0, 40000.0, 500.0, "m"],
	["Cloud base (AMSL)", "weather/cloud_base_ft", 1000.0, 12000.0, 100.0, "ft"],
	["Cloud cover", "weather/cloud_cover", 0.0, 1.0, 0.05, ""],
	["Rain", "weather/precip", 0.0, 1.0, 0.05, ""],
	["QNH", "weather/qnh_hpa", 980.0, 1040.0, 1.0, "hPa"],
	["Temperature (sea level)", "weather/temp_c", -5.0, 45.0, 1.0, "°C"],
]

## Set before add_child: the content as a page of the pause screen (ui/pause_menu.gd): no frame,
## no title, always shown, no F10 hotkey. refresh() re-reads the values when the page opens.
var embedded := false
var _labels := {}
var _sliders := {}


func _ready() -> void:
	if embedded:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		visible = false
		set_anchors_preset(PRESET_CENTER)
		custom_minimum_size = Vector2(560, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	if not embedded:
		var title := Label.new()
		title.text = "Settings  (F10 to close)"
		title.add_theme_font_size_override("font_size", 20)
		vb.add_child(title)
	var gl := Label.new()
	gl.text = "Graphics preset"
	vb.add_child(gl)
	var gh := HBoxContainer.new()
	vb.add_child(gh)
	for p in Graphics.ORDER:
		var b := Button.new()
		b.text = p.capitalize()
		b.toggle_mode = true
		b.button_pressed = p == Graphics.preset
		b.pressed.connect(func():
			Graphics.set_preset(p)
			for c in gh.get_children():
				if c is Button and c.has_meta("preset"):
					c.button_pressed = c.get_meta("preset") == p)
		b.set_meta("preset", p)
		gh.add_child(b)
	var rend := Button.new()
	var fp := Graphics.renderer() == "forward_plus"
	rend.text = ("Renderer: Forward+ (switch to Mobile)" if fp else "Renderer: Mobile (switch to Forward+ for SSAO/TAA)") + " — restart"
	rend.pressed.connect(func():
		Graphics.set_renderer("mobile" if fp else "forward_plus")
		rend.text = "Saved — restart free-sim to apply")
	gh.add_child(rend)
	vb.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 3
	vb.add_child(grid)
	for s in SLIDERS:
		var l := Label.new()
		l.text = s[0]
		grid.add_child(l)
		var sl := HSlider.new()
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = s[4]
		sl.custom_minimum_size = Vector2(260, 20)
		sl.value_changed.connect(func(v): Props.set_v(s[1], v))
		grid.add_child(sl)
		var vl := Label.new()
		vl.custom_minimum_size = Vector2(90, 0)
		grid.add_child(vl)
		_sliders[s[1]] = sl
		_labels[s[1]] = [vl, s[5]]
	if embedded:
		return
	var fl := Label.new()
	fl.text = "Failures: F9.  Back to the start screen (airport, aircraft, weather, failures): Esc."
	fl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vb.add_child(fl)


func _unhandled_key_input(e: InputEvent) -> void:
	if not embedded and e.pressed and not e.echo and e.keycode == KEY_F10:
		visible = not visible
		if visible:
			refresh()


func refresh() -> void:
	for p in _sliders:
		(_sliders[p] as HSlider).set_value_no_signal(Props.get_f(p))


func _process(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	for p in _labels:
		var v := Props.get_f(p)
		var unit: String = _labels[p][1]
		if p == "weather/time_h":
			_labels[p][0].text = "%02d:%02d" % [int(v), int(fmod(v, 1.0) * 60.0)]
		else:
			_labels[p][0].text = ("%.2f" if v < 2.0 and v != 0.0 else "%.0f") % v + " " + unit
