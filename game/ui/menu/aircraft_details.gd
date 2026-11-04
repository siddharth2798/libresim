class_name AircraftDetails
extends PanelContainer
## The "Full specification" overlay of the Aircraft step: the aircraft's description, every specification row, the model credit
## and the registration note, on a card over a dark scrim that covers the window. Esc, the Close button or a click on the scrim
## closes it. The page it belongs to (aircraft_page.gd) adds it as a child; it is a top-level Control, so it ignores the page's
## layout and fills the whole window.
##   show_aircraft(j)   fill it from an aircraft.json dictionary (AircraftDef.data)
##   open() / close()   `opened` is true while it is on screen; the signal `closed` fires when it goes away

signal closed

var opened := false

var _card: PanelContainer
var _title: Label
var _sub: Label
var _desc: Label
var _grid: GridContainer
var _credit: Label
var _reg: Label
var _close: Button


func _init() -> void:
	top_level = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel", MenuTheme.box(Color(0.0, 0.0, 0.0, 0.62), 0, Color(0, 0, 0, 0), 0.0))
	var m := CenterContainer.new()  # the card keeps its own size in the middle of the window
	add_child(m)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(820, 0)
	_card.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.035, 0.05, 0.075, 0.97), 16, MenuTheme.LINE, 24.0))
	m.add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	_title = Label.new()
	MenuTheme.use_font(_title, "semibold", MenuTheme.SIZE_TITLE)
	names.add_child(_title)
	_sub = MenuTheme.note("")
	names.add_child(_sub)
	_close = Button.new()
	_close.text = "Close  ✕"
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.pressed.connect(close)
	head.add_child(_close)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 340)  # a long specification scrolls inside the card
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	sc.add_child(body)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", MenuTheme.SIZE_BODY)
	body.add_child(_desc)
	body.add_child(MenuTheme.heading("Specification"))
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 4)
	body.add_child(_grid)
	_credit = MenuTheme.note("")
	_credit.add_theme_font_size_override("font_size", 12)
	body.add_child(_credit)
	_reg = MenuTheme.note("")
	_reg.add_theme_font_size_override("font_size", 12)
	body.add_child(_reg)


func show_aircraft(j: Dictionary) -> void:
	_title.text = str(j.get("name", ""))
	_sub.text = str(j.get("category", ""))
	_desc.text = str(j.get("description", ""))
	_credit.text = str(j.get("model_credit", ""))
	var own := Callsign.section_default(j.get("registration", {}) as Dictionary)
	_reg.text = "Registration: %s until you type your own call sign (Aircraft step or Options > Radio); it is painted on the tail." % own
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for sp in j.get("specs", []):
		var a := Label.new()
		a.text = sp[0]
		a.add_theme_color_override("font_color", MenuTheme.DIM)
		_grid.add_child(a)
		var b := Label.new()
		b.text = sp[1]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(160, 0)
		_grid.add_child(b)


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	opened = true
	visible = true
	_close.grab_focus()


func close() -> void:
	if not opened:
		return
	opened = false
	visible = false
	closed.emit()


func _input(ev: InputEvent) -> void:
	if opened and ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()  # before the flow's Esc = Back


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and not _card.get_global_rect().has_point(ev.global_position):
		close()
		accept_event()
