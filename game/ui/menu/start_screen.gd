extends Control
## Start screen (main scene): pick the airport and start position, aircraft, weather /
## time / wind and failures, then FLY. The choices go into the Session autoload and
## are remembered for next time. Command-line flight options skip this screen.

const FLIGHT := "res://world/flight.tscn"
const BG := "res://ui/menu/menu_bg.jpg"
const PAGES := [
	["Airport & start", "res://ui/menu/airport_page.gd"],
	["Aircraft", "res://ui/menu/aircraft_page.gd"],
	["Weather & time", "res://ui/menu/conditions_page.gd"],
	["Failures", "res://ui/menu/failures_page.gd"],
	["Recording", "res://ui/menu/recording_page.gd"],
	["Controls", "res://ui/menu/controls_page.gd"],
	["Options", "res://ui/menu/options_page.gd"],
	["Saved flights", "res://ui/menu/saves_page.gd"],
]

var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _summary: Label
var _loading: Label


func _ready() -> void:
	if Session.skip_menu:
		get_tree().change_scene_to_file.call_deferred(FLIGHT)
		return
	AudioSettings.apply()
	set_anchors_preset(PRESET_FULL_RECT)
	theme = MenuTheme.make()
	if ResourceLoader.exists(BG):
		var bg := TextureRect.new()
		bg.texture = load(BG)
		bg.set_anchors_preset(PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.45)
	shade.set_anchors_preset(PRESET_FULL_RECT)
	add_child(shade)
	var m := MarginContainer.new()
	m.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	add_child(m)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	m.add_child(root)
	root.add_child(_top_bar())
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 16)
	root.add_child(mid)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(200, 0)
	nav.add_theme_constant_override("separation", 8)
	mid.add_child(nav)
	var content := PanelContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.add_child(content)
	var scroll := ScrollContainer.new()  # small windows: pages scroll instead of pushing FLY off-screen
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.add_theme_constant_override("margin_right", 12)
	scroll.add_child(stack)
	var group := ButtonGroup.new()
	for i in PAGES.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, PAGES[i][0]]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(_show.bind(i))
		nav.add_child(b)
		_tabs.append(b)
		var p: Control = HBoxContainer.new()  # every page script extends HBoxContainer
		p.set_script(load(PAGES[i][1]))
		p.size_flags_vertical = SIZE_EXPAND_FILL
		p.connect("changed", _update_summary)
		stack.add_child(p)
		_pages.append(p)
	root.add_child(_bottom_bar())
	_loading = Label.new()
	_loading.text = "Loading scenery…"
	_loading.add_theme_font_size_override("font_size", 30)
	_loading.set_anchors_preset(PRESET_CENTER)
	_loading.visible = false
	add_child(_loading)
	var credits := Control.new()
	credits.set_script(load("res://ui/credits_screen.gd"))
	credits.name = "Credits"
	add_child(credits)
	_show(0)
	_update_summary()


func _top_bar() -> Control:
	var hb := HBoxContainer.new()
	var title := Label.new()
	title.text = "free-sim"
	title.add_theme_font_size_override("font_size", 40)
	hb.add_child(title)
	var sub := Label.new()
	sub.text = "   Mumbai – Pune · Western Ghats"
	sub.add_theme_color_override("font_color", MenuTheme.DIM)
	sub.add_theme_font_size_override("font_size", 18)
	sub.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(sub)
	for item in [["Credits", func(): _press(KEY_F12)], ["Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(100, 40)
		b.pressed.connect(item[1])
		hb.add_child(b)
	return hb


func _bottom_bar() -> Control:
	var bar := PanelContainer.new()
	var hb := HBoxContainer.new()
	bar.add_child(hb)
	_summary = Label.new()
	_summary.size_flags_horizontal = SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_summary)
	var fly := Button.new()
	fly.text = "FLY  ▶"
	fly.custom_minimum_size = Vector2(200, 56)
	fly.add_theme_font_size_override("font_size", 24)
	fly.add_theme_stylebox_override("normal", MenuTheme.box(Color(MenuTheme.ACCENT, 0.75), 8))
	fly.add_theme_stylebox_override("hover", MenuTheme.box(MenuTheme.ACCENT, 8))
	fly.pressed.connect(_fly)
	hb.add_child(fly)
	return bar


func _show(i: int) -> void:
	for k in _pages.size():
		_pages[k].visible = k == i
	_tabs[i].button_pressed = true


func _update_summary() -> void:
	if _summary == null:  # pages report while being built
		return
	_summary.text = Session.summary()


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


func _fly() -> void:
	Session.save()
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(FLIGHT)


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode >= KEY_1 and e.keycode < KEY_1 + PAGES.size() and not get_viewport().gui_get_focus_owner() is LineEdit:
		_show(e.keycode - KEY_1)
	elif e.keycode == KEY_ENTER and e.ctrl_pressed:
		_fly()
