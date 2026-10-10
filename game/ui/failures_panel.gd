extends PanelContainer
## F9: in-flight failures. Every system's state (OK / FAILED / armed trigger), with
## Fail / Repair buttons, how many random failures are still pending (not which), and
## "Repair all". Also shows a short on-screen notice when a failure trips (if the
## flight setup has notifications on).

var manager: FailureManager
var _rows := {}  # id -> [status Label, Button]
var _footer: Label
var _toast: Label
var _acc := 0.0


func _ready() -> void:
	visible = false
	set_anchors_preset(PRESET_CENTER)
	custom_minimum_size = Vector2(760, 0)
	var vb := VBoxContainer.new()
	add_child(vb)
	var title := Label.new()
	title.text = "Failures  (F9 to close)"
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	vb.add_child(cols)
	var halves := [VBoxContainer.new(), VBoxContainer.new()]
	for h in halves:
		cols.add_child(h)
	var n := 0
	for c in FailureCatalog.CATEGORIES:
		var col: VBoxContainer = halves[0 if n < 4 else 1]
		n += 1
		var cl := Label.new()
		cl.text = c[0]
		cl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		col.add_child(cl)
		var g := GridContainer.new()
		g.columns = 3
		col.add_child(g)
		for f in c[1]:
			var l := Label.new()
			l.text = f[1]
			l.custom_minimum_size = Vector2(220, 0)
			g.add_child(l)
			var st := Label.new()
			st.custom_minimum_size = Vector2(70, 0)
			g.add_child(st)
			var b := Button.new()
			b.custom_minimum_size = Vector2(70, 0)
			b.pressed.connect(func(): _toggle(f[0]))
			g.add_child(b)
			_rows[f[0]] = [st, b]
	vb.add_child(HSeparator.new())
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	_footer = Label.new()
	_footer.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(_footer)
	var rep := Button.new()
	rep.text = "Repair all"
	rep.pressed.connect(func(): FailureCatalog.clear_all())
	hb.add_child(rep)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 24)
	_toast.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2))
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.set_anchors_preset(PRESET_CENTER_TOP)
	_toast.position = Vector2(-200, 80)
	_toast.mouse_filter = MOUSE_FILTER_IGNORE
	add_sibling.call_deferred(_toast)


func _toggle(id: String) -> void:
	if Props.get_b("failures/" + id):
		manager.repair(id)
	else:
		manager.fail_now(id)


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_F9:
		visible = not visible
		_refresh()


func _process(dt: float) -> void:
	var t := int(Props.get_v("failures/event_t", -100000))
	var ev: String = str(Props.get_v("failures/event", ""))
	_toast.text = ev if ev != "" and Time.get_ticks_msec() - t < 8000 else ""
	_acc += dt
	if visible and _acc > 0.25:
		_acc = 0.0
		_refresh()


func _refresh() -> void:
	if manager == null:
		return
	var pending := {}
	for a in manager.armed:
		if not a.random:
			pending[a.id] = "%s %.0f %s" % [FailureCatalog.MODES[a.mode].to_lower(), a.value, FailureCatalog.MODE_UNITS[a.mode]]
	for id in _rows:
		var failed := Props.get_b("failures/" + id)
		var st: Label = _rows[id][0]
		st.text = "FAILED" if failed else ("armed" if pending.has(id) else "OK")
		st.tooltip_text = pending.get(id, "")
		st.add_theme_color_override("font_color", Color(1, 0.3, 0.2) if failed else (Color(1, 0.8, 0.3) if pending.has(id) else Color(0.5, 0.9, 0.5)))
		(_rows[id][1] as Button).text = "Repair" if failed else "Fail"
	var m := int(manager.elapsed / 60.0)
	_footer.text = "Flight time %d:%02d   ·   random failures pending: %d" % [m / 60, m % 60, manager.random_pending()]
