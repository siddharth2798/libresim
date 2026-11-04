class_name FailuresArmed
extends VBoxContainer
## Right-hand column of the Failures step: the ARMED list ("what you will get": every armed failure with its
## trigger and a remove button, a line for random failures, "0 armed" when empty, Clear all) and the RANDOM
## FAILURES settings (switch, how many, time window, which systems) with the "Tell me when something fails"
## switch. All values live in Session.setup (failures, random, notify). `refresh()` repaints everything from there.
## Signals: `changed` after any edit; `removed(id)` when an armed row's button disarmed a failure (or Clear all, id "").
## After a remove the list is rebuilt, so the keyboard focus is put back at once: on the next armed row's x, else the
## previous one's, else Clear all while it is shown; when none of those exists `focus_lost` tells the page
## (failures_page.gd), which focuses the first failure switch. (After `changed`: the page repaints this list again.)

signal changed
signal removed(id: String)
signal focus_lost  # a remove left nothing here to focus: the page picks a control

var count_label: Label
var list: VBoxContainer
var clear_btn: Button
var remove_btns := {}  # failure id -> its x Button (rebuilt with the list)
var random_switch: SwitchRow
var notify_switch: SwitchRow
var _random_box: VBoxContainer
var _spins := {}  # random key -> SpinBox
var _chips := {}  # category name -> Button
var _chips_flow: HFlowContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_child(MenuTheme.heading("Armed"))
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(gap)
	count_label = Label.new()
	count_label.add_theme_color_override("font_color", MenuTheme.DIM)
	head.add_child(count_label)
	add_child(head)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	clear_btn = Button.new()
	clear_btn.text = "Clear all scheduled failures"
	clear_btn.pressed.connect(_clear_all)
	add_child(clear_btn)
	add_child(HSeparator.new())
	add_child(MenuTheme.heading("Random failures"))
	random_switch = SwitchRow.new().setup("Random failures", "You are not told which ones are armed.")
	random_switch.tooltip_text = "Failures that happen by themselves during the flight."
	random_switch.toggled.connect(func(on):
		Session.setup.random.enabled = on
		refresh()
		changed.emit())
	add_child(random_switch)
	_build_random_settings()
	notify_switch = SwitchRow.new().setup("Tell me when something fails", "Off: find out from the instruments, like the real thing.")
	notify_switch.tooltip_text = "Off = realistic: you only find out from the instruments, the engine note and the aircraft's behaviour."
	notify_switch.toggled.connect(func(on): Session.setup.notify = on)
	add_child(notify_switch)


func _build_random_settings() -> void:
	_random_box = VBoxContainer.new()
	_random_box.add_theme_constant_override("separation", 6)
	add_child(_random_box)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	_random_box.add_child(g)
	for row in [["How many", 1, 5, "count"], ["Not before (min)", 0, 240, "from_min"], ["Not after (min)", 1, 240, "to_min"]]:
		var l := Label.new()
		l.text = row[0]
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		g.add_child(l)
		var sb := SpinBox.new()
		sb.min_value = row[1]
		sb.max_value = row[2]
		sb.custom_minimum_size = Vector2(110, 0)
		var key: String = row[3]
		sb.value_changed.connect(func(v):
			Session.setup.random[key] = v
			_update_count()
			changed.emit())
		g.add_child(sb)
		_spins[key] = sb
	_random_box.add_child(MenuTheme.note("From these systems"))
	_chips_flow = HFlowContainer.new()
	_chips_flow.add_theme_constant_override("h_separation", 6)
	_chips_flow.add_theme_constant_override("v_separation", 6)
	_random_box.add_child(_chips_flow)


## Repaint from Session.setup (also rebuilds the system chips when the aircraft's catalog changed).
func refresh() -> void:
	var s: Dictionary = Session.setup
	var cats: Array = FailureCatalog.category_names()
	if cats != _chips.keys():
		_rebuild_chips(cats)
	for name in _chips:
		(_chips[name] as Button).set_pressed_no_signal(name in s.random.categories)
	random_switch.set_on(bool(s.random.enabled))
	notify_switch.set_on(bool(s.notify))
	for key in _spins:
		(_spins[key] as SpinBox).set_value_no_signal(float(s.random[key]))
	_random_box.visible = bool(s.random.enabled)
	_rebuild_list()


func _rebuild_chips(cats: Array) -> void:
	for c in _chips.values():
		c.queue_free()
	_chips.clear()
	for name in cats:
		var b := Button.new()
		b.text = name
		PageStyles.chip(b)
		b.toggled.connect(func(on):
			var r: Array = Session.setup.random.categories
			if on and not name in r:
				r.append(name)
			elif not on:
				r.erase(name)
			_update_count()
			changed.emit())
		_chips_flow.add_child(b)
		_chips[name] = b


func _rebuild_list() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	remove_btns.clear()
	var rows := FailuresLogic.armed(Session.setup.failures, FailureCatalog.categories())
	for a in rows:
		list.add_child(_armed_row(a))
	var rnd := FailuresLogic.random_text(Session.setup.random, FailureCatalog.category_names())
	if rnd != "":
		list.add_child(_text_row("Random", rnd))
	if rows.is_empty() and rnd == "":
		list.add_child(MenuTheme.note("Nothing scheduled. The flight will have no failures unless you arm one here or switch on random failures."))
	clear_btn.visible = FailuresLogic.any_armed(Session.setup)
	_update_count()


func _update_count() -> void:
	var n := FailuresLogic.armed(Session.setup.failures, FailureCatalog.categories()).size()
	var r := " + random" if bool(Session.setup.random.enabled) else ""
	count_label.text = "%d armed%s" % [n, r]


func _armed_row(a: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.07), 8, Color(0, 0, 0, 0), 10.0))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	hb.add_child(col)
	var t := Label.new()
	t.text = a.label
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(80, 0)
	col.add_child(t)
	var sub := MenuTheme.note(a.text)
	sub.add_theme_color_override("font_color", MenuTheme.ACCENT)
	col.add_child(sub)
	var x := Button.new()
	x.text = "×"
	x.tooltip_text = "Remove: " + a.label
	x.focus_mode = Control.FOCUS_ALL
	x.size_flags_vertical = SIZE_SHRINK_CENTER
	x.custom_minimum_size = Vector2(32, 32)
	PageStyles.tiny_button(x)
	var id: String = a.id
	x.pressed.connect(func():
		var ids := _armed_ids()
		FailuresLogic.set_trigger(Session.setup.failures, id, 0)
		refresh()
		removed.emit(id)
		changed.emit()
		_focus_after_remove(ids, ids.find(id)))
	remove_btns[id] = x
	hb.add_child(x)
	return p


func _armed_ids() -> Array:
	return FailuresLogic.armed(Session.setup.failures, FailureCatalog.categories()).map(func(a): return a.id)


## Focus after the armed list was rebuilt without ids[at]: the next row's x, else the previous row's, else Clear all,
## else `focus_lost`. at = -1 (Clear all): only Clear all or `focus_lost`.
func _focus_after_remove(ids: Array, at: int) -> void:
	if not is_inside_tree():
		return
	for k in ([at + 1, at - 1] if at >= 0 else []):
		if k >= 0 and k < ids.size() and remove_btns.has(ids[k]):
			(remove_btns[ids[k]] as Button).grab_focus()
			return
	if clear_btn.visible and clear_btn.is_visible_in_tree():
		clear_btn.grab_focus()
	else:
		focus_lost.emit()


func _text_row(title: String, text: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.07), 8, Color(0, 0, 0, 0), 10.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	p.add_child(col)
	col.add_child(Label.new())
	(col.get_child(0) as Label).text = title
	var sub := MenuTheme.note(text)
	sub.add_theme_color_override("font_color", MenuTheme.ACCENT)
	col.add_child(sub)
	return p


func _clear_all() -> void:
	FailuresLogic.clear_all(Session.setup)
	refresh()
	removed.emit("")
	changed.emit()
	_focus_after_remove([], -1)
