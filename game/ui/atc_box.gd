class_name AtcBox
extends PanelContainer
## The radio widget (top-left): a slim bar by default (COM1 frequency and the unit it reaches, the
## suggested next call, the latest controller message for a while; click it or press ` to open),
## and when open a short list of calls (the suggested one first and highlighted) with a small
## row of extras (Say again, History, Voice), or the scrollable history instead of the list.
## Draws what atc_panel.gd hands over in show_model(); it decides nothing and emits signals.

signal open_requested
signal picked(index: int)
signal hovered(index: int)
signal history_toggled
signal again_requested
signal voice_toggled

const ACCENT := Color(0.3, 0.85, 0.75)
const TONES := {"ok": Color(0.62, 0.94, 0.7), "warn": Color(1.0, 0.8, 0.42), "dim": Color(0.66, 0.74, 0.82), "dead": Color(1.0, 0.45, 0.4)}
const TEXT := Color(0.9, 0.93, 0.95)
const DIM := Color(0.62, 0.7, 0.78)
const HIST_H := 198.0  # keeps the open history (about 282 px tall) above the checklist at y=300
const MAX_ROWS := 4

var menu: VBoxContainer  # everything that shows while the radio is open
var _open := false
var _freq: Label
var _unit: Label
var _chip: Label
var _next: Label
var _msg: Label
var _list: VBoxContainer
var _rows: Array[Button] = []
var _note: Label
var _hist: AtcTranscript
var _b_again: Button
var _b_hist: Button
var _b_voice: Button
var _keys: Label


func _init() -> void:
	var st := Notifications.card_style(ACCENT)
	st.content_margin_left = 14
	st.content_margin_right = 12
	st.content_margin_top = 7
	st.content_margin_bottom = 7
	add_theme_stylebox_override("panel", st)
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_child(head)
	_freq = _label(head, 16, TEXT)
	_freq.clip_text = false
	_freq.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING  # trimming would let the HBox squeeze it to nothing
	_unit = _label(head, 16, TONES.ok)
	_unit.size_flags_horizontal = SIZE_EXPAND_FILL
	_chip = _label(head, 13, DIM)
	_chip.clip_text = false
	_chip.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(1, 1, 1, 0.09)
	chip_style.set_corner_radius_all(5)
	chip_style.content_margin_left = 7
	chip_style.content_margin_right = 7
	chip_style.content_margin_top = 1
	chip_style.content_margin_bottom = 1
	_chip.add_theme_stylebox_override("normal", chip_style)
	_next = _label(vb, 15, Color(0.58, 0.86, 1.0))
	_msg = _label(vb, 15, Color(0.78, 0.9, 0.82))
	menu = VBoxContainer.new()
	menu.add_theme_constant_override("separation", 3)
	menu.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_child(menu)
	_build_menu()
	visible = false


func _label(parent: Control, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_menu() -> void:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.3)
	sep.mouse_filter = MOUSE_FILTER_IGNORE
	menu.add_child(sep)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	menu.add_child(_list)
	for i in MAX_ROWS:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 16)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color(0.92, 0.95, 0.97))
		b.pressed.connect(func(): picked.emit(i))
		b.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseMotion:  # moving the mouse over a row highlights it (a resting cursor does not)
				hovered.emit(i))
		_list.add_child(b)
		_rows.append(b)
	_note = _label(menu, 14, Color(0.58, 0.82, 0.95))
	_note.clip_text = false
	_note.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hist = AtcTranscript.new()
	_hist.mouse_filter = MOUSE_FILTER_STOP
	menu.add_child(_hist)
	var sec := HBoxContainer.new()
	sec.add_theme_constant_override("separation", 4)
	menu.add_child(sec)
	_b_again = _small(sec, again_requested)
	_b_hist = _small(sec, history_toggled)
	_b_voice = _small(sec, voice_toggled)
	_keys = _label(menu, 13, Color(0.5, 0.58, 0.66))
	_keys.clip_text = false
	_keys.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## A small flat button of the extras row.
func _small(parent: Control, sig: Signal) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(0.72, 0.82, 0.9))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.5, 0.55))
	b.pressed.connect(func(): sig.emit())
	parent.add_child(b)
	return b


func _on_gui_input(e: InputEvent) -> void:
	if not _open and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		open_requested.emit()
		accept_event()


func _row_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28) if selected else Color(1, 1, 1, 0.0)
	s.set_corner_radius_all(6)
	s.border_width_left = 3 if selected else 0
	s.border_color = ACCENT
	s.content_margin_left = 10
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


## Draw a state. Keys: width, open, history, freq, unit, tone, hint, msg, actions (labels), sel,
## note, log, can_again, voice, keys.
func show_model(m: Dictionary) -> void:
	_open = bool(m.open)
	var hist: bool = _open and bool(m.history)
	var inner: float = float(m.width) - 26.0
	custom_minimum_size.x = float(m.width)
	_freq.text = "COM1 %s" % m.freq
	_unit.text = "·  %s" % m.unit
	_unit.add_theme_color_override("font_color", TONES[m.tone])
	_chip.text = "`  close" if _open else "`  Radio"
	var acts: Array = m.actions
	_next.text = str(m.hint)
	_next.visible = str(m.hint) != "" and (not _open or (not hist and acts.is_empty()))
	_msg.text = str(m.msg)
	_msg.visible = not _open and str(m.msg) != ""
	menu.visible = _open
	mouse_default_cursor_shape = Control.CURSOR_ARROW if _open else Control.CURSOR_POINTING_HAND
	if _open:
		_show_menu(m, hist, inner)
	visible = true


func _show_menu(m: Dictionary, hist: bool, inner: float) -> void:
	var acts: Array = m.actions
	_list.visible = not hist
	for i in MAX_ROWS:
		var b := _rows[i]
		b.visible = i < acts.size()
		if i < acts.size():
			b.text = "%d   %s" % [i + 1, acts[i]]
			b.custom_minimum_size.x = inner
			var sel: bool = i == int(m.sel)
			b.add_theme_stylebox_override("normal", _row_style(sel))
			b.add_theme_stylebox_override("hover", _row_style(true))
			b.add_theme_stylebox_override("pressed", _row_style(true))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_note.text = str(m.note)
	_note.custom_minimum_size.x = inner
	_note.visible = not hist and str(m.note) != ""
	_hist.visible = hist
	_hist.custom_minimum_size = Vector2(inner, HIST_H)
	if hist:
		_hist.show_log(m.log)
	_b_again.text = "Say again  (A)"
	_b_again.disabled = not bool(m.can_again)
	_b_hist.text = "Calls  (H)" if hist else "History  (H)"
	_b_voice.text = "%s  (V)" % str(m.voice)
	_keys.text = str(m.keys)
	_keys.custom_minimum_size.x = inner


func history_view() -> AtcTranscript:
	return _hist


func rows() -> Array[Button]:
	return _rows
