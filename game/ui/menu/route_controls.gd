class_name RouteControls
extends VBoxContainer
## The rows above the Route step's map: From (the Airport step's departure, read only), To (destination search box),
## the destination's arrival runway chips and the cruise altitude; then Auto-route (Direct / VOR to VOR / Airways),
## Clear and the route as text; then one note line (the how-to hint, or the last message for NOTE_S seconds).
## It only shows what refresh() hands it and reports the player's choices as signals; route_page.gd does the edits.

signal dest_picked(icao: String)
signal rwy_picked(ident: String)
signal cruise_changed(ft: float)
signal auto_pressed(kind: String)
signal clear_pressed
signal text_entered(text: String)

const HINT := "Click the map to add an airport, navaid or fix (empty map: a free waypoint). Drag a waypoint to move it: dropped on a named point it becomes that point, elsewhere a free waypoint. Drag a leg to add a waypoint on it. Right-click a waypoint to remove it. Shift+click an airport: destination."
const AUTO := [["direct", "Direct", "Straight from the departure to the destination"],
	["vor", "VOR to VOR", "Hop between VOR and NDB stations"],
	["airway", "Airways", "Follow the published airways (shortest path)"]]
const NOTE_S := 6.0  # a message replaces the hint this long

var from_label: Label
var dest_search: AirportSearch
var rwy_seg: Segmented
var cruise: SpinBox
var auto_seg: Segmented
var clear_btn: Button
var text_box: LineEdit
var note: Label
var _rwy_for := "-"  # destination the runway chips were built for
var _note_t := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var top := _row()
	top.add_child(_cap("From"))
	from_label = Label.new()
	from_label.tooltip_text = "The departure is the airport of the Airport & start step."
	from_label.mouse_filter = Control.MOUSE_FILTER_PASS
	MenuTheme.use_font(from_label, "semibold", 17)
	top.add_child(from_label)
	top.add_child(_cap("   To"))
	dest_search = AirportSearch.new()
	dest_search.placeholder_text = "Destination: ICAO, name or city…"
	dest_search.tooltip_text = "Where the route ends. Type an ICAO code, an airport name or a city."
	dest_search.custom_minimum_size = Vector2(250, 0)
	dest_search.size_flags_horizontal = SIZE_EXPAND_FILL
	dest_search.picked.connect(func(id): dest_picked.emit(id))
	top.add_child(dest_search)
	rwy_seg = Segmented.new()
	rwy_seg.equal_width = false
	rwy_seg.pad_x = 8
	rwy_seg.selected.connect(func(v): rwy_picked.emit(str(v)))
	top.add_child(rwy_seg)
	top.add_child(_cap("   Cruise ft"))
	cruise = SpinBox.new()
	cruise.min_value = 500.0
	cruise.max_value = 41000.0
	cruise.step = 500.0
	cruise.custom_minimum_size = Vector2(112, 0)
	cruise.tooltip_text = "Cruise altitude (ft): new waypoints get it, and waypoints that were at the old one follow it."
	cruise.value_changed.connect(func(v): cruise_changed.emit(v))
	top.add_child(cruise)
	var tools := _row()
	tools.add_child(_cap("Auto-route"))
	auto_seg = Segmented.new()
	auto_seg.equal_width = false
	auto_seg.set_options(AUTO)
	for a in AUTO:
		auto_seg.button_of(a[0]).pressed.connect(func(): auto_pressed.emit(a[0]))  # every press builds (a re-press rebuilds)
	tools.add_child(auto_seg)
	clear_btn = Button.new()
	clear_btn.text = "Clear"
	clear_btn.tooltip_text = "Remove the destination and every waypoint (the step is then skipped)."
	clear_btn.custom_minimum_size = Vector2(76, 36)
	clear_btn.pressed.connect(func(): clear_pressed.emit())
	tools.add_child(clear_btn)
	text_box = LineEdit.new()
	text_box.size_flags_horizontal = SIZE_EXPAND_FILL
	text_box.placeholder_text = "Type a route, e.g. VABB DCT PAPRI W15 VAPO, and press Enter"
	text_box.tooltip_text = "Idents separated by spaces or /, DCT is ignored, airway names are expanded between their fixes.\nThe last ident is the destination when it is an airport. Free map waypoints (WPTnn) cannot be typed."
	text_box.text_submitted.connect(func(t): text_entered.emit(t))
	text_box.focus_exited.connect(func(): text_box.text = RouteEdit.as_text(Session.setup))  # an edit not entered is dropped
	tools.add_child(text_box)
	note = MenuTheme.note(HINT)
	add_child(note)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	return row


func _cap(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	l.add_theme_font_size_override("font_size", MenuTheme.SIZE_NOTE)
	return l


## Show the setup `s` and its normalized route `r`; `airports` = AirportData records (search list, runway chips).
func refresh(s: Dictionary, r: Dictionary, airports: Array) -> void:
	if dest_search.items.is_empty():
		dest_search.set_items(AirportData.search_items(airports, 0.0))
	from_label.text = RoutePageData.from_text(s)
	dest_search.set_current(r.dest)
	if r.dest != _rwy_for:
		_rwy_for = r.dest
		rwy_seg.set_options(RoutePageData.runway_options(airports, r.dest))
	rwy_seg.visible = r.dest != ""
	rwy_seg.select(r.arr_rwy)
	cruise.set_value_no_signal(r.cruise_ft)
	auto_seg.select(r.kind)
	clear_btn.disabled = not RouteEdit.planned(r)
	clear_btn.focus_mode = Control.FOCUS_NONE if clear_btn.disabled else Control.FOCUS_ALL  # Tab skips it while greyed
	if not text_box.has_focus():
		text_box.text = RouteEdit.as_text(s)


## A message in the note line (amber when `warn`); the hint comes back after NOTE_S seconds.
func say(msg: String, warn := false) -> void:
	note.text = msg
	note.add_theme_color_override("font_color", MenuTheme.WARN if warn else MenuTheme.TEXT)
	_note_t = NOTE_S


func _process(dt: float) -> void:
	if _note_t > 0.0:
		_note_t -= dt
		if _note_t <= 0.0:
			note.text = HINT
			note.add_theme_color_override("font_color", MenuTheme.DIM)
