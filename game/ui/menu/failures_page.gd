extends HBoxContainer
## Start screen step 4 (optional): failures. Three columns: AREAS (the aircraft's failure categories, each with how many
## are armed), SCHEDULE A FAILURE (one switch per failure of the chosen area; an armed one shows its trigger: at
## start, after N minutes, above N ft AGL, above N kt) and the right column (failures_armed.gd: what is armed, random
## failures, "tell me"). Failures an aircraft cannot have stay hidden (FailureCatalog, its aircraft.json failures.disabled).
## In flight, F9 shows state and fails / repairs live. Setup keys: Session.setup.failures / random / notify (unchanged).
## The page is rebuilt when it is shown after the aircraft (and so the catalog) changed.

signal changed

var _areas: VBoxContainer
var _title: Label
var _lists := {}  # category -> VBoxContainer of FailureRow
var _tabs := {}  # category -> [Button, badge Label]
var _rows := {}  # failure id -> FailureRow
var _holder: Control  # the middle column's scroll area: shows the current category's list
var _armed: FailuresArmed
var _group := ButtonGroup.new()
var _key := ""
var _cur := ""


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.add_theme_constant_override("separation", 8)
	left.add_child(MenuTheme.heading("Areas"))
	var ls := PageStyles.scroll()
	left.add_child(ls)
	_areas = VBoxContainer.new()
	_areas.size_flags_horizontal = SIZE_EXPAND_FILL
	_areas.add_theme_constant_override("separation", 2)
	ls.add_child(_areas)
	add_child(left)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.custom_minimum_size = Vector2(300, 0)
	mid.add_theme_constant_override("separation", 8)
	_title = MenuTheme.heading("Schedule a failure")
	mid.add_child(_title)
	var ms := PageStyles.scroll()
	mid.add_child(ms)
	_holder = VBoxContainer.new()
	_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	ms.add_child(_holder)
	add_child(mid)
	var rs := PageStyles.scroll()
	rs.size_flags_horizontal = SIZE_FILL
	rs.custom_minimum_size = Vector2(250, 260)
	_armed = FailuresArmed.new()
	_armed.size_flags_horizontal = SIZE_EXPAND_FILL
	_armed.changed.connect(_on_changed)
	_armed.removed.connect(_on_removed)
	_armed.focus_lost.connect(_on_focus_lost)
	var pad := MarginContainer.new()  # room for the scroll bar
	pad.add_theme_constant_override("margin_right", 12)
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_child(_armed)
	rs.add_child(pad)
	add_child(rs)
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


## Repaint from Session.setup; rebuild the areas and rows first when the aircraft's catalog is not the one shown.
func refresh() -> void:
	var cats: Array = FailureCatalog.categories()
	if str(cats.hash()) + AircraftDef.current().id != _key:
		_rebuild(cats)
	for id in _rows:
		(_rows[id] as FailureRow).refresh()
	_armed.refresh()
	_update_badges()


func _rebuild(cats: Array) -> void:
	_key = str(cats.hash()) + AircraftDef.current().id
	for c in _areas.get_children():
		_areas.remove_child(c)
		c.queue_free()
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_lists.clear()
	_tabs.clear()
	_rows.clear()
	_group = ButtonGroup.new()
	for c in cats:
		var b := Button.new()
		b.text = c[0]
		b.button_group = _group
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		PageStyles.list_item(b)
		var badge := PageStyles.badge_on(b)
		b.pressed.connect(_show_category.bind(c[0]))
		_areas.add_child(b)
		_tabs[c[0]] = [b, badge]
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		v.size_flags_horizontal = SIZE_EXPAND_FILL
		v.visible = false
		for f in c[1]:
			var row := FailureRow.new().setup(f[0], f[1])
			row.changed.connect(_on_changed)
			v.add_child(row)
			_rows[f[0]] = row
		_holder.add_child(v)
		_lists[c[0]] = v
	if not _lists.has(_cur):
		_cur = cats[0][0] if not cats.is_empty() else ""
	_show_category(_cur)


func _show_category(name: String) -> void:
	_cur = name
	for k in _lists:
		(_lists[k] as Control).visible = k == name
	if _tabs.has(name):
		(_tabs[name][0] as Button).set_pressed_no_signal(true)
	_title.text = "SCHEDULE A FAILURE  ·  %s" % name.to_upper() if name != "" else "SCHEDULE A FAILURE"


func _update_badges() -> void:
	for c in FailureCatalog.categories():
		if _tabs.has(c[0]):
			var n := FailuresLogic.armed_in(Session.setup.failures, c)
			(_tabs[c[0]][1] as Label).text = str(n) if n > 0 else ""


## A row, the armed list or a random setting changed something.
func _on_changed() -> void:
	_armed.refresh()
	_update_badges()
	changed.emit()


## An armed row's remove button or Clear all: the rows show the new state.
func _on_removed(_id: String) -> void:
	for id in _rows:
		(_rows[id] as FailureRow).refresh()


## A remove left no armed row's x or Clear all to focus: the area's first failure switch.
func _on_focus_lost() -> void:
	if is_visible_in_tree() and _lists.has(_cur):
		var rows := (_lists[_cur] as Control).get_children().filter(func(r): return r is FailureRow)
		if not rows.is_empty():
			(rows[0] as FailureRow).switch.grab_focus()
