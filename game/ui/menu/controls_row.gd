extends HBoxContainer
## One row of the controls page: action name, current binding, Bind / clear, and for
## axes invert, range, deadzone, curve (expo) and Lo / Hi calibration, plus a live value bar.
## Edits the binding dictionary in place and emits `edited`; the page saves.

signal edited
signal bind_requested(action: String)

const W_NAME := 160.0
const W_BIND := 140.0

var action := ""
var b := {}  # the binding dictionary (shared with the page's table)
var value := 0.0  # live control value, set by the page each frame
var _bind_lbl: Label
var _bind_btn: Button
var _inv: CheckBox
var _range: OptionButton
var _dz: SpinBox
var _expo: SpinBox
var _lo: Button
var _hi: Button
var _bar: Control


func setup(a: String, binding: Dictionary) -> void:
	action = a
	b = binding
	add_theme_constant_override("separation", 8)
	var n := Label.new()
	n.text = InputBindings.LABELS.get(a, a)
	n.custom_minimum_size = Vector2(W_NAME, 0)
	n.clip_text = true
	add_child(n)
	_bind_lbl = Label.new()
	_bind_lbl.custom_minimum_size = Vector2(W_BIND, 0)
	_bind_lbl.clip_text = true
	add_child(_bind_lbl)
	_bind_btn = _button("Bind", 64, func(): bind_requested.emit(action))
	_button("✕", 34, _clear).tooltip_text = "Clear binding"
	if InputBindings.is_axis(a):
		_inv = CheckBox.new()
		_inv.text = "Inv"
		_inv.toggled.connect(func(on): _edit("invert", on))
		add_child(_inv)
		_range = OptionButton.new()
		for r in InputBindings.RANGES:
			_range.add_item(r)
		_range.custom_minimum_size = Vector2(96, 0)
		_range.tooltip_text = "full: centred stick -1..1 · half: lever -1..1 -> 0..1 · trigger: 0..1"
		_range.item_selected.connect(func(i): _edit("range", InputBindings.RANGES[i]))
		add_child(_range)
		_dz = _spin(0.0, 0.5, 0.01, "Deadzone", "deadzone")
		_expo = _spin(0.0, 1.0, 0.05, "Curve (expo): 0 linear, 1 fully cubic", "expo")
		_lo = _button("Lo", 40, _calibrate.bind("lo"))
		_hi = _button("Hi", 40, _calibrate.bind("hi"))
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(90, 18)
	_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	refresh()


func _button(t: String, w: float, f: Callable) -> Button:
	var bt := Button.new()
	bt.text = t
	bt.custom_minimum_size = Vector2(w, 0)
	bt.pressed.connect(f)
	add_child(bt)
	return bt


func _spin(lo: float, hi: float, step: float, tip: String, key: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(84, 0)
	s.tooltip_text = tip
	s.prefix = "dz" if key == "deadzone" else "ex"
	s.value_changed.connect(func(v): _edit(key, v))
	add_child(s)
	return s


func _edit(key: String, v: Variant) -> void:
	b[key] = v
	refresh()
	edited.emit()


## Take the axis's current position as the low (idle, closed) or high (full) end of its travel.
func _calibrate(key: String) -> void:
	var raw = InputBindings.raw_value(b)
	if raw != null:
		_edit(key, snappedf(raw, 0.001))


func _clear() -> void:
	b["axis" if InputBindings.is_axis(action) else "button"] = -1
	b.guid = ""
	b.name = ""
	b.erase("lo")
	b.erase("hi")
	refresh()
	edited.emit()


func set_waiting(on: bool) -> void:
	_bind_btn.text = "…" if on else "Bind"
	_bind_lbl.text = "move / press…" if on else InputBindings.describe(b)


func refresh() -> void:
	_bind_lbl.text = InputBindings.describe(b)
	_bind_lbl.add_theme_color_override("font_color",
		MenuTheme.TEXT if InputBindings.describe(b) != "—" else MenuTheme.DIM)
	if _inv:
		_inv.set_pressed_no_signal(bool(b.get("invert", false)))
		_range.select(maxi(InputBindings.RANGES.find(str(b.get("range", "full"))), 0))
		_dz.set_value_no_signal(float(b.get("deadzone", 0.0)))
		_expo.set_value_no_signal(float(b.get("expo", 0.0)))
		for k in [[_lo, "lo", "Lo"], [_hi, "hi", "Hi"]]:
			k[0].tooltip_text = "Set %s end of travel from the lever's current position%s" % [
				"the low (idle)" if k[1] == "lo" else "the high (full)",
				" (now %.2f)" % float(b[k[1]]) if b.has(k[1]) else " (not set)"]
			k[0].text = k[2] + ("*" if b.has(k[1]) else "")


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
