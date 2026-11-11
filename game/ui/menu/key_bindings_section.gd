extends VBoxContainer
## Controls page, keyboard tab: one row per flight-control action (two columns when wide) with up to three
## key slots. Click a slot, then press a key (with Shift / Ctrl / Alt if wanted);
## Esc cancels, Delete / Backspace empties the slot. ✕ clears the row. Conflicts
## (same key on two actions, or on another hotkey) are listed in orange.
## Saves to user://key_bindings.json and bumps Props input/bindings_rev.
## Ground operations (ControlActions.GROUND: taxi route, pushback, jetway, door, ground vehicles) get their own section.
## Only the actions the aircraft offers (aircraft_controls.gd) get a row or count for conflicts;
## the others stay in the saved profile.

signal changed

const SLOT_W := 92.0
const NAME_W := 110.0  # minimum; the name takes the spare width and ends in an ellipsis (full text in the tooltip)
const TWO_COLUMNS_W := 940.0  # two columns of rows from this page width
const WARN := Color(1.0, 0.7, 0.3)
const MODS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var path := KeyBindings.PATH
var controls: AircraftControls  # set before adding to the tree; default = the current aircraft
var table := {}
var _slots := {}  # action -> Array[Button]
var _rows := {}  # action -> its row (hidden by filter())
var _query := ""
var _warn: Label
var _hint: Label
var _grid: GridContainer
var _ground_grid: GridContainer
var _ground_head: Label
var _flight_head: Label
var _cap_action := ""
var _cap_slot := -1


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	if controls == null:
		controls = AircraftControls.current()
	table = KeyBindings.load_from(path)
	var head := HBoxContainer.new()
	add_child(head)
	_hint = MenuTheme.note("Click a key slot, then press the new key (modifiers allowed). Esc cancels, Delete empties the slot.")
	_hint.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(_hint)
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.size_flags_vertical = SIZE_SHRINK_CENTER
	reset.pressed.connect(_reset)
	head.add_child(reset)
	_warn = Label.new()
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.add_theme_color_override("font_color", WARN)
	_warn.add_theme_font_size_override("font_size", 14)
	add_child(_warn)
	_flight_head = MenuTheme.heading("Flight controls")
	add_child(_flight_head)
	_grid = _new_grid()
	_ground_head = MenuTheme.heading("Ground operations")
	add_child(_ground_head)
	_ground_grid = _new_grid()
	for a in controls.key_actions():
		_add_row(a, _ground_grid if a in ControlActions.GROUND else _grid)
	_refresh()
	resized.connect(func():
		for g in [_grid, _ground_grid]:
			g.columns = 2 if size.x >= TWO_COLUMNS_W else 1)


func _new_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 6)
	add_child(g)
	return g


## The section an action's row is in: "ground" or "flight".
func section_of(a: String) -> String:
	return "ground" if _rows.has(a) and (_rows[a] as Control).get_parent() == _ground_grid else "flight"


func _add_row(a: String, grid: GridContainer) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	r.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(r)
	_rows[a] = r
	var n := Label.new()
	n.text = KeyBindings.LABELS[a]
	n.tooltip_text = n.text
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	n.custom_minimum_size = Vector2(NAME_W, 0)
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	r.add_child(n)
	var l := []
	for i in KeyBindings.SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(SLOT_W, 36)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_start.bind(a, i))
		r.add_child(b)
		l.append(b)
	_slots[a] = l
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = "Clear all keys for this action"
	x.custom_minimum_size = Vector2(36, 36)
	x.pressed.connect(func():
		table[a] = []
		_save())
	r.add_child(x)


## Shows only the rows that match the search words (controls_filter.gd: action name, id, bound keys); returns how many show.
func filter(query: String) -> int:
	_query = query
	var n := 0
	var ground := 0
	for a in _rows:
		var texts := [KeyBindings.LABELS[a], a, "ground operations" if a in ControlActions.GROUND else "flight controls"]
		texts.append_array(table[a].map(func(k): return KeyBindings.describe(k)))
		var ok := ControlsFilter.matches(query, texts)
		(_rows[a] as Control).visible = ok
		n += int(ok)
		ground += int(ok and a in ControlActions.GROUND)
	_ground_head.visible = ground > 0
	_flight_head.visible = n - ground > 0
	return n


func row_count() -> int:
	return _rows.size()


func _refresh() -> void:
	var bad := {}
	for a in _slots:
		for s in table[a]:
			for b in _slots:
				if b != a and table[b].any(func(o): return KeyBindings.same(s, o)):
					bad[KeyBindings.describe(s)] = true
			if not s.shift and not s.ctrl and not s.alt and KeyBindings.RESERVED.has(int(s.key)):
				bad[KeyBindings.describe(s)] = true
	for a in _slots:
		var keys: Array = table[a]
		for i in KeyBindings.SLOTS:
			var b: Button = _slots[a][i]
			var waiting: bool = a == _cap_action and i == _cap_slot
			b.text = "press…" if waiting else (KeyBindings.describe(keys[i]) if i < keys.size() else "")
			var c := MenuTheme.TEXT
			if i < keys.size() and bad.has(b.text):
				c = WARN
			b.add_theme_color_override("font_color", c)
			b.add_theme_color_override("font_hover_color", c)
	var cf := KeyBindings.conflicts(table, _slots.keys())
	_warn.text = "" if cf.is_empty() else "Conflicts:\n• " + "\n• ".join(cf)
	_warn.visible = not cf.is_empty()
	if _query != "":
		filter(_query)  # a changed binding can change what matches


func _start(a: String, slot: int) -> void:
	_cap_action = a
	_cap_slot = mini(slot, table[a].size())  # fill the first empty slot, not a gap
	_hint.text = "%s: press a key…  (Esc cancels, Delete empties the slot)" % KeyBindings.LABELS[a]
	_refresh()


func _input(e: InputEvent) -> void:
	if _cap_action == "" or not e is InputEventKey or not e.pressed or e.echo:
		return
	var k: InputEventKey = e
	if k.keycode in MODS:
		return  # wait for the real key
	get_viewport().set_input_as_handled()
	var keys: Array = table[_cap_action]
	if k.keycode == KEY_ESCAPE:
		_hint.text = "Cancelled."
	elif k.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		if _cap_slot < keys.size():
			keys.remove_at(_cap_slot)
		_hint.text = "Slot emptied."
	else:
		var s := KeyBindings.from_event(k)
		if _cap_slot < keys.size():
			keys[_cap_slot] = s
		else:
			keys.append(s)
		_hint.text = "%s -> %s" % [KeyBindings.LABELS[_cap_action], KeyBindings.describe(s)]
	_cap_action = ""
	_cap_slot = -1
	_save()


func _reset() -> void:
	table = KeyBindings.defaults()
	_cap_action = ""
	_hint.text = "Keys reset to defaults."
	_save()


func _save() -> void:
	KeyBindings.save_to(table, path)
	Props.set_v("input/bindings_rev", int(Props.get_v("input/bindings_rev", 0)) + 1)
	_refresh()
	changed.emit()
