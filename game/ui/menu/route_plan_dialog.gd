class_name RoutePlanDialog
extends Control
## The Route step's "Save plan" / "Load plan" modal: a dim backdrop over the start screen and one panel in the menu style.
##   save  a name box (Enter saves), Save and Cancel; the button says Replace when that name is already saved.
##   load  the saved plans newest first (name, departure → destination, waypoints, aircraft, date) with Load and Delete.
## Esc or Cancel closes it. It only picks: `save_named(name)` / `load_picked(key)` go to RoutePlansBox, which does the
## work and closes it. While open it takes every key (the steps behind do not react), as FlyConfirm does.

signal save_named(name: String)
signal load_picked(key: String)
signal closed

var mode := "save"
var name_box: LineEdit
var save_btn: Button
var list_box: VBoxContainer
var note: Label
var _first: Control


static func make(m: String, suggested := "") -> RoutePlanDialog:
	var d := RoutePlanDialog.new()
	d.mode = m
	d.set_meta("suggested", suggested)
	return d


func _ready() -> void:
	name = "RoutePlanDialog"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.035, 0.05, 0.075, 0.97), 12, MenuTheme.LINE, 22.0))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Save plan" if mode == "save" else "Load plan"
	title.add_theme_font_size_override("font_size", MenuTheme.SIZE_BIG + 2)
	v.add_child(title)
	if mode == "save":
		_build_save(v)
	else:
		_build_load(v)
	note = MenuTheme.note("")
	note.visible = false
	v.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cancel := _button("Cancel")
	cancel.pressed.connect(close)
	row.add_child(cancel)
	if mode == "save":
		save_btn = _button("Save")
		MenuTheme.style_primary(save_btn)
		save_btn.pressed.connect(func(): save_named.emit(name_box.text))
		row.add_child(save_btn)
		_name_changed(name_box.text)
	(_first if _first != null else cancel).grab_focus.call_deferred()


func _build_save(v: VBoxContainer) -> void:
	v.add_child(MenuTheme.note("Saved plans keep the departure, the route and its altitudes. Load them from Load plan…"))
	name_box = LineEdit.new()
	name_box.text = str(get_meta("suggested", ""))
	name_box.placeholder_text = "Plan name, e.g. VABB to VAPO"
	name_box.max_length = PlanStore.MAX_NAME
	name_box.custom_minimum_size = Vector2(0, 40)
	name_box.text_changed.connect(_name_changed)
	name_box.text_submitted.connect(func(t): save_named.emit(t))
	v.add_child(name_box)
	name_box.select_all.call_deferred()
	_first = name_box


func _name_changed(t: String) -> void:
	if save_btn == null:
		return
	save_btn.text = "Replace" if PlanStore.exists(t) else "Save"
	save_btn.disabled = PlanStore.file_key(t) == ""
	save_btn.tooltip_text = "A plan with this name is saved: this replaces it." if PlanStore.exists(t) else ""


func _build_load(v: VBoxContainer) -> void:
	var plans := PlanStore.list()
	if plans.is_empty():
		v.add_child(MenuTheme.note("No saved plans yet. Plan a route, then press Save plan…"))
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, mini(plans.size(), 5) * 54)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(list_box)
	for p in plans:
		list_box.add_child(_plan_row(p))


func _plan_row(p: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.04), 8, Color(0, 0, 0, 0), 8.0))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	panel.add_child(h)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	h.add_child(col)
	var nm := Label.new()
	nm.text = str(p.name)
	nm.clip_text = true
	MenuTheme.use_font(nm, "semibold", 15)
	col.add_child(nm)
	var sub := Label.new()
	var to := str(p.dest) if str(p.dest) != "" else "…"
	sub.text = "%s → %s · %d wpt%s · %s" % [p.departure, to, int(p.wps), "" if int(p.wps) == 1 else "s", str(p.created).replace("T", " ").left(16)]
	sub.clip_text = true
	sub.add_theme_color_override("font_color", MenuTheme.DIM)
	sub.add_theme_font_size_override("font_size", 12)
	col.add_child(sub)
	var load_b := _button("Load")
	load_b.tooltip_text = "Load this plan (and its departure)"
	load_b.pressed.connect(func(): load_picked.emit(str(p.key)))
	h.add_child(load_b)
	var del := _button("Delete")
	del.tooltip_text = "Delete this saved plan"
	del.pressed.connect(func():
		PlanStore.remove(str(p.key))
		panel.queue_free()
		say("Plan \"%s\" deleted." % p.name))
	h.add_child(del)
	if _first == null:
		_first = load_b
	return panel


func say(t: String, warn := false) -> void:
	note.text = t
	note.visible = t != ""
	note.add_theme_color_override("font_color", MenuTheme.WARN if warn else MenuTheme.DIM)


func close() -> void:
	closed.emit()
	queue_free()


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(84, 38)
	return b


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _unhandled_key_input(_e: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()
