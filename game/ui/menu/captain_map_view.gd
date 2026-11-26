class_name CaptainMapView
extends RefCounted
## The widgets of the Captain Pack map (ui/menu/captain_map_panel.gd): window layout, header (title, aircraft switch, connection chip, note),
## the pictures with their lists, the detail strip with its actions (Choose action, Bind, Clear, Invert, part selector), the Identify
## row, the message line and the footer. Built once when the panel opens. Text of the detail strip: ui/menu/captain_map_text.gd.


static func build(p: CaptainMapPanel) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.035, 0.05, 0.075, 0.97), 12, Color(MenuTheme.ACCENT, 0.85), 18.0))
	margin.add_child(panel)
	p.main = VBoxContainer.new()
	p.main.add_theme_constant_override("separation", 8)
	var stack := VBoxContainer.new()  # the main view and, in its place, the action picker
	panel.add_child(stack)
	stack.add_child(p.main)
	p.main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.stack = stack
	_header(p, p.main)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.main.add_child(scroll)
	var cols := BoxContainer.new()  # side by side; stacked (scrolling) in a window narrower than STACK_BELOW
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.custom_minimum_size = Vector2(0, 300)
	scroll.add_child(cols)
	p.cols = cols
	for dev in CaptainMap.devices():
		cols.add_child(_device(p, dev))
	_detail(p, p.main)
	_footer(p, p.main)


## A short window (UI scale 150 % and up on a small screen) drops the note and shrinks the detail strip, so the pictures keep room.
static func fit(p: CaptainMapPanel, short: bool) -> void:
	p.note.visible = not short
	p.detail.custom_minimum_size.y = 52.0 if short else 80.0
	p.msg.custom_minimum_size.y = 0.0 if short else 22.0
	for pic in p.pictures.values():  # stacked: the pictures stay small enough to see a whole device in the scrolling area
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if p.cols.vertical else Control.SIZE_EXPAND_FILL
		pic.custom_minimum_size.y = 250.0 if p.cols.vertical else 300.0


static func _header(p: CaptainMapPanel, v: Control) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var title := Label.new()
	title.text = "Captain Pack map"
	title.add_theme_font_size_override("font_size", MenuTheme.SIZE_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var ids := AircraftDef.list_ids()
	if ids.size() > 1:
		var l := Label.new()
		l.text = "Aircraft"
		l.add_theme_color_override("font_color", MenuTheme.DIM)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(l)
		p.aircraft_switch = Segmented.new()
		p.aircraft_switch.equal_width = false
		p.aircraft_switch.set_options(ids.map(func(id): return [id, ControlsHeader.aircraft_name(id)]), p.controls.id)
		p.aircraft_switch.selected.connect(func(id): p.set_aircraft(str(id)))
		head.add_child(p.aircraft_switch)
	p.status = Label.new()
	p.status.add_theme_font_size_override("font_size", MenuTheme.SIZE_BODY)
	head.add_child(p.status)
	p.note = MenuTheme.note("")
	p.note.custom_minimum_size = Vector2(200, 40)  # two lines
	v.add_child(p.note)


static func _button(text: String, primary: bool, w: float, h := 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", MenuTheme.SIZE_BODY)
	MenuTheme.style_primary(b, primary)
	return b


static func _device(p: CaptainMapPanel, dev: String) -> Control:
	var info: Dictionary = CaptainMap.data().devices[dev]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 0.95 if dev == "sidestick" else 1.2
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var ms: Array = info.markers
	var pic := CaptainMapPicture.new().setup(dev, CaptainMapPicture.load_texture(str(info.get("image", ""))), ms, float(info.get("aspect", 1.0)))
	pic.title = str(info.get("title", dev))
	pic.marker_clicked.connect(func(id: String): p.select(dev, id))
	row.add_child(pic)
	var leg := CaptainMapLegend.new().build(dev, ms)
	leg.picked.connect(func(id: String): p.select(dev, id))
	row.add_child(leg)
	p.pictures[dev] = pic
	p.legends[dev] = leg
	return col


static func _detail(p: CaptainMapPanel, v: Control) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL_2, 8, MenuTheme.LINE, 10.0))
	v.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	p.detail = Label.new()
	p.detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.detail.custom_minimum_size = Vector2(200, 80)  # four lines, so the layout does not jump when a marker is selected
	p.detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.detail.add_theme_font_size_override("font_size", 14)
	top.add_child(p.detail)
	var acts := VBoxContainer.new()  # the actions of the selected control, right of its text
	acts.add_theme_constant_override("separation", 6)
	top.add_child(acts)
	p.part_pick = OptionButton.new()
	p.part_pick.custom_minimum_size = Vector2(300, 34)
	p.part_pick.item_selected.connect(p.pick_part)
	acts.add_child(p.part_pick)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	acts.add_child(row1)
	p.choose_btn = _button("Choose action…", true, 200)
	p.choose_btn.pressed.connect(p.open_picker)
	row1.add_child(p.choose_btn)
	p.clear_btn = _button("Clear", false, 92)
	p.clear_btn.pressed.connect(p.clear_selected)
	row1.add_child(p.clear_btn)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	acts.add_child(row2)
	p.bind_btn = _button("Bind", false, 200)
	p.bind_btn.pressed.connect(p.start_bind)
	row2.add_child(p.bind_btn)
	p.invert_btn = CheckButton.new()
	p.invert_btn.text = "Invert"
	p.invert_btn.tooltip_text = "Swap on and off for this switch"
	p.invert_btn.toggled.connect(p.set_invert)
	row2.add_child(p.invert_btn)
	var ident := HBoxContainer.new()
	ident.add_theme_constant_override("separation", 8)
	ident.visible = false
	col.add_child(ident)
	p.ident_row = ident
	p.ident_label = Label.new()
	p.ident_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.ident_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ident.add_child(p.ident_label)
	p.ident_pick = OptionButton.new()
	p.ident_pick.custom_minimum_size = Vector2(250, 36)
	ident.add_child(p.ident_pick)
	p.ident_save = _button("Save", true, 90, 36.0)
	p.ident_save.pressed.connect(p.save_identified)
	ident.add_child(p.ident_save)
	p.msg = Label.new()
	p.msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.msg.custom_minimum_size = Vector2(200, 22)
	v.add_child(p.msg)


static func _footer(p: CaptainMapPanel, v: Control) -> void:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	v.add_child(foot)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	p.identify_btn = _button("Identify", false, 120)
	p.identify_btn.toggle_mode = true
	p.identify_btn.tooltip_text = "Press any button or move any axis on the pack: its marker is selected. A number the map does not know can be taught."
	p.identify_btn.toggled.connect(p.set_identify)
	foot.add_child(p.identify_btn)
	p.reset_btn = _button("Reset to the Airbus Captain Pack profile", false, 300)
	p.reset_btn.pressed.connect(p.reset_profile)
	foot.add_child(p.reset_btn)
	p.close_btn = _button("Close", true, 120)
	p.close_btn.pressed.connect(p.close)
	foot.add_child(p.close_btn)


## Tab / Shift+Tab cycle through the visible buttons of the main view; Up / Down walk a list, Left / Right cross to the other list.
static func wire_focus(p: CaptainMapPanel) -> void:
	var ring: Array[Button] = []
	var lists: Array = []
	for dev in CaptainMap.devices():
		var l: Array[Button] = []
		for id in p.legends[dev].ids():
			l.append(p.legends[dev].rows[id].button)
		lists.append(l)
		ring.append_array(l)
	var tail: Array[Button] = [p.choose_btn, p.bind_btn, p.clear_btn, p.identify_btn, p.reset_btn, p.close_btn]
	ring.append_array(tail)
	for i in ring.size():
		ring[i].focus_next = ring[i].get_path_to(ring[(i + 1) % ring.size()])
		ring[i].focus_previous = ring[i].get_path_to(ring[(i - 1 + ring.size()) % ring.size()])
	for li in lists.size():
		var l: Array = lists[li]
		var other: Array = lists[(li + 1) % lists.size()]
		for i in l.size():
			var b: Button = l[i]
			b.focus_neighbor_top = b.get_path_to(l[maxi(i - 1, 0)])
			b.focus_neighbor_bottom = b.get_path_to(l[mini(i + 1, l.size() - 1)] if i < l.size() - 1 else p.choose_btn)
			b.focus_neighbor_left = b.get_path_to(other[mini(i, other.size() - 1)] if li > 0 else b)
			b.focus_neighbor_right = b.get_path_to(other[mini(i, other.size() - 1)] if li < lists.size() - 1 else b)
	for i in tail.size():
		var b: Button = tail[i]
		b.focus_neighbor_left = b.get_path_to(tail[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(tail[mini(i + 1, tail.size() - 1)])
		b.focus_neighbor_top = b.get_path_to(lists[0][lists[0].size() - 1] if i < 3 else p.choose_btn)
		b.focus_neighbor_bottom = b.get_path_to(b if i < 3 else b)
