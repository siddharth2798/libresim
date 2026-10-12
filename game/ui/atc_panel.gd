extends PanelContainer
## Radio panel: ` opens the menu, 1-6 pick a call (the menu swallows the keys, so camera views
## do not change), ` closes it. Header: COM1 active / standby and the unit COM1 is tuned to.
## Then the transcript (who said what) and a menu that lists only the calls that make sense in
## the current state, plus "Say again" and, when COM1 is on the wrong frequency, "Tune COM1 to
## <unit>". With the menu closed only the recent transmissions are shown, for a while after the
## last one (the controller also calls by itself). V toggles the ATC voice while the menu is open.
## The logic is in atc/ (atc_session.gd); this node is the screen and the keys. flight.gd sets
## ground_ops and fdm_node. Where it sits: atc/atc_layout.gd (never over the other UI).

const ACCENT := Color(0.3, 0.85, 0.75)
const WIDTH := 360.0
const RECENT := 18.0  # s the transcript stays after the last transmission

var ground_ops: GroundOps
var fdm_node: FdmNode
var session: AtcSession
var _open := false
var _head: Label
var _unit: Label
var _info: Label
var _sep: HSeparator
var _log: AtcTranscript
var _items: Array[Label] = []
var _hint: Label
var _entries: Array = []
var _quiet := 999.0  # s since the last transmission
var _asked := 999.0  # s since the pilot last made a call (a lesson shows the transcript only then)
var _serial := 0
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", Notifications.card_style(ACCENT))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	_head = _label(vb, 14, Color(0.78, 0.86, 0.92))
	_unit = _label(vb, 16, Color(0.6, 1.0, 0.7))
	_info = _label(vb, 12, Color(0.6, 0.68, 0.75))
	_log = AtcTranscript.new()
	vb.add_child(_log)
	_sep = HSeparator.new()
	vb.add_child(_sep)
	for i in 6:
		_items.append(_label(vb, 15, Color(1, 0.85, 0.4)))
	_hint = _label(vb, 12, Color(0.6, 0.68, 0.75))
	visible = false


func _exit_tree() -> void:
	if session != null:
		session.close()


func _label(parent: Control, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 28.0, 0)
	parent.add_child(l)
	return l


## Wait until flight.gd has wired the scene, then build the ATC session from its data.
func _try_init() -> void:
	if ground_ops == null or ground_ops.ops == null or ground_ops.airports == null:
		return
	var nav := get_node_or_null("../../Avionics/Nav")
	if nav == null or nav.db == null:
		return
	var rw: Array = []
	if ground_ops.airports.data != null:
		rw = ground_ops.airports.data.runways
	session = AtcSession.new()
	session.setup(AtcWorld.make_env(nav.db.airports, nav.db.coms, rw, ground_ops.ops.data), AtcWorld.make_hooks(ground_ops))


func _process(dt: float) -> void:
	if session == null:
		_try_init()
		return
	session.tick(dt)
	_quiet += dt
	_asked += dt
	_t += dt
	var c := session.c
	if c.tx_serial != _serial:  # something was said
		_serial = c.tx_serial
		_quiet = 0.0
		_refresh()
	elif _t > 0.5:
		_t = 0.0
		if visible:
			_refresh()
	var want := _open or _recent()
	if want != visible:
		visible = want
		if want:
			_refresh()


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo or session == null:
		return
	if e.keycode == KEY_QUOTELEFT:
		_open = not _open
		visible = _open or _recent()
		_refresh()
		get_viewport().set_input_as_handled()
	elif _open and e.keycode >= KEY_1 and e.keycode <= KEY_6:
		var i: int = e.keycode - KEY_1
		if i < _entries.size():
			session.pick(_entries[i])
		_open = false
		_quiet = 0.0
		_asked = 0.0
		visible = true
		_refresh()
		get_viewport().set_input_as_handled()
	elif _open and e.keycode == KEY_V and not e.shift_pressed and not e.ctrl_pressed:
		UserOptions.set_v("atc_voice", not AtcVoice.enabled())
		if AtcVoice.enabled():
			SpeechService.request()  # starts the one-time probe; the hint says if there is no voice
		_refresh()
		get_viewport().set_input_as_handled()


## Show the transcript for a while after a transmission. In a training lesson ATC never pops up by
## itself: only after the pilot has made a call.
func _recent() -> bool:
	return _quiet < RECENT and (not AtcSession.in_lesson() or _asked < RECENT)


func _refresh() -> void:
	if session == null:
		return
	var c := session.c
	_log.show_log(c.log, 8 if _open else 4)
	_log.custom_minimum_size = Vector2(WIDTH - 28.0, 170.0 if _open else 96.0)
	for n in [_head, _unit, _info, _sep, _hint]:
		n.visible = _open
	if _open:
		var w := session.w
		var t := AtcFacilities.tuned(w)
		_head.text = "COM1  %.3f   standby %.3f" % [Props.get_f("controls/com1/freq_mhz", 118.1), Props.get_f("controls/com1/standby_mhz", 121.9)]
		var dead := not bool(w.get("com1_ok", true))
		_unit.text = ("COM1 is off (no power)" if str(w.get("com1_why", "")) == "unpowered" else "COM1 has failed") if dead else str(t.label)
		_unit.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if dead else (Color(0.6, 1.0, 0.7) if t.role != "" else Color(1, 0.8, 0.4)))
		_info.text = "%s  ·  squawk %s  ·  %s  ·  information %s" % [c.s.callsign, c.s.squawk, str(c.s.state).replace("_", " "), c.info_word()]
		_entries = session.menu()
		for i in _items.size():
			_items[i].visible = i < _entries.size()
			if i < _entries.size():
				_items[i].text = "%d  %s" % [i + 1, _entries[i].label]
				_items[i].add_theme_color_override("font_color", Color(0.6, 0.9, 1.0) if _entries[i].kind != "call" else Color(1, 0.85, 0.4))
		var calls_text := "" if not _entries.is_empty() else "No call fits right now.   "
		_hint.text = "%s`  close     V  voice %s%s" % [calls_text, "on" if AtcVoice.enabled() else "off",
			" (no system voice)" if session.voice.missing() else ""]
	else:
		for it in _items:
			it.visible = false
	reset_size()
	call_deferred("_place")


func _place() -> void:
	position = AtcLayout.place(get_combined_minimum_size(), get_viewport_rect().size, _busy())


## Rects of the other UI that is on screen now (see atc/atc_layout.gd).
func _busy() -> Array:
	var out: Array = AtcLayout.reserved(get_viewport_rect().size)
	var ui := get_parent()
	var overlay := ui.get_node_or_null("Panel")
	if overlay != null and overlay.visible and overlay.get("_pieces") != null:
		for p in overlay._pieces:
			if p[0].visible:
				out.append(Rect2(p[0].global_position, p[0].size))
	for n in ["Checklist", "Map"]:
		var node := ui.get_node_or_null(n) as Control
		if node != null and node.visible:
			out.append(node.get_global_rect())
	for ch in ui.get_children():
		var scr: Script = ch.get_script()
		if scr != null and str(scr.get_global_name()) == "TrainingHud" and ch.visible:
			var card: Control = ch.get("_card")
			if card != null and card.visible:
				out.append(card.get_global_rect())
	return out
