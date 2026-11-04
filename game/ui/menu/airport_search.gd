class_name AirportSearch
extends LineEdit
## Search box with a drop-down list (a PopupPanel holding an ItemList). Type an ICAO code, a name or a city; the list
## filters on every keystroke; Up / Down move, Enter picks, Esc closes and puts the chosen airport's name back, a click
## picks too. The popup is `unfocusable` so the keys keep going to this box while the list is open.
## Items: [{id, ident, name, city, text, note, short}] (AirportData.search_items). `picked(id)` is the only output; the
## owner decides what a pick does and calls set_current() to show the result.

signal picked(id: String)

const MAX_ROWS := 9

var items: Array = []  # all entries
var shown: Array = []  # the entries of the list now (filter(items, text))
var current := ""  # the id shown in the box when it is not being edited
var _popup: PopupPanel
var _list: ItemList
var _active := 0
var _picking := false


func _init() -> void:
	placeholder_text = "Search airport: ICAO, name or city…"
	clear_button_enabled = false
	select_all_on_focus = true
	_list = ItemList.new()
	_list.focus_mode = Control.FOCUS_NONE
	_list.same_column_width = true
	_list.item_clicked.connect(func(i, _p, b):
		if b == MOUSE_BUTTON_LEFT:
			_pick(i))
	_popup = PopupPanel.new()
	_popup.unfocusable = true
	_popup.add_child(_list)
	_popup.popup_hide.connect(_on_hidden)
	_list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_changed.connect(_on_text)
	gui_input.connect(_on_gui_input)  # (the signal comes before the LineEdit's own key handling, so accept_event() wins)
	focus_exited.connect(_close)
	add_child(_popup)


func set_items(list: Array) -> void:
	items = list
	if _popup.visible:
		_refill()


## Shows airport `id` in the box (not an edit: the list is not opened and nothing is picked).
func set_current(id: String) -> void:
	current = id
	if not has_focus() or not _popup.visible:
		_restore_text()


func is_open() -> bool:
	return _popup.visible


## Entries that match `q` (ICAO, name or city, case-insensitive, every word of the query must match somewhere):
## ICAO starts with the query first, then ICAO contains, then the rest; original order inside a group.
static func filter(list: Array, q: String) -> Array:
	var words := q.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return list.duplicate()
	var keyed := []
	for i in list.size():
		var e: Dictionary = list[i]
		var ident := str(e.ident).to_lower()
		var hay := "%s %s %s" % [ident, str(e.name).to_lower(), str(e.get("city", "")).to_lower()]
		var ok := true
		for w in words:
			ok = ok and w in hay
		if not ok:
			continue
		var rank := 2
		if ident.begins_with(words[0]):
			rank = 0
		elif words[0] in ident:
			rank = 1
		keyed.append([rank, i])
	keyed.sort_custom(func(a, b): return a[1] < b[1] if a[0] == b[0] else a[0] < b[0])
	return keyed.map(func(k): return list[k[1]])


func _on_text(t: String) -> void:
	if _picking:
		return
	_active = 0
	_open()


## Opens (or refreshes) the list for the text now in the box.
func _open() -> void:
	_refill()
	if _popup.visible or not is_inside_tree():
		return
	var r := get_global_rect()
	_popup.popup_on_parent(Rect2i(Vector2i(r.position + Vector2(0, r.size.y + 4)), _fit()))


func _refill() -> void:
	var q := text
	if not items.is_empty() and q == _label_of(current):
		q = ""  # the box shows the chosen airport: opening it lists them all
	shown = filter(items, q)
	_list.clear()
	for e in shown:
		var i := _list.add_item(str(e.text))
		_list.set_item_tooltip(i, "%s%s" % [str(e.get("note", "")), "  ·  too short for this aircraft" if e.get("short", false) else ""])
		if e.get("short", false):
			_list.set_item_custom_fg_color(i, MenuTheme.FAINT)
	if shown.is_empty():
		_list.add_item("No airport matches “%s”." % text)
		_list.set_item_disabled(0, true)
	_active = clampi(_active, 0, maxi(shown.size() - 1, 0))
	if not shown.is_empty():
		_list.select(_active)
		_list.ensure_current_is_visible()
	if _popup.visible:
		_popup.size = _fit()


## Sizes the list for the rows now in it (at most MAX_ROWS, then it scrolls) and returns the popup's size.
func _fit() -> Vector2i:
	var rows := clampi(_list.item_count, 1, MAX_ROWS)
	var row_h := _list.get_theme_font("font").get_height(_list.get_theme_font_size("font_size")) + 8.0 + _list.get_theme_constant("v_separation")
	var r := get_global_rect()
	var room := get_viewport().get_visible_rect().size.x - r.position.x - 8.0
	var w := minf(maxf(r.size.x, 560.0), maxf(room, r.size.x))
	_list.custom_minimum_size = Vector2(w - 10.0, rows * row_h + 8.0)
	return Vector2i(int(w), int(_list.custom_minimum_size.y) + 10)


func _on_gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _popup.visible:
		_active = 0
		_open()  # a click on a box that already has the focus
		return
	if not (e is InputEventKey) or not e.pressed:
		return
	match e.keycode:
		KEY_DOWN, KEY_UP:
			if not _popup.visible:
				_open()
			elif not shown.is_empty():
				_active = posmod(_active + (1 if e.keycode == KEY_DOWN else -1), shown.size())
				_list.select(_active)
				_list.ensure_current_is_visible()
			accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if _popup.visible and not shown.is_empty():
				_pick(_active)
			accept_event()
		KEY_ESCAPE:
			if _popup.visible:
				_close()
				_restore_text()
				accept_event()  # the first Esc only closes the list; the next one leaves the page


func _pick(i: int) -> void:
	if i < 0 or i >= shown.size():
		return
	var id := str(shown[i].id)
	_picking = true
	current = id
	_close()
	_restore_text()
	_picking = false
	picked.emit(id)
	release_focus()


func _close() -> void:
	if _popup.visible:
		_popup.hide()


func _on_hidden() -> void:
	if not has_focus():
		_restore_text()


func _label_of(id: String) -> String:
	for e in items:
		if e.id == id:
			return "%s · %s" % [str(e.ident), _short_name(str(e.name))]
	return id


## "Chhatrapati Shivaji Maharaj International Airport" -> "Chhatrapati Shivaji Maharaj International".
static func _short_name(n: String) -> String:
	for suffix in [" Airport", " Aerodrome"]:
		if n.ends_with(suffix):
			return n.trim_suffix(suffix)
	return n


func _restore_text() -> void:
	var t := _label_of(current)
	if text != t:
		text = t
		caret_column = 0
