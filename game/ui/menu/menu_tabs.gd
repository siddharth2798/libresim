class_name MenuTabs
extends BoxContainer
## Tabs for the Options and Controls pages: a bar of flat toggle Buttons (pill with an accent tint when
## selected, MenuTheme.focus_box ring on keyboard focus) and a stack of pages; only the selected page shows.
## All pages are built up front and only hidden, so every control stays alive (and findable by tests).
##
##     var tabs := MenuTabs.new().setup(false, true)   # (as_rail, sticky): bar on top / rail at the left; sticky = the pages
##                                                     # scroll under a bar that stays in view (the page must fill its height)
##     tabs.add_tab("sound", "Sound", page_control)
##     tabs.tab_changed.connect(func(id): ...)
##     tabs.select("sound")                            # also emits tab_changed unless emit := false
##
## Keys: Left / Right (Up / Down on a rail) on a focused tab select the neighbour (wraps) and keep the focus
## there; Ctrl+Tab / Ctrl+Shift+Tab switch from anywhere while the tabs are visible. The key rules are
## pure statics (`step`, `delta_for_key`) so they are tested without a window.

signal tab_changed(id: String)

const RAIL_W := 190.0

var rail := false
var content: Control  # the stack the pages sit in
var header: Container  # the bar, plus whatever add_extra() put beside it (a rail: its scroll area)
var scroll: ScrollContainer  # sticky tabs: the pages scroll in this, the bar stays
var _bar: Container
var _group := ButtonGroup.new()
var _ids: Array[String] = []
var _btns := {}  # id -> Button
var _pages := {}  # id -> Control
var _cur := ""


## `as_rail`: tabs stacked at the left of the pages instead of a row above them. `sticky`: the pages scroll inside this
## control (both ways when they need to, the focused control is kept in view) and the tab bar never scrolls away; the
## page that holds the tabs must then give them its whole height instead of scrolling as a whole.
func setup(as_rail := false, sticky := false) -> MenuTabs:
	rail = as_rail
	vertical = not as_rail
	add_theme_constant_override("separation", 22 if as_rail else 10)
	size_flags_horizontal = SIZE_EXPAND_FILL
	if as_rail:
		_bar = VBoxContainer.new()
		_bar.custom_minimum_size = Vector2(RAIL_W, 0)
		_bar.add_theme_constant_override("separation", 6)
		_bar.size_flags_horizontal = SIZE_FILL
		var rs := ScrollContainer.new()  # a window too short for all the tabs scrolls the rail instead of cutting the last ones off
		rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		rs.follow_focus = true
		rs.custom_minimum_size = Vector2(RAIL_W, 0)
		rs.add_child(_bar)
		header = rs
	else:
		_bar = HBoxContainer.new()
		_bar.add_theme_constant_override("separation", 6)
		var flow := HFlowContainer.new()  # a narrow window wraps the extras under the tabs instead of widening the page
		flow.add_theme_constant_override("h_separation", 18)
		flow.add_theme_constant_override("v_separation", 8)
		flow.size_flags_horizontal = SIZE_EXPAND_FILL
		flow.add_child(_bar)
		header = flow
	add_child(header)
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	m.size_flags_vertical = SIZE_EXPAND_FILL
	content = m
	if sticky:
		size_flags_vertical = SIZE_EXPAND_FILL
		scroll = ScrollContainer.new()
		scroll.follow_focus = true
		scroll.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		m.add_theme_constant_override("margin_right", 10)  # room for the scroll bar
		scroll.add_child(m)
		add_child(scroll)
	else:
		add_child(m)
	return self


## Puts a control beside the tabs on a bar on top (it wraps to a second line when the window is narrow); on a rail it goes under the tabs.
func add_extra(c: Control) -> void:
	(_bar if rail else header).add_child(c)


## Adds a tab and its page (hidden unless it becomes the selected one). The first tab added is selected.
func add_tab(id: String, title: String, page: Control) -> Button:
	var b := Button.new()
	b.text = title
	b.toggle_mode = true
	b.button_group = _group
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if rail else HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = SIZE_EXPAND_FILL if rail else SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(0, 40)
	style_tab(b, 10 if rail else 20)
	b.pressed.connect(func(): select(id))
	b.gui_input.connect(_on_tab_input.bind(id))
	_bar.add_child(b)
	content.add_child(page)
	page.visible = false
	_ids.append(id)
	_btns[id] = b
	_pages[id] = page
	if _cur == "":
		select(id, false)
	return b


## Swaps the page of a tab for a new one (the old one is freed); the tab keeps its place and selection state.
func replace_page(id: String, page: Control) -> void:
	if not _pages.has(id):
		return
	var old: Control = _pages[id]
	content.remove_child(old)
	old.queue_free()
	content.add_child(page)
	page.visible = id == _cur
	_pages[id] = page


func current() -> String:
	return _cur


func ids() -> Array[String]:
	return _ids


func button(id: String) -> Button:
	return _btns.get(id)


func page(id: String) -> Control:
	return _pages.get(id)


## Selects a tab by id (unknown ids are ignored). Emits tab_changed only when the tab really changes.
func select(id: String, emit := true) -> void:
	if not _pages.has(id):
		return
	var changed := id != _cur
	_cur = id
	for k in _ids:
		_pages[k].visible = k == id
		(_btns[k] as Button).set_pressed_no_signal(k == id)
	if changed and emit:
		tab_changed.emit(id)


## Moves `delta` tabs (wrapping) and puts the keyboard focus on the new tab.
func move(delta: int, focus := false) -> void:
	if _ids.is_empty():
		return
	var id := _ids[step(_ids.find(_cur), _ids.size(), delta)]
	select(id)
	if focus:
		(_btns[id] as Button).grab_focus()


func _on_tab_input(e: InputEvent, _id: String) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var d := delta_for_key(e.keycode, e.ctrl_pressed, e.shift_pressed, rail)
		if d != 0:
			move(d, true)
			accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and is_visible_in_tree() and e.keycode == KEY_TAB and e.ctrl_pressed:
		move(delta_for_key(e.keycode, true, e.shift_pressed, rail))
		get_viewport().set_input_as_handled()


## Index `delta` steps from `cur` in a list of `count`, wrapping at both ends (an unknown `cur`, -1, counts as 0).
static func step(cur: int, count: int, delta: int) -> int:
	if count <= 0:
		return 0
	return posmod(maxi(cur, 0) + delta, count)


## -1 / +1 for the keys that move between tabs, else 0. Left / Right always; Up / Down only on a rail;
## Ctrl+Tab (Shift reverses) on either.
static func delta_for_key(keycode: int, ctrl: bool, shift: bool, on_rail: bool) -> int:
	if keycode == KEY_TAB and ctrl:
		return -1 if shift else 1
	if ctrl:
		return 0
	match keycode:
		KEY_LEFT: return -1
		KEY_RIGHT: return 1
		KEY_UP: return -1 if on_rail else 0
		KEY_DOWN: return 1 if on_rail else 0
	return 0


## The flat tab look: clear when idle, light on hover, accent tint and border when selected.
static func style_tab(b: Button, radius := 20) -> void:
	var clear := MenuTheme.box(Color(0, 0, 0, 0), radius, Color(0, 0, 0, 0), 16.0)
	var lit := MenuTheme.box(MenuTheme.HOVER_FILL, radius, Color(0, 0, 0, 0), 16.0)
	var on := MenuTheme.box(Color(MenuTheme.ACCENT, 0.2), radius, Color(MenuTheme.ACCENT, 0.7), 16.0)
	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", MenuTheme.focus_box(radius))
	b.add_theme_font_override("font", MenuTheme.font("medium"))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, MenuTheme.DIM if k == "font_color" else Color.WHITE)
