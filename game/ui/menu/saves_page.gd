extends HBoxContainer
## Start screen page: saved flights (core/situation.gd). Left: the saves as cards (picture, name, airport, aircraft,
## date), newest first. Right: the chosen one (picture, details) with "Fly from this save" and "Delete" (which asks
## first: Delete > "Yes, delete" / "Keep it"). Fly: its flight setup (airport, weather, failures, ...) becomes the
## session setup and the flight scene resumes the saved situation (Situation.pending_load). Double click on a
## card, or Enter on the selected card, also flies it. No saves: a short note on how to make one. Texts: saves_logic.gd.

signal changed

const FLIGHT := "res://world/flight.tscn"

var _saves: Array = []
var _cards: Array[SaveCard] = []
var _group := ButtonGroup.new()
var _list: VBoxContainer
var _detail: VBoxContainer
var _left: VBoxContainer
var _empty: PanelContainer
var _thumb: TextureRect
var _title: Label
var _table: GridContainer
var _info: Label
var _fly: Button
var _del: Button
var _keep: Button
var _guard := SavesLogic.Guard.new()
var _sel := ""  # file of the selected save


func _ready() -> void:
	add_theme_constant_override("separation", 20)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(340, 0)
	_left.add_theme_constant_override("separation", 8)
	add_child(_left)
	var ls := PageStyles.scroll()
	ls.custom_minimum_size = Vector2(0, 300)
	_left.add_child(ls)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	ls.add_child(_list)
	_left.add_child(MenuTheme.note("In flight: Esc → Save flight, or F11 quick-save / Shift+F11 quick-load."))
	_build_detail()
	_build_empty()
	visibility_changed.connect(_when_shown)
	_refresh()


func _when_shown() -> void:
	if is_visible_in_tree():
		_refresh()


## The empty state: shown instead of the list and the details when there is no save.
func _build_empty() -> void:
	_empty = PanelContainer.new()
	_empty.size_flags_horizontal = SIZE_EXPAND_FILL
	_empty.size_flags_vertical = SIZE_SHRINK_BEGIN
	_empty.add_theme_stylebox_override("panel", PageStyles.inset())
	add_child(_empty)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_empty.add_child(v)
	var t := Label.new()
	t.text = "No saved flights yet"
	MenuTheme.use_font(t, "semibold", 22)
	v.add_child(t)
	v.add_child(MenuTheme.note("In flight press Esc → Save flight, or F11 to quick-save. Shift+F11 quick-loads the last one."))
	v.add_child(MenuTheme.note("A save keeps everything: position, engine state, fuel, switches, radios, failures, weather and time."))


func _build_detail() -> void:
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(380, 0)
	_detail.add_theme_constant_override("separation", 10)
	add_child(_detail)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(0, 190)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.clip_contents = true
	_detail.add_child(_thumb)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuTheme.use_font(_title, "semibold", 22)
	_detail.add_child(_title)
	_table = GridContainer.new()
	_table.columns = 2
	_table.add_theme_constant_override("h_separation", 18)
	_table.add_theme_constant_override("v_separation", 4)
	_detail.add_child(_table)
	_info = MenuTheme.note("")
	_detail.add_child(_info)
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 10)
	bar.add_theme_constant_override("v_separation", 8)
	_detail.add_child(bar)
	_fly = Button.new()
	_fly.text = "Fly from this save  ▶"
	_fly.custom_minimum_size = Vector2(240, 48)
	MenuTheme.style_primary(_fly)
	_fly.pressed.connect(_fly_save)
	bar.add_child(_fly)
	_del = Button.new()
	_del.custom_minimum_size = Vector2(110, 48)
	_del.pressed.connect(_delete_pressed)
	bar.add_child(_del)
	_keep = Button.new()
	_keep.text = "Keep it"
	_keep.custom_minimum_size = Vector2(110, 48)
	_keep.pressed.connect(func():
		_guard.cancel()
		_show_selected()
		_del.grab_focus())
	bar.add_child(_keep)


func _refresh() -> void:
	var keep := _sel
	_saves = Situation.list_saves()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_cards.clear()
	_group = ButtonGroup.new()
	_sel = ""
	for m in _saves:
		var c := SaveCard.new().setup(m, SituationStore.load_thumb(m.get("thumb", "")))
		c.button_group = _group
		c.pressed.connect(_select.bind(m.file))
		c.activated.connect(_fly_save)
		_list.add_child(c)
		_cards.append(c)
		if m.file == keep:
			_sel = m.file
	if _sel == "" and not _saves.is_empty():
		_sel = _saves[0].file
	for c in _cards:
		c.set_pressed_no_signal(c.meta.file == _sel)
	_guard.cancel()
	_show_selected()


func _select(file: String) -> void:
	if file != _sel:
		_guard.cancel()
	_sel = file
	_show_selected()


func _selected() -> Dictionary:
	for m in _saves:
		if m.file == _sel:
			return m
	return {}


func _show_selected() -> void:
	var m := _selected()
	_detail.visible = not m.is_empty()
	_left.visible = not m.is_empty()
	_empty.visible = m.is_empty()
	_fly.disabled = m.is_empty()
	_del.disabled = m.is_empty()
	var ask := _guard.is_asked(str(m.get("file", "")))
	_del.text = "Yes, delete" if ask else "Delete"
	_keep.visible = ask
	if ask:
		MenuTheme.style_primary(_del, true, MenuTheme.BAD)
	else:
		_del.remove_theme_stylebox_override("normal")
		_del.remove_theme_stylebox_override("hover")
		_del.remove_theme_stylebox_override("pressed")
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			_del.remove_theme_color_override(k)
		_del.remove_theme_font_override("font")
	_info.text = ""
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	if m.is_empty():
		_thumb.texture = null
		return
	_thumb.texture = SituationStore.load_thumb(m.get("thumb", ""))
	_title.text = SavesLogic.title(m)
	var d := SituationStore.read(m.file)
	for r in SavesLogic.rows(m, d.get("setup", {})):
		var k := Label.new()
		k.text = r[0]
		k.add_theme_color_override("font_color", MenuTheme.DIM)
		_table.add_child(k)
		var v := Label.new()
		v.text = r[1]
		v.size_flags_horizontal = SIZE_EXPAND_FILL
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(160, 0)
		_table.add_child(v)


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
	_fly.disabled = true
	await BusyOverlay.load_scene(get_tree(), FLIGHT, "Loading scenery…")


## Delete: the first press asks, the second (on the "Yes, delete" button) deletes.
func _delete_pressed() -> void:
	var m := _selected()
	if m.is_empty():
		return
	if not _guard.is_asked(m.file):
		_guard.ask(m.file)
		_show_selected()
		_keep.grab_focus()  # the safe answer has the focus
		return
	if _guard.confirm(m.file):
		Situation.delete(m.file)
		_sel = ""
		_refresh()
