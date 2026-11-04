extends HBoxContainer
## Start screen page (and the pause screen's Options): options in tabs (ui/menu/menu_tabs.gd), a rail at the left.
##   Sound            audio volume + mute per bus (core/audio_settings.gd)
##   Graphics         preset, renderer, post effects (options_graphics.gd; the Graphics autoload, same as F10)
##   Display & units  UI size (UiScale), HUD at start, units (core/user_options.gd)
##   Flight controls  yoke keys, input smoothing, auto-coordination
##   Radio / ATC      call sign, radio assist, ATC voice (atc/atc_options_box.gd)
##   Training aids    callouts and their voice
## Everything is saved as soon as it changes. Every tab is built at once and only hidden.

signal changed

const PRESET_NOTES := OptionsGraphics.PRESET_NOTES
const TABS := [["sound", "Sound"], ["graphics", "Graphics"], ["display", "Display & units"],
	["controls", "Flight controls"], ["radio", "Radio / ATC"], ["aids", "Training aids"]]
const UNIT_ROWS := [["Altitude", "alt_unit"], ["Speed", "speed_unit"], ["Pressure", "pressure_unit"]]

var tabs: MenuTabs
var _restart_note: Label  # the Graphics tab's "restart to apply" line


func _ready() -> void:
	AudioSettings.apply()
	tabs = MenuTabs.new().setup(true, true)
	add_child(tabs)
	var gfx := OptionsGraphics.new()
	gfx.changed.connect(func(): changed.emit())
	for t in TABS:
		var body: Control
		match t[0]:
			"sound": body = _sound()
			"graphics": body = gfx
			"display": body = _display()
			"controls": body = _flight_controls()
			"radio": body = _radio()
			"aids": body = _aids()
		tabs.add_tab(t[0], t[1], body)
	_restart_note = gfx.restart_note


func _sound() -> Control:
	var v := OptionRows.tab_body("Sound", "Volumes are saved immediately and apply in flight. Muting Master silences everything.")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for b in AudioSettings.BUSES:
		_bus_row(grid, b)
	return v


func _display() -> Control:
	var v := OptionRows.tab_body("Display", "Auto sizes text and panels to the window (4K, ultrawide, small windows). A percentage is fixed, relative to your system scale.")
	v.add_child(OptionRows.choice("UI size", "ui_scale", func(_x):
		UiScale.apply()
		changed.emit()))
	v.add_child(OptionRows.switch("Show the HUD overlay at start (H toggles in flight)", "hud_at_start", func(_on): changed.emit()))
	v.add_child(MenuTheme.heading("Units"))
	for u in UNIT_ROWS:
		v.add_child(OptionRows.choice(u[0], u[1], func(_x): changed.emit()))
	v.add_child(MenuTheme.note("Stored for later: instruments and the HUD still read ft, kt and inHg, like the real C172 panel."))
	return v


func _flight_controls() -> Control:
	var v := OptionRows.tab_body("Flight controls")
	v.add_child(OptionRows.choice("Yoke keys", "keyboard_mode", func(_x): changed.emit()))
	v.add_child(MenuTheme.note("Spring: arrow keys re-centre when released. Sticky: they stay where you leave them, like FlightGear (tap the opposite key to return to centre)."))
	v.add_child(OptionRows.choice("Input smoothing", "control_smoothing", func(_x): changed.emit()))
	v.add_child(OptionRows.switch("Auto-coordination (rudder follows aileron)", "auto_coordination", func(_on): changed.emit()))
	v.add_child(MenuTheme.note("Key and joystick bindings, deadzone and curve are on the Controls page (J in flight)."))
	return v


func _radio() -> Control:
	var atc := AtcOptionsBox.new()
	atc.size_flags_horizontal = SIZE_EXPAND_FILL
	atc.changed.connect(func(): changed.emit())
	return atc


func _aids() -> Control:
	var v := OptionRows.tab_body("Training callouts")
	v.add_child(OptionRows.switch("Training callouts (K toggles in flight)", "callouts", func(_on): changed.emit()))
	var cv_note := SpeechNote.new("callouts_voice")
	v.add_child(OptionRows.switch("Speak them (system voice)", "callouts_voice", func(_on):
		cv_note.refresh()
		changed.emit()))
	v.add_child(cv_note)
	v.add_child(MenuTheme.note("Airspeed alive, Rotate, Positive rate; 500 / 100 / 50 / 30 / 20 / 10 ft on the approach; sink rate, low airspeed and bank angle warnings. Off by default: a real C172 has none."))
	return v


func _bus_row(grid: GridContainer, bus: String) -> void:
	var l := Label.new()
	l.text = AudioSettings.LABELS.get(bus, bus)
	l.custom_minimum_size = Vector2(130, 0)  # "Wind & environment" wraps rather than widening the tab
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.value = AudioSettings.volume(bus) * 100.0
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(110, 0)
	grid.add_child(sl)
	var v := Label.new()
	v.custom_minimum_size = Vector2(56, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = "%d %%" % int(sl.value)
	grid.add_child(v)
	var m := SwitchRow.new().setup("Mute", "", AudioSettings.muted(bus)).compact()
	grid.add_child(m)
	sl.value_changed.connect(func(x):
		v.text = "%d %%" % int(x)
		AudioSettings.set_volume(bus, x / 100.0)
		changed.emit())
	m.toggled.connect(func(on: bool):
		AudioSettings.set_muted(bus, on)
		changed.emit())
