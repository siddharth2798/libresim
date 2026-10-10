extends PanelContainer
## Interactive checklists (F2). Items with a property condition tick themselves when
## the aircraft state matches; the others tick on click (or Enter = next unticked).
## PageUp/PageDown inside the panel switch lists (Ctrl+PgUp/PgDn while flying).
## Data: aircraft/c172/checklists.json.

var lists: Array = []
var current := 0
var _manual := {}  # "list/item" -> true
var _vb: VBoxContainer
var _title: Label
var _rows: Array = []


func _ready() -> void:
	var d = Paths.load_res_json("res://aircraft/c172/checklists.json")
	lists = d.lists if d else []
	visible = false
	set_anchors_preset(PRESET_TOP_LEFT)
	position = Vector2(10, 300)
	custom_minimum_size = Vector2(430, 0)
	modulate = Color(1, 1, 1, 0.93)
	_vb = VBoxContainer.new()
	add_child(_vb)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	_vb.add_child(_title)
	_rebuild()


func _rebuild() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	if lists.is_empty():
		return
	var l: Dictionary = lists[current]
	_title.text = "%s  (%d/%d)   Ctrl+PgUp/PgDn lists · Enter tick" % [l.name, current + 1, lists.size()]
	for i in l.items.size():
		var b := CheckBox.new()
		b.text = l.items[i].text
		b.focus_mode = Control.FOCUS_NONE
		var key := "%d/%d" % [current, i]
		b.toggled.connect(func(on): _manual[key] = on)
		_vb.add_child(b)
		_rows.append(b)


static func _met(item: Dictionary) -> bool:
	if not item.has("prop"):
		return false
	var v = Props.get_v(item.prop)
	if v == null:
		return false
	if item.has("eq"):
		if item.eq is bool:
			return bool(v) == item.eq
		return is_equal_approx(float(v), float(item.eq))
	if item.has("range"):
		return float(v) >= item.range[0] and float(v) <= item.range[1]
	return false


func _process(_dt: float) -> void:
	if not visible or lists.is_empty():
		return
	var l: Dictionary = lists[current]
	for i in _rows.size():
		var item: Dictionary = l.items[i]
		var b: CheckBox = _rows[i]
		var auto := _met(item)
		var done: bool = auto or _manual.get("%d/%d" % [current, i], false)
		b.set_pressed_no_signal(done)
		b.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if done else Color(1, 1, 1))
		b.disabled = auto


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_F2:
		visible = not visible
	elif visible and e.ctrl_pressed and e.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		current = clampi(current + (1 if e.keycode == KEY_PAGEDOWN else -1), 0, lists.size() - 1)
		_rebuild()
		get_viewport().set_input_as_handled()
	elif visible and e.keycode == KEY_ENTER:
		for i in _rows.size():
			if not _rows[i].button_pressed:
				_manual["%d/%d" % [current, i]] = true
				break
		get_viewport().set_input_as_handled()
