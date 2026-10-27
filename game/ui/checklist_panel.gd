class_name ChecklistPanel
extends ChecklistWindow
## Interactive checklists (F2). The window chrome (drag, resize, collapse, opacity) is
## ui/checklist_window.gd; this adds the content. Items with a property condition tick themselves
## when the aircraft state matches; the others tick on click (or Enter = next unticked item,
## Shift+Enter = take the last manual tick back). The first open item is highlighted and scrolled
## into view; collapsed, the window shows it as one line. Ctrl+PgUp/PgDn switch lists, F2 shows
## and hides the window, Shift+F2 collapses it. Data: aircraft/c172/checklists.json.

const HILITE := Color(0.25, 0.5, 0.9, 0.5)
const DONE_COL := Color(0.55, 1.0, 0.6)

var lists: Array = []
var current := 0
var _manual := {}  # "list/item" -> true
var _rows: Array = []  # CheckBox per item of the current list
var _state: Array = []  # per row: 0 open, 1 done, +2 when it is the current item
var _cur_item := -2  # index of the highlighted row (-1: all done)
var _hilite := StyleBoxFlat.new()
var _plain := StyleBoxEmpty.new()


func _ready() -> void:
	super()
	var d = Paths.load_res_json("res://aircraft/c172/checklists.json")
	lists = d.lists if d else []
	_hilite.bg_color = HILITE
	_hilite.set_corner_radius_all(5)
	_hilite.border_color = Color(0.6, 0.8, 1.0, 0.9)
	_hilite.border_width_left = 3
	_plain.content_margin_left = 3.0  # same text offset as the highlighted row
	visible = false
	close_requested.connect(func(): visible = false)
	list_step.connect(step_list)
	_rebuild()


func step_list(delta: int) -> void:
	var n := clampi(current + delta, 0, maxi(lists.size() - 1, 0))
	if n != current:
		current = n
		_rebuild()


func _rebuild() -> void:
	for r in _rows:
		body.remove_child(r)
		r.queue_free()
	_rows.clear()
	_state.clear()
	_cur_item = -2
	if lists.is_empty():
		return
	var l: Dictionary = lists[current]
	for i in l.items.size():
		var b := CheckBox.new()
		b.text = l.items[i].text
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		b.add_theme_constant_override("outline_size", 3)
		var key := "%d/%d" % [current, i]
		b.toggled.connect(func(on): _manual[key] = on)
		body.add_child(b)
		_rows.append(b)
		_state.append(-1)
	_refresh()


static func _met(item: Dictionary) -> bool:
	if not item.has("prop"):
		return false
	var v = Props.get_v(item.prop)
	if v == null:
		return false
	if item.has("eq"):
		if item.eq is bool:
			return bool(v) == item.eq
		return is_equal_approx(float(v), float(item.eq))
	if item.has("range"):
		return float(v) >= item.range[0] and float(v) <= item.range[1]
	return false


func is_done(i: int) -> bool:
	return _met(lists[current].items[i]) or _manual.get("%d/%d" % [current, i], false)


## Index of the first item not done in the current list, -1 when the list is complete.
func current_item() -> int:
	if lists.is_empty():
		return -1
	for i in lists[current].items.size():
		if not is_done(i):
			return i
	return -1


func _process(dt: float) -> void:
	super(dt)
	if visible:
		_refresh()


func _refresh() -> void:
	if lists.is_empty():
		return
	var l: Dictionary = lists[current]
	var cur := current_item()
	var n_done := 0
	for i in _rows.size():
		var item: Dictionary = l.items[i]
		var b: CheckBox = _rows[i]
		var auto := _met(item)
		var done: bool = auto or _manual.get("%d/%d" % [current, i], false)
		n_done += 1 if done else 0
		var st := (1 if done else 0) + (2 if i == cur else 0)
		b.set_pressed_no_signal(done)
		b.disabled = auto
		if st != _state[i]:
			_state[i] = st
			_style_row(b, done, i == cur)
	if cur != _cur_item:
		_cur_item = cur
		if cur >= 0:
			ensure_visible(_rows[cur])
	var line := "✓  List complete" if cur < 0 else "▶  " + str(l.items[cur].text)
	set_header(str(l.name), "List %d/%d  ·  %d/%d done" % [current + 1, lists.size(), n_done, _rows.size()], line)


func _style_row(b: CheckBox, done: bool, is_current: bool) -> void:
	var col := DONE_COL if done else Color(1, 1, 1)
	var sb: StyleBox = _hilite if is_current else _plain
	for n in ["normal", "hover", "pressed", "hover_pressed", "disabled", "hover_disabled", "hover_pressed_mirrored"]:
		b.add_theme_stylebox_override(n, sb)
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(n, col)


func _tick_next() -> void:
	var i := current_item()
	if i >= 0:
		_manual["%d/%d" % [current, i]] = true


func _untick_last() -> void:
	for i in range(_rows.size() - 1, -1, -1):
		if _manual.get("%d/%d" % [current, i], false):
			_manual["%d/%d" % [current, i]] = false
			return


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_F2:
		if e.shift_pressed:
			visible = true
			toggle_collapsed()
		else:
			visible = not visible
		get_viewport().set_input_as_handled()
	elif visible and e.ctrl_pressed and e.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		step_list(1 if e.keycode == KEY_PAGEDOWN else -1)
		get_viewport().set_input_as_handled()
	elif visible and e.keycode == KEY_ENTER:
		if e.shift_pressed:
			_untick_last()
		else:
			_tick_next()
		get_viewport().set_input_as_handled()
