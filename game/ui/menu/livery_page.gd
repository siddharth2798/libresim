extends HBoxContainer
## Free-flight step after Aircraft: paint regions, sticker slots, and presets kept on this computer.
## Writes Session.setup.livery through Livery.repair_setup. Reset returns the factory colours and clears stickers.

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
	add_theme_constant_override("separation", 16)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(340, 300)
	stage.size_flags_vertical = SIZE_EXPAND_FILL
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	var view := preload("res://ui/menu/livery_preview.gd").new()
	_preview = view
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(view)
	stage.add_child(view.zoom_controls())
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	_empty = MenuTheme.note("This aircraft has nothing to paint yet. Reset does nothing.")
	_empty.visible = false
	right.add_child(_empty)
	_regions = preload("res://ui/menu/livery_regions.gd").new()
	_regions.picked.connect(set_region)
	right.add_child(_regions)
	_slots = preload("res://ui/menu/livery_slots.gd").new()
	_slots.edited.connect(_on_slot)
	_slots.load_asked.connect(_ask_file)
	right.add_child(_slots)
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
