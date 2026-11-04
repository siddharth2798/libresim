class_name SwitchRow
extends HBoxContainer
## Shared start-screen control: a title with an optional description and a switch (a pill with a knob) at the left.
## The whole row is the control: a click anywhere on it, or Space / Enter while it has the focus, flips it. On is
## the accent track with the knob at the right and a tick in it, off is a grey track with the knob at the left, so
## the state is not only a colour. The row keeps no state outside itself: pages listen to `toggled` and write the
## value into Session.setup.
##
## API
##   setup(title, description := "", on := false) -> SwitchRow
##   set_on(bool)           change the state without emitting `toggled`
##   is_on() -> bool
##   set_disabled(bool)     dim the row, no focus, no clicks (`disabled` property does the same)
##   set_title(text), set_description(text)   (an empty description hides its line)
##   tooltip_text           the row's hover text (a normal Control property)
##   signal toggled(on)     the player flipped the switch (not on set_on)
## Pure helpers (headless tests): next_state, knob_x.

signal toggled(on: bool)

const TRACK := Vector2(46, 26)
const KNOB := 18.0
const PAD := 4.0
const MARGIN := 6.0  # space round the content inside the row (the title starts at MARGIN + 46 + 12)

var on := false
var disabled := false:
	set = set_disabled

var _title := Label.new()
var _desc := Label.new()
var _track := _Track.new()
var _hover := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var inner := MarginContainer.new()  # room for the hover fill and the focus ring inside the row's own rectangle
	inner.size_flags_horizontal = SIZE_EXPAND_FILL
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, int(MARGIN))
	add_child(inner)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(body)
	_track.owner_row = self
	_track.custom_minimum_size = TRACK
	_track.size_flags_vertical = SIZE_SHRINK_BEGIN
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_track)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(col)
	_title.add_theme_font_override("font", MenuTheme.font("medium"))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(120, 0)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)
	_desc.add_theme_color_override("font_color", MenuTheme.DIM)
	_desc.add_theme_font_size_override("font_size", MenuTheme.SIZE_NOTE)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(120, 0)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc.visible = false
	col.add_child(_desc)
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func setup(title: String, description := "", initial := false) -> SwitchRow:
	set_title(title)
	set_description(description)
	set_on(initial)
	return self


## A narrow row (a short title such as "Mute" in a table cell): lets the title take less than the usual 120 px minimum.
func compact(title_min_w := 40.0) -> SwitchRow:
	_title.custom_minimum_size.x = title_min_w
	_desc.custom_minimum_size.x = title_min_w
	return self


func set_title(text: String) -> void:
	_title.text = text


func set_description(text: String) -> void:
	_desc.text = text
	_desc.visible = text != ""


func set_on(v: bool) -> void:
	on = v
	_track.queue_redraw()


func is_on() -> bool:
	return on


func set_disabled(d: bool) -> void:
	disabled = d
	focus_mode = Control.FOCUS_NONE if d else Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_ARROW if d else Control.CURSOR_POINTING_HAND
	modulate.a = 0.5 if d else 1.0


func _gui_input(e: InputEvent) -> void:
	var click: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	if click or e.is_action_pressed("ui_accept"):
		_flip()
		accept_event()


func _flip() -> void:
	var v := next_state(on, disabled)
	if v == on:
		return
	set_on(v)
	toggled.emit(v)


func _draw() -> void:
	if _hover and not disabled:
		draw_style_box(MenuTheme.box(Color(1, 1, 1, 0.06), 8), Rect2(Vector2.ZERO, size))
	if has_focus():
		draw_style_box(MenuTheme.focus_box(8), Rect2(Vector2(2, 2), size - Vector2(4, 4)))  # inside the row: a parent that clips must not cut the ring


## The state after a click or key: unchanged while disabled.
static func next_state(is_on: bool, is_disabled: bool) -> bool:
	return is_on if is_disabled else not is_on


## x of the knob's left edge inside a track of width `w`.
static func knob_x(is_on: bool, w: float, knob: float, pad: float) -> float:
	return w - knob - pad if is_on else pad


## The pill and its knob (drawn, no theme parts), reads the row's state.
class _Track extends Control:
	var owner_row: SwitchRow

	func _draw() -> void:
		var is_on: bool = owner_row != null and owner_row.on
		var r := Rect2(Vector2.ZERO, SwitchRow.TRACK)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(int(SwitchRow.TRACK.y / 2.0))
		sb.bg_color = MenuTheme.ACCENT if is_on else Color(1, 1, 1, 0.20)
		sb.border_color = MenuTheme.ACCENT if is_on else Color(1, 1, 1, 0.38)
		sb.set_border_width_all(1)
		draw_style_box(sb, r)
		var kx := SwitchRow.knob_x(is_on, r.size.x, SwitchRow.KNOB, SwitchRow.PAD)
		var c := Vector2(kx + SwitchRow.KNOB / 2.0, r.size.y / 2.0)
		draw_circle(c, SwitchRow.KNOB / 2.0, MenuTheme.ACCENT_INK if is_on else MenuTheme.TEXT)
		if is_on:  # a tick in the knob: the state is also a shape
			draw_polyline(PackedVector2Array([c + Vector2(-4, 0.5), c + Vector2(-1, 3.5), c + Vector2(4.5, -3)]), MenuTheme.ACCENT, 2.0, true)
