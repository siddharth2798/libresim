class_name AirportStartPanel
extends VBoxContainer
## Right column of the Airport step: how the flight starts. A three-way choice (Runway / Stand / In the air), then
## only what that choice needs: runway chips with the wind on each, the stand list, or the air-start numbers with the
## side view. It holds no state of its own: it shows what the page gives it and reports the pilot's choices as signals.

signal mode_picked(mode: String)
signal runway_picked(ident: String)
signal stand_picked(name: String)
signal air_edited(key: String, value: float)
signal air_reset
signal cold_toggled(on: bool)

const MODES := [["runway", "Runway"], ["stand", "Stand / gate"], ["air", "In the air"]]

var mode_btns := {}
var alt: SpinBox
var dist: SpinBox
var air_note: Label  # the aircraft's default start
var cold: SwitchRow
var stand_note: Label
var mode_note: Label
var profile: GlideProfile
var _syncing := false  # the spin boxes are being set from the setup: not an edit by the pilot
var _runway_box: VBoxContainer
var _runway_head: Label
var _runway_grid: GridContainer
var _runway_btns := {}  # ident -> Button
var _short_note: Label
var _stand_box: VBoxContainer
var _stand_head: Label
var _stand_list: StandList
var _air_box: VBoxContainer
var _air_grid: GridContainer
var _group := ButtonGroup.new()


func _init() -> void:
	custom_minimum_size = Vector2(300, 0)
	add_theme_constant_override("separation", 8)
	add_child(MenuTheme.heading("Start at", 13))
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 4)
	add_child(seg)
	var g := ButtonGroup.new()
	for m in MODES:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.button_group = g
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.28), 8, MenuTheme.ACCENT))
		b.add_theme_stylebox_override("hover_pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.36), 8, MenuTheme.ACCENT))
		b.pressed.connect(func(): mode_picked.emit(m[0]))
		if m[0] == "stand":
			b.tooltip_text = "Stands come from OpenStreetMap: gates with jetbridges at the big airports, remote bays and GA parking."
		seg.add_child(b)
		mode_btns[m[0]] = b
	mode_note = MenuTheme.note("")
	add_child(mode_note)
	_build_runways()
	_build_stands()
	_build_air()
	cold = SwitchRow.new().setup("Cold & dark start", "Engine off, everything off: run the checklists.")
	cold.tooltip_text = "Engine off, everything off: run the checklists."
	cold.toggled.connect(func(on): cold_toggled.emit(on))
	add_child(cold)
	stand_note = MenuTheme.note("Stand starts are cold & dark, brake set.")
	add_child(stand_note)


func _section(parent: Control, text: String) -> Label:
	var l := MenuTheme.heading(text, 13)
	parent.add_child(l)
	return l


func _build_runways() -> void:
	_runway_box = VBoxContainer.new()
	_runway_box.add_theme_constant_override("separation", 6)
	add_child(_runway_box)
	_runway_head = _section(_runway_box, "Runway")
	_runway_grid = GridContainer.new()
	_runway_grid.columns = 2
	_runway_grid.add_theme_constant_override("h_separation", 6)
	_runway_grid.add_theme_constant_override("v_separation", 6)
	_runway_box.add_child(_runway_grid)
	_short_note = MenuTheme.note("")
	_runway_box.add_child(_short_note)


func _build_stands() -> void:
	_stand_box = VBoxContainer.new()
	_stand_box.add_theme_constant_override("separation", 6)
	_stand_box.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_stand_box)
	_stand_head = _section(_stand_box, "Stand")
	_stand_list = StandList.new()
	_stand_list.picked.connect(func(n): stand_picked.emit(n))
	_stand_box.add_child(_stand_list)


func _build_air() -> void:
	_air_box = VBoxContainer.new()
	_air_box.add_theme_constant_override("separation", 6)
	add_child(_air_box)
	_section(_air_box, "Air start")
	_air_grid = GridContainer.new()
	_air_grid.columns = 2
	_air_box.add_child(_air_grid)
	alt = _spin("Height (ft)", 100, "air_ft", "Height above the field.")
	dist = _spin("Distance (nm)", 0.5, "air_nm", "Distance out on final approach.")
	profile = GlideProfile.new()
	_air_box.add_child(profile)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_air_box.add_child(row)
	air_note = MenuTheme.note("")
	air_note.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(air_note)
	var reset := Button.new()
	reset.text = "Default"
	reset.tooltip_text = "Height and distance follow the chosen aircraft again."
	reset.size_flags_vertical = SIZE_SHRINK_CENTER
	reset.pressed.connect(func(): air_reset.emit())
	row.add_child(reset)


func _spin(label: String, step: float, key: String, tip: String) -> SpinBox:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	SliderRow.tip_on(l, tip)
	_air_grid.add_child(l)
	var sb := SpinBox.new()
	sb.tooltip_text = tip
	sb.size_flags_horizontal = SIZE_EXPAND_FILL
	sb.step = step
	sb.value_changed.connect(func(v):
		if not _syncing:
			air_edited.emit(key, v))
	_air_grid.add_child(sb)
	return sb


## Which part shows. `mode` runway | stand | air; `has_stands` false greys the stand choice.
func show_mode(mode: String, has_stands: bool) -> void:
	mode_btns.stand.disabled = not has_stands
	mode_btns[mode].set_pressed_no_signal(true)
	mode_note.text = {"runway": "On the runway, engine running, lined up. Click a runway end on the map or below.",
		"stand": "Parked at the apron or a gate. Click a dot on the map or pick one below.",
		"air": "Airborne on final to the runway chosen below."}[mode]
	mode_note.visible = mode != "air"  # (the air-start block says it)
	_runway_head.text = "Land on runway" if mode == "air" else "Runway"
	_runway_box.visible = mode != "stand"
	_stand_box.visible = mode == "stand" and has_stands
	_air_box.visible = mode == "air"
	cold.visible = mode == "runway"  # a stand start is always cold & dark (the note), an air start never
	stand_note.visible = mode == "stand"


## rows: [{ident, text (first line), wind (second line), short, bad, tip}].
func set_runways(rows: Array, selected: String, short_note: String) -> void:
	for c in _runway_grid.get_children():
		c.queue_free()
		_runway_grid.remove_child(c)
	_runway_btns.clear()
	for r in rows:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s\n%s" % [r.text, r.wind]
		b.tooltip_text = r.tip
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(120, 0)
		style_choice(b)
		if r.short or r.bad:
			var col: Color = MenuTheme.WARN if r.short else MenuTheme.BAD
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(k, col)
		var ident: String = r.ident
		b.pressed.connect(func(): runway_picked.emit(ident))
		_runway_grid.add_child(b)
		_runway_btns[ident] = b
	_short_note.text = short_note
	_short_note.visible = short_note != ""
	mark_runway(selected)


func mark_runway(ident: String) -> void:
	for id in _runway_btns:
		_runway_btns[id].set_pressed_no_signal(id == ident)


func runway_button(ident: String) -> Button:
	return _runway_btns.get(ident)


## rows: [{name, jetbridge, sub}] in display order; `head`: "Stand · N on offer for the Cessna 172S".
func set_stands(rows: Array, selected: String, head: String) -> void:
	_stand_head.text = head
	_stand_list.set_rows(rows, selected)


func mark_stand(name: String) -> void:
	_stand_list.mark(name)


func stand_button(name: String) -> Button:
	return _stand_list.button(name)


## The look of a choice button (a runway chip, a stand row): quiet, accent outline and tint when it is the choice.
static func style_choice(b: Button) -> void:
	b.add_theme_stylebox_override("normal", MenuTheme.box(Color(1, 1, 1, 0.06), 8, MenuTheme.LINE))
	b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.2), 8, MenuTheme.ACCENT))
	b.add_theme_stylebox_override("hover_pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.3), 8, MenuTheme.ACCENT))


## Limits and values of the air-start spin boxes, the note and the side view. `a`: AircraftDef.air_start().
func sync_air(a: Dictionary, setup: Dictionary) -> void:
	_syncing = true
	alt.min_value = a.limits.alt_ft[0]
	alt.max_value = a.limits.alt_ft[1]
	dist.min_value = a.limits.dist_nm[0]
	dist.max_value = a.limits.dist_nm[1]
	alt.set_value_no_signal(float(setup.air_ft))
	dist.set_value_no_signal(float(setup.air_nm))
	_syncing = false
	air_note.text = "Default for this aircraft: %s ft, %s nm, %d kt." % [AirportData.thousands(int(a.alt_ft)), Session.nm_text(a.dist_nm), int(a.kias)]
	refresh_profile()


## Re-reads the side view (after an edit of height or distance).
func refresh_profile() -> void:
	profile.refresh()
