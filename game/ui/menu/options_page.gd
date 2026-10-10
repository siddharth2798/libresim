extends HBoxContainer
## Start screen page: options. Audio volume + mute per bus (core/audio_settings.gd),
## graphics preset (Graphics autoload, same as F10), units and HUD-at-start
## (core/user_options.gd). Everything is saved as soon as it changes.

signal changed

const PRESET_NOTES := {
	"low": "70 % render scale with FSR, no shadows, short scenery range. For integrated graphics.",
	"medium": "85 % render scale with FSR, near shadows, medium scenery range.",
	"high": "Full resolution, MSAA 2x, shadows to 300 m, long scenery range.",
	"ultra": "MSAA 4x, long shadows, densest trees and buildings, more cloud steps.",
}
const UNIT_ROWS := [["Altitude", "alt_unit"], ["Speed", "speed_unit"], ["Pressure", "pressure_unit"]]

var _preset_note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 32)
	AudioSettings.apply()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	left.add_child(MenuTheme.heading("Sound"))
	for b in AudioSettings.BUSES:
		_bus_row(left, b)
	left.add_child(MenuTheme.note("Volumes are saved immediately and apply in flight. Muting Master silences everything."))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	right.add_child(MenuTheme.heading("Graphics quality"))
	var row := HBoxContainer.new()
	right.add_child(row)
	var g := ButtonGroup.new()
	for p in Graphics.ORDER:
		var bt := Button.new()
		bt.text = p.capitalize()
		bt.toggle_mode = true
		bt.button_group = g
		bt.size_flags_horizontal = SIZE_EXPAND_FILL
		bt.button_pressed = p == Graphics.preset
		bt.pressed.connect(func():
			Graphics.set_preset(p)
			_preset_note.text = PRESET_NOTES.get(p, "")
			changed.emit())
		row.add_child(bt)
	_preset_note = MenuTheme.note(PRESET_NOTES.get(Graphics.preset, ""))
	right.add_child(_preset_note)
	right.add_child(MenuTheme.heading("Units"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	right.add_child(grid)
	for u in UNIT_ROWS:
		_unit_row(grid, u[0], u[1])
	right.add_child(MenuTheme.note("Stored for later: instruments and the HUD still read ft, kt and inHg, like the real C172 panel."))
	right.add_child(MenuTheme.heading("Display"))
	var hud := CheckBox.new()
	hud.text = "Show the HUD overlay at start (H toggles in flight)"
	hud.button_pressed = bool(UserOptions.get_v("hud_at_start"))
	hud.toggled.connect(func(on):
		UserOptions.set_v("hud_at_start", on)
		changed.emit())
	right.add_child(hud)


func _bus_row(parent: Control, bus: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	parent.add_child(hb)
	var l := Label.new()
	l.text = AudioSettings.LABELS.get(bus, bus)
	l.custom_minimum_size = Vector2(190, 0)
	hb.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 100.0
	sl.step = 5.0
	sl.value = AudioSettings.volume(bus) * 100.0
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	hb.add_child(sl)
	var v := Label.new()
	v.custom_minimum_size = Vector2(48, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = "%d %%" % int(sl.value)
	hb.add_child(v)
	var m := CheckBox.new()
	m.text = "Mute"
	m.button_pressed = AudioSettings.muted(bus)
	hb.add_child(m)
	sl.value_changed.connect(func(x):
		v.text = "%d %%" % int(x)
		AudioSettings.set_volume(bus, x / 100.0)
		changed.emit())
	m.toggled.connect(func(on):
		AudioSettings.set_muted(bus, on)
		changed.emit())


func _unit_row(grid: GridContainer, label: String, key: String) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	grid.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = SIZE_EXPAND_FILL
	var choices: Array = UserOptions.CHOICES[key]
	for c in choices:
		ob.add_item(c)
	ob.select(maxi(choices.find(UserOptions.get_v(key)), 0))
	ob.item_selected.connect(func(i):
		UserOptions.set_v(key, choices[i])
		changed.emit())
	grid.add_child(ob)
