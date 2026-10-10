extends HBoxContainer
## Start screen page 4: schedule failures for any system (at start, after N minutes,
## climbing through N ft AGL, or above N kt) and/or random failures (how many, in which
## time window, from which systems). In flight, F9 shows state and fails / repairs live.

signal changed

var _rows := {}  # id -> [OptionButton, SpinBox]


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	var list := VBoxContainer.new()  # the start screen scrolls the page
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(list)
	var s: Dictionary = Session.setup
	for c in FailureCatalog.CATEGORIES:
		list.add_child(MenuTheme.heading(c[0]))
		var g := GridContainer.new()
		g.columns = 3
		list.add_child(g)
		for f in c[1]:
			var l := Label.new()
			l.text = f[1]
			l.size_flags_horizontal = SIZE_EXPAND_FILL
			g.add_child(l)
			var ob := OptionButton.new()
			for m in FailureCatalog.MODES:
				ob.add_item(m)
			ob.custom_minimum_size = Vector2(170, 0)
			g.add_child(ob)
			var sb := SpinBox.new()
			sb.max_value = 20000
			sb.custom_minimum_size = Vector2(150, 0)
			g.add_child(sb)
			_rows[f[0]] = [ob, sb]
			var cur: Array = s.failures.get(f[0], [0, 0.0])
			ob.select(int(cur[0]))
			sb.set_value_no_signal(float(cur[1]))
			ob.item_selected.connect(func(_i): _store(f[0], true))
			sb.value_changed.connect(func(_v): _store(f[0], false))
			_style(f[0])
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(340, 0)
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	right.add_child(MenuTheme.heading("Random failures"))
	var r: Dictionary = s.random
	var en := CheckBox.new()
	en.text = "Enable random failures"
	en.button_pressed = bool(r.enabled)
	en.toggled.connect(func(on):
		r.enabled = on
		changed.emit())
	right.add_child(en)
	_num(right, "How many", 1, 5, 1, r, "count")
	_num(right, "Not before (min)", 0, 240, 1, r, "from_min")
	_num(right, "Not after (min)", 1, 240, 1, r, "to_min")
	right.add_child(MenuTheme.note("Systems that may fail:"))
	var cg := GridContainer.new()
	cg.columns = 2
	right.add_child(cg)
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
	right.add_child(HSeparator.new())
	var nt := CheckBox.new()
	nt.text = "Tell me when something fails"
	nt.button_pressed = bool(s.notify)
	nt.toggled.connect(func(on): s.notify = on)
	right.add_child(nt)
	right.add_child(MenuTheme.note("Off = realistic: you only find out from the instruments, the engine note and the aircraft's behaviour."))
	var clr := Button.new()
	clr.text = "Clear all scheduled failures"
	clr.pressed.connect(func():
		s.failures = {}
		en.button_pressed = false
		for id in _rows:
			_rows[id][0].select(0)
			_style(id)
		changed.emit())
	right.add_child(clr)


func _num(parent: Control, label: String, lo: float, hi: float, step: float, d: Dictionary, key: String) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = SIZE_EXPAND_FILL
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
