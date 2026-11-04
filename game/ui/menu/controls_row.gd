extends VBoxContainer
## One row of the Controls page, Joystick tab: action name (takes the spare width, ellipsis plus tooltip for
## long names), current binding, Bind / clear and a live value bar; for axes also a Tune button that opens a
## second line with invert, range, deadzone and curve (expo). Edits the binding dictionary in place and
## emits `edited`; the page saves. Tune opens by itself for an inverted axis; its tooltip gives the current values.

signal edited
signal bind_requested(action: String)

const W_NAME := 150.0  # minimum
const W_BIND := 150.0

var action := ""
var b := {}  # the binding dictionary (shared with the page's table)
var value := 0.0  # live control value, set by the page each frame
var tune: Control  # the second line (axes only)
var _bind_lbl: Label
var _bind_btn: Button
var _tune_btn: Button
var _inv: CheckButton
var _range: OptionButton
var _dz: SpinBox
var _expo: SpinBox
var _bar: Control


func setup(a: String, binding: Dictionary) -> void:
	action = a
	b = binding
	add_theme_constant_override("separation", 4)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	add_child(line)
	var n := Label.new()
	n.text = InputBindings.LABELS.get(a, a)
	n.tooltip_text = n.text
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	n.custom_minimum_size = Vector2(W_NAME, 0)
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(n)
	_bind_lbl = Label.new()
	_bind_lbl.custom_minimum_size = Vector2(W_BIND, 0)
	_bind_lbl.clip_text = true
	_bind_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(_bind_lbl)
	_bind_btn = _button(line, "Bind", 64, func(): bind_requested.emit(action))
	_button(line, "✕", 36, _clear).tooltip_text = "Clear binding"
	if InputBindings.is_axis(a):
		_tune_btn = _button(line, "⚙ Tune", 84, func(): _show_tune(not tune.visible))
		_tune_btn.toggle_mode = true
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(96, 18)
	_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	line.add_child(_bar)
	if InputBindings.is_axis(a):
		_build_tune()
	refresh()
	if tune and _is_tuned():
		_show_tune(true)


func _build_tune() -> void:
	var t := HBoxContainer.new()
	t.add_theme_constant_override("separation", 16)
	t.visible = false
	tune = t
	add_child(t)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(12, 0)
	t.add_child(pad)
	_inv = CheckButton.new()
	_inv.text = "Invert"
	_inv.toggled.connect(func(on): _edit("invert", on))
	t.add_child(_inv)
	t.add_child(_field("Range"))
	_range = OptionButton.new()
	for r in InputBindings.RANGES:
		_range.add_item(r)
	_range.custom_minimum_size = Vector2(100, 0)
	_range.tooltip_text = "full: centred stick -1..1 · half: lever -1..1 -> 0..1 · trigger: 0..1"
	_range.item_selected.connect(func(i): _edit("range", InputBindings.RANGES[i]))
	t.add_child(_range)
	t.add_child(_field("Deadzone"))
	_dz = _spin(t, 0.0, 0.5, 0.01, "Deadzone", "deadzone")
	t.add_child(_field("Curve"))
	_expo = _spin(t, 0.0, 1.0, 0.05, "Curve (expo): 0 linear, 1 fully cubic", "expo")


func _field(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	return l


func _button(parent: Control, t: String, w: float, f: Callable) -> Button:
	var bt := Button.new()
	bt.text = t
	bt.custom_minimum_size = Vector2(w, 36)
	bt.pressed.connect(f)
	parent.add_child(bt)
	return bt


func _spin(parent: Control, lo: float, hi: float, step: float, tip: String, key: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(96, 0)
	s.tooltip_text = tip
	s.value_changed.connect(func(v): _edit(key, v))
	parent.add_child(s)
	return s


## Opens by itself for an inverted axis (the one setting that is a surprise when hidden).
func _is_tuned() -> bool:
	return bool(b.get("invert", false))


func _summary() -> String:
	return "%s%s range, deadzone %.2f, curve %.2f. Click to edit." % ["Inverted, " if _is_tuned() else "", b.get("range", "full"), float(b.get("deadzone", 0.0)), float(b.get("expo", 0.0))]


func _show_tune(on: bool) -> void:
	tune.visible = on
	_tune_btn.set_pressed_no_signal(on)


func _edit(key: String, v: Variant) -> void:
	b[key] = v
	refresh()
	edited.emit()


func _clear() -> void:
	b["axis" if InputBindings.is_axis(action) else "button"] = -1
	b.guid = ""
	refresh()
	edited.emit()


func set_waiting(on: bool) -> void:
	_bind_btn.text = "…" if on else "Bind"
	_bind_lbl.text = "move / press…" if on else InputBindings.describe(b)


func refresh() -> void:
	_bind_lbl.text = InputBindings.describe(b)
	_bind_lbl.tooltip_text = _bind_lbl.text
	_bind_lbl.add_theme_color_override("font_color",
		MenuTheme.TEXT if InputBindings.describe(b) != "—" else MenuTheme.DIM)
	if _inv:
		_inv.set_pressed_no_signal(bool(b.get("invert", false)))
		_range.select(maxi(InputBindings.RANGES.find(str(b.get("range", "full"))), 0))
		_dz.set_value_no_signal(float(b.get("deadzone", 0.0)))
		_expo.set_value_no_signal(float(b.get("expo", 0.0)))
		_tune_btn.tooltip_text = _summary()


func set_value(v: float) -> void:
	if not is_equal_approx(v, value):
		value = v
		_bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0, 0, 0, 0.35))
	var full := InputBindings.is_axis(action) and str(b.get("range", "full")) == "full"
	var col := Color(MenuTheme.ACCENT, 0.85)
	if full:
		var mid := r.size.x * 0.5
		var w := value * mid
		_bar.draw_rect(Rect2(mid + minf(w, 0.0), 2, absf(w), r.size.y - 4), col)
		_bar.draw_line(Vector2(mid, 0), Vector2(mid, r.size.y), Color(1, 1, 1, 0.4))
	else:
		_bar.draw_rect(Rect2(0, 2, r.size.x * clampf(value, 0.0, 1.0), r.size.y - 4), col)
	_bar.draw_rect(r, Color(1, 1, 1, 0.15), false)
