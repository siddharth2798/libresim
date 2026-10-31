extends "res://ui/menu/page_frame.gd"
## Free flight: the guided setup. A stepper (Aircraft > Airport & start > Weather & time >
## Failures > Recording > Fly) above one page at a time; Back / Next name where they go, every
## step but the last has a filled Fly now, and the last has the big FLY button. Back on the
## first step leaves for the home screen (back_pressed). The choices go into Session.setup.
## The aircraft comes first because the airport page depends on it (air-start height and
## distance, runways long enough, stands that suit it). Keys: 1-5 jump to a step,
## Page Up / Page Down step, Ctrl+Enter flies.

signal fly_requested

## [title, page script, prompt]
const STEPS := [
	["Aircraft", "res://ui/menu/aircraft_page.gd", "Which aircraft, and how loaded?"],
	["Airport & start", "res://ui/menu/airport_page.gd", "Where do you want to start?"],
	["Weather & time", "res://ui/menu/conditions_page.gd", "What are the conditions?"],
	["Failures (optional)", "res://ui/menu/failures_page.gd", "Practise an emergency, or skip this."],
	["Recording (optional)", "res://ui/menu/recording_page.gd", "Record the flight as a video, or skip this."],
]

var cur := 0
var fly_btn: Button  # "Fly now", in the footer on every step but the last (whose main button is FLY)
var _pills: Array[Button] = []
var _visited := {}


func _init() -> void:
	super()
	var stepper := _stepper()
	add_child(stepper)
	move_child(stepper, 0)
	fly_btn = Button.new()
	fly_btn.text = "Fly now  ▶"
	fly_btn.tooltip_text = "Start flying with this setup (Ctrl+Enter)"
	fly_btn.custom_minimum_size = Vector2(170, 56)
	fly_btn.add_theme_font_size_override("font_size", 20)
	fly_btn.pressed.connect(func(): fly_requested.emit())
	MenuTheme.style_primary(fly_btn)
	footer.add_child(fly_btn)
	footer.move_child(fly_btn, primary_btn.get_index())
	for st in STEPS:
		var p := make_page(st[1])
		p.connect("changed", _update_summary)
		add_page(p)
	show_step(0)


## Stepper pills: the current step is filled, finished steps get a tick, every pill is clickable.
func _stepper() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for i in STEPS.size() + 1:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 38)
		b.focus_mode = Control.FOCUS_NONE
		if i < STEPS.size():
			b.pressed.connect(show_step.bind(i))
		else:
			b.pressed.connect(func(): fly_requested.emit())
		hb.add_child(b)
		_pills.append(b)
		if i < STEPS.size():
			var arrow := Label.new()
			arrow.text = "›"
			arrow.add_theme_color_override("font_color", MenuTheme.DIM)
			arrow.add_theme_font_size_override("font_size", 22)
			hb.add_child(arrow)
	return hb


## Called each time the flow is opened from the home screen: start at the first step.
func enter() -> void:
	show_step(0)
	_update_summary()


func show_step(i: int) -> void:
	_visited[cur] = true  # leaving a step counts as having looked at it
	cur = clampi(i, 0, STEPS.size() - 1)
	show_page(cur)
	_refresh()


func _refresh() -> void:
	var last := STEPS.size() - 1
	for i in _pills.size():
		var b := _pills[i]
		var here := i == cur
		var done := i < STEPS.size() and _visited.has(i) and not here
		b.text = ("✓  " if done else ("%d  " % (i + 1) if i < STEPS.size() else "▶  ")) + (STEPS[i][0] if i < STEPS.size() else "Fly")
		b.add_theme_stylebox_override("normal", MenuTheme.box(Color(MenuTheme.ACCENT, 0.8) if here else Color(1, 1, 1, 0.07), 19))
		b.add_theme_stylebox_override("hover", MenuTheme.box(Color(MenuTheme.ACCENT, 0.9) if here else Color(1, 1, 1, 0.16), 19))
		b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.9), 19))
		b.add_theme_color_override("font_color", Color.WHITE if here else (MenuTheme.ACCENT if done else MenuTheme.DIM))
	prompt.text = "Step %d of %d  ·  %s" % [cur + 1, STEPS.size(), STEPS[cur][2]]
	set_primary("FLY  ▶" if cur == last else "Next:  %s  ▶" % STEPS[cur + 1][0].get_slice(" (", 0))
	primary_btn.add_theme_font_size_override("font_size", 26 if cur == last else 20)
	primary_btn.custom_minimum_size = Vector2(220 if cur == last else 250, 56)
	MenuTheme.style_primary(primary_btn, cur == last)  # Next is the quiet outline; Fly now / FLY is the filled button
	fly_btn.visible = cur != last


func _update_summary() -> void:
	summary.text = Session.summary()


func go_back() -> void:
	if cur > 0:
		show_step(cur - 1)
	else:
		back_pressed.emit()


func on_primary() -> void:
	if cur < STEPS.size() - 1:
		show_step(cur + 1)
	else:
		fly_requested.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.pressed or e.echo:
		return
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if e.keycode >= KEY_1 and e.keycode < KEY_1 + STEPS.size() and not typing:
		show_step(e.keycode - KEY_1)
	elif e.keycode == KEY_ENTER and e.ctrl_pressed:
		fly_requested.emit()
	elif e.keycode == KEY_PAGEDOWN and cur < STEPS.size() - 1:
		show_step(cur + 1)
	elif e.keycode == KEY_PAGEUP and cur > 0:
		show_step(cur - 1)
	else:
		return
	get_viewport().set_input_as_handled()
