extends PanelContainer
## Saved flights, in flight (core/situation.gd). Opened from the pause menu (open());
## pauses the flight model while open, Esc closes it.
## Save the current flight under a name (default "<ICAO> <date time>"), or Load /
## Delete a save from the list (thumbnail, airport, altitude, IAS, date).
## F11 quick-save, Shift+F11 quick-load (slot "quicksave"), with a brief confirmation.

var flight: Node  # world/flight.gd (defaults to the scene owner)
var _list: ItemList
var _name: LineEdit
var _status: Label
var _load_btn: Button
var _del_btn: Button
var _toast: Label
var _toast_t := 0.0
var _saves: Array = []


func _ready() -> void:
	visible = false
	if flight == null:
		flight = owner
	theme = MenuTheme.make()
	add_theme_stylebox_override("panel", MenuTheme.box(Color(MenuTheme.PANEL, 0.95), 10, Color(1, 1, 1, 0.08), 18.0))
	custom_minimum_size = Vector2(760, 540)
	set_anchors_preset(PRESET_CENTER)
	offset_left = -380.0
	offset_right = 380.0
	offset_top = -270.0
	offset_bottom = 270.0
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var t := Label.new()
	t.text = "Saved flights"
	t.add_theme_font_size_override("font_size", 22)
	vb.add_child(t)
	var row := HBoxContainer.new()
	vb.add_child(row)
	_name = LineEdit.new()
	_name.size_flags_horizontal = SIZE_EXPAND_FILL
	_name.placeholder_text = "Name"
	_name.text_submitted.connect(func(_t): _save())
	row.add_child(_name)
	row.add_child(_button("Save current flight", _save))
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(160, 90)
	_list.icon_mode = ItemList.ICON_MODE_LEFT
	_list.item_selected.connect(func(_i): _update_buttons())
	_list.item_activated.connect(func(_i): _load())
	vb.add_child(_list)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_status)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(bar)
	_load_btn = _button("Load", _load)
	_del_btn = _button("Delete", _delete)
	bar.add_child(_load_btn)
	bar.add_child(_del_btn)
	bar.add_child(_button("Close", close))
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(PRESET_CENTER_TOP)
	_toast.position = Vector2(-150, 60)
	_toast.custom_minimum_size = Vector2(300, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	get_parent().add_child.call_deferred(_toast)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 36)
	b.pressed.connect(cb)
	return b


## Show the panel (pauses the flight). focus_save: put the cursor in the name field.
func open(focus_save := false) -> void:
	visible = true
	flight.fdm_node.paused = true
	_name.text = Situation.default_name(flight)
	_status.text = Situation.why_not_save(flight)
	_refresh()
	if focus_save:
		_name.grab_focus()
		_name.select_all()
	elif _list.item_count > 0:
		_list.grab_focus()


func close() -> void:
	visible = false
	flight.fdm_node.paused = false


func _refresh() -> void:
	_saves = Situation.list_saves()
	_list.clear()
	for m in _saves:
		var where := "on the ground" if m.get("on_ground", false) else "%d ft, %d KIAS" % [int(m.get("alt_ft", 0)), int(m.get("ias_kt", 0))]
		var i := _list.add_item("%s   ·   %s, %s   ·   %s" % [m.get("name", m.file), m.get("airport", "?"), where, m.get("date", "")])
		var tex := SituationStore.load_thumb(m.thumb)
		if tex:
			_list.set_item_icon(i, tex)
	if _list.item_count > 0:
		_list.select(0)
	_update_buttons()


func _update_buttons() -> void:
	var none := _list.get_selected_items().is_empty()
	_load_btn.disabled = none
	_del_btn.disabled = none


func _selected() -> Dictionary:
	var s := _list.get_selected_items()
	return _saves[s[0]] if not s.is_empty() else {}


func _save() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		name = Situation.default_name(flight)
	visible = false  # keep the panel out of the thumbnail
	var err := await _save_with_thumb(name)
	visible = true
	_status.text = err if err != "" else "Saved \"%s\"" % name
	_refresh()


## Waits for a frame without UI panels on top, then saves with a thumbnail.
func _save_with_thumb(name: String) -> String:
	var err := Situation.why_not_save(flight)
	if err != "":
		return err
	_toast_t = 0.0
	_toast.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return Situation.save(flight, name, SituationStore.grab_thumbnail(get_viewport()))


func _load() -> void:
	var m := _selected()
	if m.is_empty():
		return
	var err := Situation.load_file(flight, m.file)
	if err != "":
		_status.text = err
		return
	close()
	toast("Loaded \"%s\"" % m.get("name", m.file))


func _delete() -> void:
	var m := _selected()
	if m.is_empty():
		return
	Situation.delete(m.file)
	_status.text = "Deleted \"%s\"" % m.get("name", m.file)
	_refresh()


func quick_save() -> void:
	var err := await _save_with_thumb(Situation.QUICK)
	toast(err if err != "" else "Quick-saved (Shift+F11 to return here)")


func quick_load() -> void:
	var err := Situation.load_file(flight, Situation.QUICK)
	toast(err if err != "" else "Quick-loaded")


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 2.5


func _process(dt: float) -> void:
	_toast_t -= dt
	_toast.visible = _toast_t > 0.0


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE and visible:
		close()
		get_viewport().set_input_as_handled()
	elif e.keycode == KEY_F11 and not visible:
		if e.shift_pressed:
			quick_load()
		else:
			quick_save()
		get_viewport().set_input_as_handled()
