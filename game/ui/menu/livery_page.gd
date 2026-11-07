extends HBoxContainer
## Free-flight step after Aircraft. Writes Session.setup.livery through Livery.repair_setup.

signal changed

var _regions: VBoxContainer
var _slots: VBoxContainer
var _preview: SubViewportContainer
var _presets: OptionButton
var _name: LineEdit
var _error: Label
var _empty: Label
var _dialog: FileDialog
var _id := ""
var _colors := {}
var _placed := {}
var _filling := false
var _slot := ""


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(420, 420)
	stage.size_flags_horizontal = SIZE_EXPAND_FILL
	stage.size_flags_vertical = SIZE_EXPAND_FILL
	stage.size_flags_stretch_ratio = 1.25
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	var view := preload("res://ui/menu/livery_preview.gd").new()
	_preview = view
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(view)
	stage.add_child(_overlay())
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(320, 0)
	add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.size_flags_vertical = SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", 14)
	scroll.add_child(right)
	_empty = MenuTheme.note("This aircraft has nothing to paint yet. Reset does nothing.")
	_empty.visible = false
	right.add_child(_empty)
	right.add_child(MenuTheme.heading("Paint"))
	_regions = preload("res://ui/menu/livery_regions.gd").new()
	_regions.picked.connect(set_region)
	right.add_child(_regions)
	right.add_child(MenuTheme.heading("Pictures"))
	_slots = preload("res://ui/menu/livery_slots.gd").new()
	_slots.edited.connect(_on_slot)
	_slots.load_asked.connect(_ask_file)
	right.add_child(_slots)
	right.add_child(MenuTheme.heading("Presets"))
	right.add_child(_preset_row())
	_error = MenuTheme.note("")
	right.add_child(_error)
	right.add_child(MenuTheme.note("Presets stay on this computer."))
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Picture for this slot"
	_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	_dialog.file_selected.connect(_on_file)
	add_child(_dialog)
	visibility_changed.connect(_when_shown)
	if is_visible_in_tree():
		_sync()


func _when_shown() -> void:
	if is_visible_in_tree():
		_sync()


func set_region(key: String, color: Color) -> void:
	if _filling or _id == "":
		return
	var hex := Livery.to_hex(color)
	var factory := ""
	for r in Livery.of(AircraftDef.load_def(_id)).regions:
		if r.key == key:
			factory = Livery.to_hex(r.default)
	if hex == factory:
		_colors.erase(key)
	else:
		_colors[key] = hex
	_store()
	_preview.set_paint(Livery.entry(Session.setup.get("livery"), _id))


## "" when the preset was saved, otherwise one line for the page.
func save_preset(preset_name: String) -> String:
	_ensure()
	var n := LiveryStore.save_preset(_id, preset_name, Livery.entry(Session.setup.get("livery"), _id))
	if n == "":
		_say("Name the preset first.")
		return "Name the preset first."
	_say("")
	_fill_presets()
	return ""


func load_preset(preset_name: String) -> void:
	_ensure()
	var all: Dictionary = _all()
	all[_id] = LiveryStore.load_preset(_id, preset_name)
	Session.setup["livery"] = Livery.repair_setup(all)
	_sync()
	changed.emit()


func reset_livery() -> void:
	_ensure()
	_colors = {}
	_placed = {}
	_store()
	_sync()


func _overlay() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	var zoom := HBoxContainer.new()
	zoom.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	zoom.offset_left = -88.0
	zoom.offset_top = 8.0
	zoom.offset_right = -8.0
	zoom.offset_bottom = 40.0
	zoom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom.add_theme_constant_override("separation", 4)
	zoom.add_child(_zoom_button("−", 1.0 / 1.18))
	zoom.add_child(_zoom_button("+", 1.18))
	layer.add_child(zoom)
	var views := HBoxContainer.new()
	views.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	views.offset_top = -44.0
	views.offset_bottom = -8.0
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	views.mouse_filter = Control.MOUSE_FILTER_IGNORE
	views.add_theme_constant_override("separation", 4)
	for pair in [["Side", "side"], ["Front", "front"], ["Tail", "tail"]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_preview.face.bind(pair[1]))
		views.add_child(b)
	layer.add_child(views)
	var hint := Label.new()
	hint.text = "Drag to turn · scroll to zoom"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hint.offset_left = 10.0
	hint.offset_top = 8.0
	hint.offset_right = 250.0
	hint.offset_bottom = 30.0
	hint.add_theme_color_override("font_color", MenuTheme.DIM)
	hint.add_theme_font_size_override("font_size", 13)
	layer.add_child(hint)
	return layer


func _zoom_button(text: String, factor: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 28)
	b.pressed.connect(_preview.zoom_by.bind(factor))
	return b


func _preset_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_name = LineEdit.new()
	_name.placeholder_text = "Preset name"
	_name.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_name)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(func(): save_preset(_name.text))
	row.add_child(save)
	_presets = OptionButton.new()
	_presets.add_item("Load preset")
	row.add_child(_presets)
	var load := Button.new()
	load.text = "Load"
	load.pressed.connect(_load_selected)
	row.add_child(load)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(reset_livery)
	row.add_child(reset)
	return row


func _sync() -> void:
	var def := AircraftDef.load_def(str(Session.setup.get("aircraft", "")))
	if def == null:
		return
	_filling = true
	_id = def.id
	var lv := Livery.of(def)
	var e := Livery.entry(Session.setup.get("livery"), _id)
	_colors = e.colors.duplicate() if e.get("colors") is Dictionary else {}
	_placed = e.stickers.duplicate(true) if e.get("stickers") is Dictionary else {}
	_empty.visible = lv.regions.is_empty() and lv.stickers.is_empty()
	_regions.bind(lv, Livery.colors_of(lv, e))
	_slots.bind(lv.stickers, _placed)
	_fill_presets()
	_preview.show_aircraft(def)
	_preview.set_paint(e)
	_filling = false


func _ensure() -> void:
	if _id == "":
		_sync()


func _store() -> void:
	var all := _all()
	var e := {}
	if not _colors.is_empty():
		e["colors"] = _colors.duplicate()
	if not _placed.is_empty():
		e["stickers"] = _placed.duplicate(true)
	if e.is_empty():
		all.erase(_id)
	else:
		all[_id] = e
	Session.setup["livery"] = Livery.repair_setup(all)
	changed.emit()


func _all() -> Dictionary:
	var cur = Session.setup.get("livery", {})
	return cur.duplicate(true) if cur is Dictionary else {}


func _on_slot(key: String, fields: Dictionary) -> void:
	if _filling:
		return
	if fields.is_empty():
		_placed.erase(key)
	else:
		_placed[key] = fields
	_store()
	_preview.set_paint(Livery.entry(Session.setup.get("livery"), _id))
	if fields.is_empty():
		_slots.bind(Livery.of(AircraftDef.load_def(_id)).stickers, _placed)


func _ask_file(key: String) -> void:
	_slot = key
	_dialog.popup_centered_ratio(0.6)


func _on_file(path: String) -> void:
	var r := LiveryStore.import_file(path)
	if not r.ok:
		_say(str(r.error))
		return
	_say("")
	var cur: Dictionary = _placed.get(_slot, {}).duplicate() if _placed.get(_slot) is Dictionary else {}
	cur["image"] = r.image
	cur["scale"] = float(cur.get("scale", 1.0))
	cur["dx"] = float(cur.get("dx", 0.0))
	cur["dy"] = float(cur.get("dy", 0.0))
	cur["mirror"] = bool(cur.get("mirror", true))
	_placed[_slot] = cur
	_store()
	_sync()
	_preview.face(_slot)


func _load_selected() -> void:
	if _presets.selected <= 0:
		return
	load_preset(_presets.get_item_text(_presets.selected))


func _fill_presets() -> void:
	_presets.clear()
	_presets.add_item("Load preset")
	for n in LiveryStore.list_presets(_id):
		_presets.add_item(n)


func _say(text: String) -> void:
	_error.text = text
