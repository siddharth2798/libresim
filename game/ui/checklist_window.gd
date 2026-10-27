class_name ChecklistWindow
extends Control
## The floating window that holds the checklist (ui/checklist_panel.gd fills it): drag it by the
## title bar, resize it by any edge or corner, collapse it to one line, close it, make its
## background see-through. Like a window in MSFS. The node is exactly the window's rectangle, so
## the mouse passes through everything outside it. Geometry rules: ui/checklist_geom.gd.
## Position (fractions of the free screen space), size, opacity and collapsed state are kept in
## user options; a window that was never moved docks at the right edge, centred, and keeps clear
## of the 2D instrument panel pieces and the cards.

signal close_requested
signal list_step(delta: int)

const TITLE_H := 30.0
const COLLAPSED_H := 62.0
const INSET := 10.0
const KEY_PREFIX := "checklist_"
const BG := Color(0.04, 0.06, 0.09)

var persist := true  # tests and screenshots switch it off
var opacity := 0.9
var collapsed := false
var body: VBoxContainer
var _rect := Rect2(0, 0, 340, 400)  # expanded rectangle, UI units
var _moved := false
var _frac := Vector2(1.0, 0.5)
var _mode := 0  # 0 idle, 1 dragging, 2 resizing
var _zone := Vector2i.ZERO
var _grab_rect := Rect2()
var _grab_mouse := Vector2.ZERO
var _hover := false
var _style := StyleBoxFlat.new()
var _title: Label
var _progress: Label
var _current: Label
var _scroll: ScrollContainer
var _footer: HBoxContainer
var _nav: HBoxContainer
var _collapse_btn: Button
var _slider: HSlider
var _busy_sig := ""


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	_style.set_corner_radius_all(10)
	_style.set_border_width_all(1)
	_style.border_color = Color(0.5, 0.65, 0.85, 0.5)
	_build()
	_load_state()
	get_viewport().size_changed.connect(relayout)
	UiScale.changed.connect(func(_f): relayout())
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	visibility_changed.connect(_on_visibility)
	relayout()


func _build() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vb.offset_left = INSET
	vb.offset_right = -INSET
	vb.offset_top = 2
	vb.offset_bottom = -4
	vb.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 3)
	add_child(vb)
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = TITLE_H
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	vb.add_child(bar)
	_title = _label(16, Color(1, 0.88, 0.55))
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_title.text = "Checklist"
	bar.add_child(_title)
	_collapse_btn = _button("–", "Collapse to one line (Shift+F2)", toggle_collapsed)
	bar.add_child(_collapse_btn)
	bar.add_child(_button("×", "Close (F2)", func(): close_requested.emit()))
	var nav := HBoxContainer.new()
	_nav = nav
	nav.mouse_filter = MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 6)
	vb.add_child(nav)
	nav.add_child(_button("‹", "Previous list (Ctrl+PgUp)", func(): list_step.emit(-1), 26))
	_progress = _label(13, Color(0.75, 0.85, 0.95))
	_progress.size_flags_horizontal = SIZE_EXPAND_FILL
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(_progress)
	nav.add_child(_button("›", "Next list (Ctrl+PgDn)", func(): list_step.emit(1), 26))
	_current = _label(14, Color(1, 1, 1))
	_current.visible = false
	_current.autowrap_mode = TextServer.AUTOWRAP_OFF
	_current.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(_current)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	vb.add_child(_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 1)
	_scroll.add_child(body)
	_footer = HBoxContainer.new()
	_footer.mouse_filter = MOUSE_FILTER_IGNORE
	_footer.add_theme_constant_override("separation", 6)
	vb.add_child(_footer)
	var cap := _label(12, Color(0.7, 0.78, 0.86))
	cap.text = "Opacity"
	cap.custom_minimum_size.x = 46
	_footer.add_child(cap)
	_slider = HSlider.new()
	_slider.min_value = ChecklistGeom.OPACITY_MIN
	_slider.max_value = ChecklistGeom.OPACITY_MAX
	_slider.step = 0.05
	_slider.value = opacity
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	_slider.size_flags_vertical = SIZE_SHRINK_CENTER
	_slider.tooltip_text = "Background opacity; the text stays fully readable"
	_slider.value_changed.connect(func(v: float): set_opacity(v, false))
	_slider.drag_ended.connect(func(_c: bool): _save())
	_footer.add_child(_slider)
	var grip := Control.new()  # leaves the bottom-right resize corner free
	grip.custom_minimum_size = Vector2(14, 0)
	grip.mouse_filter = MOUSE_FILTER_IGNORE
	_footer.add_child(grip)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _button(text: String, tip: String, cb: Callable, w := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 24)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


# --- content hooks for the subclass -------------------------------------------------------------

func set_header(title: String, progress: String, current_line: String) -> void:
	_title.text = title
	_progress.text = progress
	_current.text = current_line


func ensure_visible(c: Control) -> void:
	if is_inside_tree() and not collapsed:
		_scroll_to.call_deferred(c)


func _scroll_to(c: Control) -> void:
	if is_instance_valid(c) and _scroll.is_ancestor_of(c):  # the list may have been rebuilt meanwhile
		_scroll.ensure_control_visible(c)


# --- state and placement ------------------------------------------------------------------------

func _vp() -> Vector2:
	return get_viewport_rect().size


func set_opacity(v: float, save := true) -> void:
	opacity = ChecklistGeom.clamp_opacity(v)
	_style.bg_color = Color(BG, 0.28 + 0.68 * (opacity - ChecklistGeom.OPACITY_MIN) / (ChecklistGeom.OPACITY_MAX - ChecklistGeom.OPACITY_MIN))
	if _slider != null and not is_equal_approx(_slider.value, opacity):
		_slider.set_value_no_signal(opacity)
	queue_redraw()
	if save:
		_save()


func toggle_collapsed() -> void:
	set_collapsed(not collapsed)


func set_collapsed(on: bool) -> void:
	collapsed = on
	_scroll.visible = not on
	_footer.visible = not on
	_nav.visible = not on
	_current.visible = on
	_collapse_btn.text = "+" if on else "–"
	_collapse_btn.tooltip_text = ("Expand" if on else "Collapse to one line") + " (Shift+F2)"
	relayout()
	_save()


## The window's rectangle as drawn now (collapsed windows keep their top-left corner and width).
func shown_rect() -> Rect2:
	return Rect2(_rect.position, Vector2(_rect.size.x, COLLAPSED_H) if collapsed else _rect.size)


func relayout() -> void:
	var vp := _vp()
	if _moved:
		_rect = ChecklistGeom.from_fraction(_frac, _rect.size, vp)
	else:
		_rect = ChecklistGeom.default_rect(ChecklistGeom.fit_size(_rect.size, vp), vp, _busy())
	_apply()


func _apply() -> void:
	var r := shown_rect()
	set_anchors_preset(PRESET_TOP_LEFT)
	position = r.position
	size = r.size
	queue_redraw()


## Rectangles the default dock keeps clear of: the 2D instrument panel pieces, the training
## card, the always-present top-centre UI.
func _busy() -> Array:
	var out: Array = AtcLayout.reserved(_vp())
	var ui := get_parent()
	if ui == null:
		return out
	var overlay := ui.get_node_or_null("Panel")
	if overlay != null and overlay.visible and overlay.get("_pieces") != null:
		for p in overlay._pieces:
			if p[0].visible:
				out.append(p[0].get_global_rect())
	for ch in ui.get_children():
		if ch is TrainingHud and ch.visible:
			var card: Control = ch.get("_card")
			if card != null and card.visible:
				out.append(card.get_global_rect())
	return out


func _process(_dt: float) -> void:
	if not visible or _moved or _mode != 0:
		return
	var sig := str(_vp())  # cheap change check: panel layout, training card, window size
	for b: Rect2 in _busy():
		sig += str(b)
	if sig != _busy_sig:
		_busy_sig = sig
		relayout()


func _on_visibility() -> void:
	if visible:
		_busy_sig = ""
		relayout()
	else:
		_mode = 0
		_hover = false
		Props.set_v("ui/checklist_grab", false)


func _set_hover(on: bool) -> void:
	_hover = on
	Props.set_v("ui/checklist_grab", _hover or _mode != 0)  # the mouse yoke holds still over the window


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	_style.draw(get_canvas_item(), r)
	draw_rect(Rect2(1, 1, size.x - 2, TITLE_H), Color(1, 1, 1, 0.07))
	for i in 3:  # resize grip: three short diagonal strokes bottom-right
		var o := 5.0 + i * 4.0
		draw_line(Vector2(size.x - o - 2, size.y - 4), Vector2(size.x - 4, size.y - o - 2), Color(1, 1, 1, 0.45), 1.0)


# --- mouse: drag, resize, cursor ----------------------------------------------------------------

func _zone_here(local: Vector2) -> Vector2i:
	var z := ChecklistGeom.zone_at(local, size)
	if collapsed:
		z.y = 0
	return z


static func cursor_for(z: Vector2i) -> int:
	if z.x != 0 and z.y != 0:
		return Control.CURSOR_FDIAGSIZE if z.x == z.y else Control.CURSOR_BDIAGSIZE
	if z.x != 0:
		return Control.CURSOR_HSIZE
	if z.y != 0:
		return Control.CURSOR_VSIZE
	return Control.CURSOR_ARROW


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and _mode == 0:
			_zone = _zone_here(e.position)
			_mode = 2 if _zone != Vector2i.ZERO else 1
			_grab_rect = _rect
			_grab_mouse = e.global_position
			if _mode == 1:
				mouse_default_cursor_shape = Control.CURSOR_MOVE
			_set_hover(_hover)
		elif not e.pressed and _mode != 0:
			_end_grab()
		accept_event()
	elif e is InputEventMouseMotion:
		if _mode == 0:
			mouse_default_cursor_shape = cursor_for(_zone_here(e.position)) as Control.CursorShape
		else:
			_grab_move(e.global_position - _grab_mouse)
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and e.position.y < TITLE_H:
		set_opacity(opacity + (0.05 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.05))  # wheel on the title bar: opacity
		accept_event()


func _grab_move(delta: Vector2) -> void:
	var vp := _vp()
	if _mode == 1:
		_rect = ChecklistGeom.clamp_rect(Rect2(_grab_rect.position + delta, _grab_rect.size), vp)
	else:
		var z := _zone
		_rect = ChecklistGeom.resize(_grab_rect, z, delta, vp)
	_apply()


func _end_grab() -> void:
	if _mode == 1:
		_rect = ChecklistGeom.snap(_rect, _vp())
	_mode = 0
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_moved = true
	_frac = ChecklistGeom.fraction_of(_rect, _vp())
	_apply()
	_set_hover(_hover)
	_save()


# --- persistence --------------------------------------------------------------------------------

func _load_state() -> void:
	if not persist:
		set_opacity(opacity, false)
		return
	var fx := float(UserOptions.get_v(KEY_PREFIX + "x"))
	var fy := float(UserOptions.get_v(KEY_PREFIX + "y"))
	_moved = fx >= 0.0 and fy >= 0.0
	_frac = Vector2(fx, fy)
	var w := float(UserOptions.get_v(KEY_PREFIX + "w"))
	var h := float(UserOptions.get_v(KEY_PREFIX + "h"))
	_rect.size = Vector2(w, h) if w > 0.0 and h > 0.0 else ChecklistGeom.default_size(_vp())
	set_opacity(float(UserOptions.get_v(KEY_PREFIX + "opacity")), false)
	if bool(UserOptions.get_v(KEY_PREFIX + "collapsed")):
		set_collapsed(true)


func _save() -> void:
	if not persist:
		return
	UserOptions.set_v(KEY_PREFIX + "x", _frac.x if _moved else -1.0)
	UserOptions.set_v(KEY_PREFIX + "y", _frac.y if _moved else -1.0)
	UserOptions.set_v(KEY_PREFIX + "w", _rect.size.x)
	UserOptions.set_v(KEY_PREFIX + "h", _rect.size.y)
	UserOptions.set_v(KEY_PREFIX + "opacity", opacity)
	UserOptions.set_v(KEY_PREFIX + "collapsed", collapsed)


## Put the window somewhere definite (tests, screenshots): fractions, expanded size, opacity, collapsed.
func set_placement(frac: Vector2, win_size: Vector2, op: float, coll: bool) -> void:
	_moved = true
	_frac = frac
	_rect.size = ChecklistGeom.fit_size(win_size, _vp())
	set_opacity(op, false)
	set_collapsed(coll)
