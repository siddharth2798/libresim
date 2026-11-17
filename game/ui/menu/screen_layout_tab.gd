class_name ScreenLayoutTab
extends VBoxContainer
## Options > Screen layout: what shows on the game screen in outside views and where. A preview of the screen
## (ScreenLayoutPreview) with a box per shown piece of the chosen aircraft's Custom layout and the flight-data
## bar, a switch per piece, and a reset. Changing anything selects the Custom layout (Tab in flight cycles
## Full, Split, Compact, Minimal, Custom, Off). Data and storage: ui/screen_layout.gd.

signal changed

const HUD_SWITCH := "Flight data bar at start (H toggles in flight)"

var preview := ScreenLayoutPreview.new()
var aircraft_id := ""
var _seg: Segmented
var _switches: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(MenuTheme.heading("Screen layout"))
	add_child(MenuTheme.note("Your own layout for outside views. Drag a box to move it; drag its corner or turn the wheel over it to resize. "
		+ "Changing anything here selects the Custom layout; in flight Tab cycles Full, Split, Compact, Minimal, Custom and Off."))
	var ids := AircraftDef.list_ids().filter(func(i): return not ScreenLayout.catalog(AircraftDef.load_def(i)).is_empty())
	var cur := AircraftDef.current()
	aircraft_id = cur.id if cur != null and cur.id in ids else (ids[0] if not ids.is_empty() else "")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = "Aircraft"
	l.custom_minimum_size = Vector2(OptionRows.LABEL_W, 0)
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	row.add_child(l)
	_seg = Segmented.new()
	_seg.equal_width = false
	_seg.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_seg.set_options(ids.map(func(i): return [i, AircraftDef.load_def(i).display_name()]), aircraft_id)
	_seg.selected.connect(func(v): select_aircraft(str(v)))
	row.add_child(_seg)
	add_child(row)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	add_child(body)
	preview.edited.connect(func(): changed.emit())
	body.add_child(preview)
	_switches = VBoxContainer.new()
	_switches.add_theme_constant_override("separation", 6)
	_switches.custom_minimum_size = Vector2(250, 0)
	body.add_child(_switches)
	var reset := Button.new()
	reset.text = "Reset to the default layout"
	reset.size_flags_horizontal = SIZE_SHRINK_BEGIN
	reset.pressed.connect(reset_layout)
	add_child(reset)
	add_child(MenuTheme.note("The mini-map can also be dragged, zoomed and resized in flight."))
	select_aircraft(aircraft_id)


func select_aircraft(id: String) -> void:
	aircraft_id = id
	if _seg != null:
		_seg.select(id)
	var def := AircraftDef.load_def(id) if id != "" else null
	preview.hud_on = bool(UserOptions.get_v("hud_at_start"))
	preview.set_aircraft(def)
	_build_switches()


func _build_switches() -> void:
	for c in _switches.get_children():
		c.queue_free()
	var hud := OptionRows.switch(HUD_SWITCH, "hud_at_start", func(on: bool):
		preview.hud_on = on
		preview.queue_redraw()
		changed.emit())
	_switches.add_child(hud)
	for c in ScreenLayout.catalog(preview.def):
		var sw := SwitchRow.new().setup(c.label, "", bool(preview.pieces[c.id].on))
		sw.name = "piece_" + c.id
		sw.toggled.connect(set_piece_on.bind(c.id))
		_switches.add_child(sw)


func set_piece_on(on: bool, id: String) -> void:
	preview.pieces[id].on = on
	ScreenLayout.save_pieces(preview.def, preview.pieces)
	ScreenLayout.use_custom()
	preview.queue_redraw()
	changed.emit()


func reset_layout() -> void:
	ScreenLayout.reset(preview.def)
	ScreenLayout.reset_hud()
	select_aircraft(aircraft_id)
	changed.emit()
