extends HBoxContainer
## Start screen page 4 (optional): schedule failures for any system (at start, after N minutes,
## climbing through N ft AGL, or above N kt) and/or random failures (how many, in which
## time window, from which systems). In flight, F9 shows state and fails / repairs live.

signal changed

var _rows := {}  # id -> [OptionButton, SpinBox]
var _en: CheckBox  # random failures on / off


func _ready() -> void:
	var root := VBoxContainer.new()  # the start screen scrolls the page
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var s: Dictionary = Session.setup
	var bar := _toolbar(root, s)
	var cols := HBoxContainer.new()  # the scheduled failures, categories split over two columns
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)
	var cats: Array = FailureCatalog.categories()
	var total := 0
	for c in cats:
		total += c[1].size() + 1
	var left := _column(cols)
	var right := _column(cols)
	var used := 0
	for c in cats:
		var col: VBoxContainer = left if used * 2 < total else right
		used += c[1].size() + 1
		col.add_child(MenuTheme.heading(c[0]))
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("v_separation", 4)
		col.add_child(g)
		for f in c[1]:
			_row(g, f, s)
	_clear_button(bar, s)


func _column(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	return v


func _row(g: GridContainer, f: Array, s: Dictionary) -> void:
	var l := Label.new()
	l.text = f[1]
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(230, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.add_child(l)
	var ob := OptionButton.new()
	for m in FailureCatalog.MODES:
		ob.add_item(m)
	ob.custom_minimum_size = Vector2(150, 0)
	g.add_child(ob)
	var sb := SpinBox.new()
	sb.max_value = 20000
	sb.custom_minimum_size = Vector2(120, 0)
	g.add_child(sb)
	_rows[f[0]] = [ob, sb]
	var cur: Array = s.failures.get(f[0], [0, 0.0])
	ob.select(int(cur[0]))
	sb.set_value_no_signal(float(cur[1]))
	ob.item_selected.connect(func(_i): _store(f[0], true))
	sb.value_changed.connect(func(_v): _store(f[0], false))
	_style(f[0])


## Top row: random failures (its settings appear when it is on), the notify option, Clear all.
func _toolbar(root: Control, s: Dictionary) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 20)
	root.add_child(bar)
	var r: Dictionary = s.random
	var more := VBoxContainer.new()  # the random failures' settings, shown while they are enabled
	more.add_theme_constant_override("separation", 8)
	_en = CheckBox.new()
	_en.text = "Random failures"
	_en.tooltip_text = "Failures that happen by themselves during the flight."
	_en.button_pressed = bool(r.enabled)
	_en.toggled.connect(func(on):
		r.enabled = on
		more.visible = on
		changed.emit())
	bar.add_child(_en)
	var nt := CheckBox.new()
	nt.text = "Tell me when something fails"
	nt.tooltip_text = "Off = realistic: you only find out from the instruments, the engine note and the aircraft's behaviour."
	nt.button_pressed = bool(s.notify)
	nt.toggled.connect(func(on): s.notify = on)
	bar.add_child(nt)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(spacer)
	root.add_child(more)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 24)
	more.add_child(nums)
	_num(nums, "How many", 1, 5, 1, r, "count")
	_num(nums, "Not before (min)", 0, 240, 1, r, "from_min")
	_num(nums, "Not after (min)", 1, 240, 1, r, "to_min")
	var cg := HFlowContainer.new()
	cg.add_theme_constant_override("h_separation", 8)
	more.add_child(cg)
	for name in FailureCatalog.category_names():
		var cb := CheckBox.new()
		cb.text = name
		cb.button_pressed = name in r.categories
		cb.toggled.connect(func(on):
			if on and not name in r.categories:
				r.categories.append(name)
			elif not on:
				r.categories.erase(name))
		cg.add_child(cb)
	more.visible = _en.button_pressed
	return bar


func _clear_button(bar: Control, s: Dictionary) -> void:
	var clr := Button.new()
	clr.text = "Clear all scheduled failures"
	clr.pressed.connect(func():
		s.failures = {}
		_en.button_pressed = false
		for id in _rows:
			_rows[id][0].select(0)
			_style(id)
		changed.emit())
	bar.add_child(clr)


func _num(parent: Control, label: String, lo: float, hi: float, step: float, d: Dictionary, key: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	hb.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = float(d[key])
	sb.value_changed.connect(func(v): d[key] = v)
	hb.add_child(sb)


## Sensible default value when a trigger mode is picked.
func _store(id: String, mode_changed: bool) -> void:
	var ob: OptionButton = _rows[id][0]
	var sb: SpinBox = _rows[id][1]
	var mode := ob.selected
	if mode_changed:
		sb.set_value_no_signal([0.0, 0.0, 10.0, 1000.0, 100.0][mode])
	if mode == 0:
		Session.setup.failures.erase(id)
	else:
		Session.setup.failures[id] = [mode, sb.value]
	_style(id)
	changed.emit()


func _style(id: String) -> void:
	var mode: int = _rows[id][0].selected
	var sb: SpinBox = _rows[id][1]
	sb.modulate.a = 1.0 if mode >= 2 else 0.0  # (hiding would shift the grid columns)
	sb.editable = mode >= 2
	sb.suffix = FailureCatalog.MODE_UNITS[mode]
