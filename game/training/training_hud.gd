class_name TrainingHud
extends Control
## Training overlay: the lesson card (steps, current instruction and hint), live target
## gauges (value against target and tolerance), and the result card with stars at the end
## (or, when the lesson cannot be finished any more, the "not completed" card).

signal retry
signal next_lesson
signal to_menu

const ACCENT := Color(0.35, 0.75, 1.0)
const GOOD := Color(0.35, 0.9, 0.45)
const WARN := Color(1.0, 0.72, 0.2)
const BAD := Color(1.0, 0.4, 0.35)
const DIM := Color(0.62, 0.66, 0.72)

var _lesson: Dictionary
var _assist := "full"
var _card: PanelContainer
var _title: Label
var _list: VBoxContainer
var _instr: Label
var _hint: Label
var _gauges_box: VBoxContainer
var _gauges: Array = []
var _cur := 0
var _result: PanelContainer
var _wrap: Control  # centring container around the result card


## One horizontal target gauge: the marker's position within [min, max], the tolerance band
## around the target in green, the marker green inside the band and amber outside.
class BarGauge extends Control:
	var g: Dictionary
	var v := 0.0

	func _init(def: Dictionary) -> void:
		g = def
		custom_minimum_size = Vector2(330, 38)

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var lo := float(g.min)
		var hi := float(g.max)
		var w := size.x
		var x := func(val: float) -> float: return clampf((val - lo) / (hi - lo), 0.0, 1.0) * w
		draw_string(f, Vector2(0, 14), str(g.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.88, 0.92))
		var unit: String = g.get("unit", "")
		var txt := ("%.1f" % v if absf(float(g.max) - float(g.min)) <= 12.0 else "%.0f" % v) + (" " + unit if unit != "" else "")
		draw_string(f, Vector2(0, 14), txt, HORIZONTAL_ALIGNMENT_RIGHT, w, 14, Color(1, 1, 1))
		var y := 24.0
		draw_rect(Rect2(0, y, w, 8), Color(1, 1, 1, 0.12))
		var t := float(g.target)
		var tol := float(g.tol)
		draw_rect(Rect2(x.call(t - tol), y, x.call(t + tol) - x.call(t - tol), 8), Color(GOOD, 0.45))
		draw_line(Vector2(x.call(t), y - 3), Vector2(x.call(t), y + 11), Color(1, 1, 1, 0.8), 2.0)
		var ok := absf(v - t) <= tol
		var col := GOOD if ok else (WARN if absf(v - t) <= tol * 2.5 else Color(1.0, 0.35, 0.3))
		var mx: float = x.call(v)
		draw_colored_polygon(PackedVector2Array([Vector2(mx, y + 9), Vector2(mx - 6, y + 20), Vector2(mx + 6, y + 20)]), col)


func setup(lesson: Dictionary, assist: String) -> void:
	_lesson = lesson
	_assist = assist
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	var st := Notifications.card_style(ACCENT)
	st.bg_color = Color(0.05, 0.07, 0.1, 0.86)
	_card.add_theme_stylebox_override("panel", st)
	_card.position = Vector2(16, 70)
	_card.custom_minimum_size = Vector2(372, 0)
	_card.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_card.add_child(vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", ACCENT)
	vb.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	vb.add_child(_list)
	vb.add_child(HSeparator.new())
	_instr = _label(vb, 18, Color(1, 1, 1))
	_hint = _label(vb, 14, DIM)
	_gauges_box = VBoxContainer.new()
	_gauges_box.add_theme_constant_override("separation", 2)
	vb.add_child(_gauges_box)


func _label(parent: Control, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(330, 0)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func show_step(idx: int) -> void:
	_cur = idx
	var steps: Array = _lesson.steps
	_title.text = "%s  ·  STEP %d OF %d" % [str(_lesson.title).to_upper(), idx + 1, steps.size()]
	_fill_list(idx, false)
	_instr.text = str(steps[idx].text)
	_hint.text = str(steps[idx].get("hint", "")) if _assist != "off" else ""
	_hint.visible = _hint.text != ""
	for c in _gauges_box.get_children():
		c.queue_free()
	_gauges.clear()
	if _assist == "full":
		for g in steps[idx].get("gauges", []):
			var bg := BarGauge.new(g)
			_gauges_box.add_child(bg)
			_gauges.append(bg)


## Step list: done ticked, current marked (a cross when the lesson ended on it), the rest open.
func _fill_list(idx: int, ended: bool) -> void:
	for c in _list.get_children():
		c.queue_free()
	var steps: Array = _lesson.steps
	for i in steps.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 14)
		var mark := "✓  " if i < idx else (("✗  " if ended else "▶  ") if i == idx else "○  ")
		l.text = mark + str(steps[i].title)
		l.add_theme_color_override("font_color", GOOD if i < idx else ((BAD if ended else Color(1, 1, 1)) if i == idx else DIM))
		_list.add_child(l)


## A new attempt (F5 / Try again): the lesson card is back and any result card is gone.
func reset() -> void:
	_clear_result()
	_card.visible = true
	_title.add_theme_color_override("font_color", ACCENT)


func _clear_result() -> void:
	if is_instance_valid(_wrap):
		_wrap.queue_free()
	_wrap = null
	_result = null


func update_gauges(snap: Dictionary, s0: Dictionary) -> void:
	for bg in _gauges:
		bg.v = TrainingLogic.value(snap, s0, bg.g.metric)
		bg.queue_redraw()


## The centred result card (replaces the lesson card); returns its VBox.
func _result_panel(accent: Color) -> VBoxContainer:
	_clear_result()
	_card.visible = false
	_result = PanelContainer.new()
	var st := Notifications.card_style(accent)
	st.border_width_left = 0
	st.border_width_top = 4
	st.bg_color = Color(0.06, 0.07, 0.09, 0.95)
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	_result.add_theme_stylebox_override("panel", st)
	_result.mouse_filter = MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_result.add_child(vb)
	_wrap = Notifications.centered(_result, PRESET_FULL_RECT, 0)
	add_child(_wrap)
	return vb


func _buttons(vb: VBoxContainer, has_next: bool) -> void:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var buttons := [["Try again", func(): retry.emit()], ["Keep flying", func(): _clear_result()], ["Menu", func(): to_menu.emit()]]
	if has_next:
		buttons.insert(1, ["Next lesson ▶", func(): next_lesson.emit()])
	for bd in buttons:
		var btn := Button.new()
		btn.text = bd[0]
		btn.custom_minimum_size = Vector2(130, 40)
		btn.pressed.connect(bd[1])
		hb.add_child(btn)


func _title_label(vb: VBoxContainer, text: String) -> void:
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)


func show_result(grade: Dictionary, has_next: bool) -> void:
	var vb := _result_panel(GOOD)
	_title_label(vb, "%s complete" % _lesson.title)
	var stars := Label.new()
	stars.text = "★".repeat(grade.stars) + "☆".repeat(3 - grade.stars)
	stars.add_theme_font_size_override("font_size", 40)
	stars.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(stars)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	vb.add_child(grid)
	for it in grade.items:
		var a := Label.new()
		a.text = str(it.label)
		grid.add_child(a)
		var b := Label.new()
		b.text = "—" if is_nan(it.value) else ("%.0f %s" % [it.value, it.unit])
		b.add_theme_color_override("font_color", DIM)
		grid.add_child(b)
		var c := Label.new()
		c.text = ["✗  Needs work", "~  OK", "✓  Good"][it.points]
		c.add_theme_color_override("font_color", [BAD, WARN, GOOD][it.points])
		grid.add_child(c)
	_buttons(vb, has_next)


## The lesson cannot be finished any more (touched down early, left the approach ...): why, what
## was done, what to work on. `info` is TrainingLogic.abort().
func show_incomplete(info: Dictionary) -> void:
	var vb := _result_panel(WARN)
	_title_label(vb, str(info.title))
	var why := _label(vb, 18, Color(1, 1, 1))
	why.text = str(info.reason)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	why.custom_minimum_size = Vector2(440, 0)
	for st in info.steps:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 14)
		l.text = ["✓  ", "✗  ", "○  "][["done", "current", "todo"].find(st.state)] + str(st.title) + ("   (not completed)" if st.state == "current" else "")
		l.add_theme_color_override("font_color", {"done": GOOD, "current": BAD, "todo": DIM}[st.state])
		vb.add_child(l)
	var tip := _label(vb, 14, DIM)
	tip.text = ("To improve: " + str(info.tip) + "\n" if str(info.tip) != "" else "") + str(info.hint)
	tip.custom_minimum_size = Vector2(440, 0)
	_buttons(vb, false)


## Compact ending on the lesson card itself (a crash: the crash card owns the buttons, F5 retries).
func show_ended(info: Dictionary) -> void:
	_title.text = "%s  ·  ENDED" % str(_lesson.title).to_upper()
	_title.add_theme_color_override("font_color", BAD)
	_fill_list(int(info.step), true)
	_instr.text = str(info.reason)
	_hint.text = ("To improve: " + str(info.tip) + "\n" if str(info.tip) != "" else "") + "Press F5 to try the lesson again."
	_hint.visible = true
	for c in _gauges_box.get_children():
		c.queue_free()
	_gauges.clear()
