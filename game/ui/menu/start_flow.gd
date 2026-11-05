extends "res://ui/menu/page_frame.gd"
## Free flight: the guided setup. A left rail (FlowRail: the five steps with live value and status mark) beside one page at a time;
## a footer with Back, the setup as clickable chips (FlowChips), Next (names the next step, hidden on the last) and the one filled
## Fly button. Fly is never disabled: normal accent when the setup is ready (or has only warnings), amber "Fly anyway" when
## SetupChecks finds a "bad" problem (start_screen.gd then asks first). Back on the first step leaves for home (back_pressed).
## Choices go into Session.setup. Aircraft comes first because the airport page depends on it (air-start height and distance,
## runways long enough, stands that suit it). Keys: 1-5 jump to a step, Page Up / Down step, Ctrl+Enter flies, Esc goes back.
## Texts: flow_values.gd.

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
var fly_btn: Button  # the one filled button, in the footer on every step
var rail: FlowRail
var chips: FlowChips
var _visited := {}
var _sig := 0  # hash of Session.setup at the last repaint: a change by anything else repaints too


func _init() -> void:
	super()
	rail = FlowRail.new()
	rail.step_pressed.connect(show_step)
	chips = FlowChips.new()
	chips.chip_pressed.connect(show_step)
	_layout()
	fly_btn = Button.new()
	fly_btn.custom_minimum_size = Vector2(150, 56)
	fly_btn.add_theme_font_size_override("font_size", 20)
	fly_btn.pressed.connect(func(): fly_requested.emit())
	footer.add_child(fly_btn)
	primary_btn.add_theme_font_size_override("font_size", 18)
	primary_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.custom_minimum_size = Vector2(100, 56)
	for st in STEPS:
		var p := make_page(st[1])
		p.connect("changed", refresh_chrome)
		add_page(p)
	show_step(0)


## [rail | prompt + page panel] above the footer; the chips take the footer's summary slot.
func _layout() -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	var row := HBoxContainer.new()
	row.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	remove_child(prompt)
	remove_child(content)
	col.add_child(prompt)
	col.add_child(content)
	row.add_child(rail)
	row.add_child(col)
	add_child(row)
	move_child(row, 0)
	footer.add_child(chips)
	footer.move_child(chips, summary.get_index())
	summary.visible = false


## Called each time the flow is opened from the home screen: start at the first step.
func enter() -> void:
	show_step(0)


func show_step(i: int) -> void:
	_visited[cur] = true  # leaving a step counts as having looked at it
	cur = clampi(i, 0, STEPS.size() - 1)
	show_page(cur)
	var last := STEPS.size() - 1
	prompt.text = "Step %d of %d  ·  %s" % [cur + 1, STEPS.size(), STEPS[cur][2]]
	set_primary("" if cur == last else "Next:  %s  ▶" % STEPS[cur + 1][0].get_slice(" (", 0))
	MenuTheme.style_primary(primary_btn, false)  # Next is the quiet outline; Fly is the one filled button
	refresh_chrome()


## Repaint the rail, the chips and the Fly button from Session.setup (a page changed it, or it was replaced).
func refresh_chrome() -> void:
	var setup: Dictionary = Session.setup
	var list := SetupChecks.checks(setup)
	rail.refresh(setup, list, cur, _visited)
	chips.refresh(setup, list)
	fly_btn.text = FlowValues.fly_label(list)
	var bad := SetupChecks.worst(list) == "bad"
	MenuTheme.style_primary(fly_btn, true, MenuTheme.WARN if bad else MenuTheme.ACCENT)
	fly_btn.tooltip_text = ("Fly anyway: %s (Ctrl+Enter asks first)" % "; ".join(SetupChecks.reasons(list))) if bad else "Start flying with this setup (Ctrl+Enter)"
	_sig = setup.hash()


func _process(_dt: float) -> void:
	if is_visible_in_tree() and Session.setup.hash() != _sig:
		refresh_chrome()


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
