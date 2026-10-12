extends Control
## Start screen (main scene): pick the airport and start position, aircraft, weather /
## time / wind and failures, then FLY. The choices go into the Session autoload and
## are remembered for next time. Command-line flight options skip this screen.

const FLIGHT := "res://world/flight.tscn"
const BG := "res://ui/menu/menu_bg.jpg"
const LOGO := "res://branding/logo.png"
## [title, script, group, prompt]. Group "step" pages form the guided Next / Back flow
## (Airport -> Aircraft -> Weather -> Failures -> Fly); the rest are reachable from the left list.
const PAGES := [
	["Airport & start", "res://ui/menu/airport_page.gd", "step", "Where do you want to start?"],
	["Aircraft", "res://ui/menu/aircraft_page.gd", "step", "Choose your aircraft, fuel and load."],
	["Weather & time", "res://ui/menu/conditions_page.gd", "step", "Set the weather, time of day and wind."],
	["Failures", "res://ui/menu/failures_page.gd", "step", "Optional: practise emergencies. Skip this to fly with everything working."],
	["Training", "res://ui/menu/training_page.gd", "learn", "Learn to take off, cruise and land, one lesson at a time."],
	["Recording", "res://ui/menu/recording_page.gd", "more", "Record your flight as a video."],
	["Controls", "res://ui/menu/controls_page.gd", "more", "Keyboard, joystick and gamepad."],
	["Options", "res://ui/menu/options_page.gd", "more", "Sound, graphics and flight-control feel."],
	["Saved flights", "res://ui/menu/saves_page.gd", "more", "Pick up where you left off."],
]
const STEPS := 4  # the first four pages are the guided steps
const GROUP_TITLES := {"step": "FREE FLIGHT", "learn": "LEARN", "more": "MORE"}

var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _summary: Label
var _loading: Label
var _prompt: Label
var _pills: Array[Button] = []
var _back: Button
var _next: Button
var _fly_btn: Button
var _visited := {}
var _cur := 0


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
	nav.add_theme_constant_override("separation", 4)
	mid.add_child(nav)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	mid.add_child(column)
	column.add_child(_stepper())
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 20)
	column.add_child(_prompt)
	var content := PanelContainer.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(content)
	var scroll := ScrollContainer.new()  # small windows: pages scroll instead of pushing FLY off-screen
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var stack := MarginContainer.new()
	stack.size_flags_horizontal = SIZE_EXPAND_FILL
	stack.size_flags_vertical = SIZE_EXPAND_FILL
	stack.add_theme_constant_override("margin_right", 12)
	scroll.add_child(stack)
	var group := ButtonGroup.new()
	var last_group := ""
	for i in PAGES.size():
		if PAGES[i][2] != last_group:
			last_group = PAGES[i][2]
			if nav.get_child_count() > 0:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 6)
				nav.add_child(gap)
			nav.add_child(MenuTheme.heading(GROUP_TITLES[last_group], 13))
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_show.bind(i))
		nav.add_child(b)
		_tabs.append(b)
		var p: Control = HBoxContainer.new()  # every page script extends HBoxContainer
		p.set_script(load(PAGES[i][1]))
		p.size_flags_vertical = SIZE_EXPAND_FILL
		p.connect("changed", _update_summary)
		if p.has_signal("start_requested"):
			p.connect("start_requested", _start_lesson)
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
	Session.end_lesson()  # coming back from a lesson: restore the free-flight setup
	_show(0)
	_update_summary()


func _top_bar() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	if ResourceLoader.exists(LOGO):
		var logo := TextureRect.new()
		logo.texture = load(LOGO)
		logo.custom_minimum_size = Vector2(64, 64)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(logo)
	var title := Label.new()
	title.text = "libresim"
	title.add_theme_font_size_override("font_size", 40)
	hb.add_child(title)
	var sub := Label.new()
	sub.text = "Mumbai – Kochi · Western Ghats"
	sub.add_theme_color_override("font_color", MenuTheme.DIM)
	sub.add_theme_font_size_override("font_size", 18)
	sub.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(sub)
	for item in [["Handbook", _open_handbook], ["Credits", func(): _press(KEY_F12)], ["Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(100, 40)
		b.pressed.connect(item[1])
		hb.add_child(b)
	return hb


## Opens the HTML handbook (docs/site/index.html) in the system browser.
func _open_handbook() -> void:
	var path := Paths.docs_dir().path_join("docs/site/index.html")
	if FileAccess.file_exists(path):
		OS.shell_open("file://" + path)
	else:
		push_warning("Handbook not found: " + path)


func _bottom_bar() -> Control:
	var bar := PanelContainer.new()
	var hb := HBoxContainer.new()
	bar.add_child(hb)
	_summary = Label.new()
	_summary.size_flags_horizontal = SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_summary)
	hb.add_theme_constant_override("separation", 10)
	_back = Button.new()
	_back.text = "◀  Back"
	_back.custom_minimum_size = Vector2(120, 56)
	_back.pressed.connect(func(): _show(maxi(_cur - 1, 0)))
	hb.add_child(_back)
	_next = Button.new()
	_next.custom_minimum_size = Vector2(250, 56)
	_next.add_theme_font_size_override("font_size", 20)
	_next.pressed.connect(func(): _show(mini(_cur + 1, STEPS - 1)))
	hb.add_child(_next)
	_fly_btn = Button.new()
	_fly_btn.custom_minimum_size = Vector2(200, 56)
	_fly_btn.add_theme_font_size_override("font_size", 24)
	_fly_btn.pressed.connect(_fly)
	hb.add_child(_fly_btn)
	return bar


## Stepper above the page: Airport > Aircraft > Weather > Failures > Fly. The current step is
## filled, finished steps get a tick, and every pill is clickable.
func _stepper() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for i in STEPS + 1:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_show.bind(i) if i < STEPS else _fly)
		hb.add_child(b)
		_pills.append(b)
		if i < STEPS:
			var arrow := Label.new()
			arrow.text = "›"
			arrow.add_theme_color_override("font_color", MenuTheme.DIM)
			arrow.add_theme_font_size_override("font_size", 22)
			hb.add_child(arrow)
	return hb


func _refresh_flow() -> void:
	var on_step := _cur < STEPS
	for i in _pills.size():
		var b := _pills[i]
		var cur := on_step and i == _cur
		var done := i < STEPS and _visited.has(i) and not cur
		b.text = ("✓  " if done else ("%d  " % (i + 1) if i < STEPS else "▶  ")) + (PAGES[i][0] if i < STEPS else "Fly")
		b.add_theme_stylebox_override("normal", MenuTheme.box(Color(MenuTheme.ACCENT, 0.8) if cur else Color(1, 1, 1, 0.07), 19))
		b.add_theme_stylebox_override("hover", MenuTheme.box(Color(MenuTheme.ACCENT, 0.9) if cur else Color(1, 1, 1, 0.16), 19))
		b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.9), 19))
		b.add_theme_color_override("font_color", Color.WHITE if cur else (MenuTheme.ACCENT if done else MenuTheme.DIM))
	for i in _tabs.size():
		_tabs[i].text = ("✓ " if i < STEPS and _visited.has(i) and i != _cur else "") + "%d  %s" % [i + 1, PAGES[i][0]]
	_prompt.text = "Step %d of %d  ·  %s" % [_cur + 1, STEPS, PAGES[_cur][3]] if on_step else PAGES[_cur][3]
	_back.visible = on_step and _cur > 0
	_next.visible = on_step and _cur < STEPS - 1
	if _next.visible:
		_next.text = "Next:  %s  ▶" % PAGES[_cur + 1][0]
	# the primary (filled) button is whatever the player should press next
	var fly_primary := not (on_step and _cur < STEPS - 1)
	_style_primary(_next, true)
	_style_primary(_fly_btn, fly_primary)
	_fly_btn.text = "FLY  ▶" if on_step or _cur >= STEPS else "FLY  ▶"
	if not on_step:
		_back.visible = true
		_back.text = "◀  Flight setup"


func _style_primary(b: Button, primary: bool) -> void:
	var fill := Color(MenuTheme.ACCENT, 0.8) if primary else Color(1, 1, 1, 0.07)
	b.add_theme_stylebox_override("normal", MenuTheme.box(fill, 8, Color(MenuTheme.ACCENT, 0.9) if not primary else Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", MenuTheme.box(Color(MenuTheme.ACCENT, 0.95) if primary else Color(1, 1, 1, 0.16), 8))
	b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.5), 8))
	b.add_theme_color_override("font_color", Color.WHITE)


func _show(i: int) -> void:
	if _cur < STEPS:
		_visited[_cur] = true  # leaving a step counts as having looked at it
	_cur = i
	for k in _pages.size():
		_pages[k].visible = k == i
	_tabs[i].button_pressed = true
	_refresh_flow()


func _update_summary() -> void:
	if _summary == null:  # pages report while being built
		return
	_summary.text = Session.summary()


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


## Training page: the lesson was already written into Session.setup (start_requested).
func _start_lesson() -> void:
	_loading.text = "Loading lesson…"
	_loading.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(FLIGHT)


func _fly() -> void:
	Session.training = ""  # a free flight, not a lesson
	Session.save()
	_loading.text = "Loading scenery…"
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
	elif e.keycode == KEY_PAGEDOWN and _cur < STEPS - 1:
		_show(_cur + 1)
	elif e.keycode == KEY_PAGEUP and _cur > 0 and _cur < STEPS:
		_show(_cur - 1)
