extends HBoxContainer
## Start screen page: saved flights (core/situation.gd). Pick one and "Fly from this
## save": its flight setup (airport, weather, failures, ...) becomes the session setup
## and the flight scene resumes the saved situation (Situation.pending_load).

signal changed

const FLIGHT := "res://world/flight.tscn"

var _saves: Array = []
var _list: ItemList
var _thumb: TextureRect
var _info: Label
var _fly: Button
var _del: Button


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	add_child(left)
	left.add_child(MenuTheme.heading("Saved flights"))
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 360)
	_list.item_selected.connect(func(_i): _show_selected())
	_list.item_activated.connect(func(_i): _fly_save())
	left.add_child(_list)
	left.add_child(MenuTheme.note("In flight: Esc → Save flight, or F11 quick-save / Shift+F11 quick-load."))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(480, 270)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_thumb)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	right.add_child(bar)
	_fly = Button.new()
	_fly.text = "Fly from this save  ▶"
	_fly.custom_minimum_size = Vector2(240, 48)
	_fly.add_theme_stylebox_override("normal", MenuTheme.box(Color(MenuTheme.ACCENT, 0.6), 8))
	_fly.add_theme_stylebox_override("hover", MenuTheme.box(MenuTheme.ACCENT, 8))
	_fly.pressed.connect(_fly_save)
	bar.add_child(_fly)
	_del = Button.new()
	_del.text = "Delete"
	_del.custom_minimum_size = Vector2(110, 48)
	_del.pressed.connect(_delete)
	bar.add_child(_del)
	visibility_changed.connect(func(): if is_visible_in_tree(): _refresh())
	_refresh()


func _refresh() -> void:
	var keep: String = _selected().get("file", "")
	_saves = Situation.list_saves()
	_list.clear()
	for m in _saves:
		var i := _list.add_item("%s  ·  %s  ·  %s" % [m.get("name", m.file), m.get("airport", "?"), m.get("date", "")])
		if m.file == keep:
			_list.select(i)
	if _list.get_selected_items().is_empty() and _list.item_count > 0:
		_list.select(0)
	_show_selected()


func _selected() -> Dictionary:
	if _list == null:
		return {}
	var s := _list.get_selected_items()
	return _saves[s[0]] if not s.is_empty() and s[0] < _saves.size() else {}


func _show_selected() -> void:
	var m := _selected()
	_fly.disabled = m.is_empty()
	_del.disabled = m.is_empty()
	_thumb.texture = SituationStore.load_thumb(m.get("thumb", ""))
	if m.is_empty():
		_info.text = "No saved flights yet."
		return
	var where := "On the ground" if m.get("on_ground", false) else "%d ft (%d ft above ground), %d KIAS" % [
		int(m.get("alt_ft", 0)), int(m.get("agl_ft", 0)), int(m.get("ias_kt", 0))]
	_info.text = "%s\nNear %s · %s\nSaved %s" % [m.get("name", m.file), m.get("airport", "?"), where, m.get("date", "")]


func _fly_save() -> void:
	var m := _selected()
	if m.is_empty():
		return
	var d := SituationStore.read(m.file)
	if d.is_empty():
		_info.text = "Cannot read this save."
		return
	var setup: Dictionary = Session.DEFAULT.duplicate(true)
	setup.merge(d.get("setup", {}), true)
	Session.setup = setup
	Situation.pending_load = m.file
	changed.emit()
	_fly.text = "Loading scenery…"
	_fly.disabled = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(FLIGHT)


func _delete() -> void:
	var m := _selected()
	if m.is_empty():
		return
	Situation.delete(m.file)
	_refresh()
