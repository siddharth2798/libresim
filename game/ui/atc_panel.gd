extends Control
## The radio (see docs/ATC.md): a slim bar at the top-left in free flight (COM1 frequency and unit,
## the suggested next call, the latest controller message); ` or a click opens a short list of calls
## (the suggested one first): Up/Down or 1-4 choose, Enter calls, Esc or ` closes, A says again,
## H shows the history, V toggles the voice. A call closes the list. Incoming messages are a calm
## card in the notification stack (ui/atc_card.gd). In a training lesson the bar stays hidden: only
## ` opens it. While it is open the arrow keys do not pitch the aircraft (Props ui/radio_open).
## This node is the keys and the wiring; the logic is in atc/ (atc_session.gd, atc_assist.gd,
## atc_card_logic.gd) and the drawing in atc_box.gd. flight.gd sets ground_ops and fdm_node.
## Where it sits: atc/atc_layout.gd (never over the other UI).

var ground_ops: GroundOps
var fdm_node: FdmNode
var session: AtcSession
var menu: Control  # the part that shows while the radio is open (the e2e panels check reads it)
var _box: AtcBox
var _cards := AtcCardLogic.new()
var _card: AtcCard
var _open := false
var _history := false
var _sel := 0
var _actions: Array = []
var _serial := 0
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_box = AtcBox.new()
	add_child(_box)
	menu = _box.menu
	_box.open_requested.connect(func(): _set_open(true))
	_box.picked.connect(_perform)
	_box.hovered.connect(func(i: int):
		if i != _sel:
			_sel = i
			_refresh())
	_box.history_toggled.connect(_toggle_history)
	_box.again_requested.connect(_say_again)
	_box.voice_toggled.connect(_toggle_voice)


func _exit_tree() -> void:
	Props.set_v("ui/radio_open", false)
	if session != null:
		session.close()


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
	if Props.get_b("replay/active"):
		_box.visible = false
		return
	session.tick(dt)
	_cards.tick(dt)
	if session.c.tx_serial != _serial:
		_heard(session.c)
	_t += dt
	if _t > 0.25:
		_t = 0.0
		_refresh()


## New transmissions: the message card (ui/atc_card.gd) and the bar.
func _heard(c: AtcController) -> void:
	var n := c.tx_serial - _serial
	_serial = c.tx_serial
	for e in c.log.slice(maxi(c.log.size() - n, 0)):
		_show_card(_cards.feed(e))
	_refresh()


func _show_card(started: bool) -> void:
	var notes := get_tree().get_first_node_in_group("notifications") as Notifications
	if notes == null:
		return
	if started or _card == null or not is_instance_valid(_card) or _card.is_queued_for_deletion():
		_card = AtcCard.new()
		notes.adopt(_card, _cards.left, "atc")
	else:
		notes.touch("atc", _cards.left)
	_card.show_lines(_cards.lines)


# ---- keys and clicks ----

## ` opens the radio (while it is open the keys are taken in _input).
func _unhandled_key_input(e: InputEvent) -> void:
	if session != null and not _open and e.pressed and not e.echo and e.keycode == KEY_QUOTELEFT:
		_set_open(true)
		get_viewport().set_input_as_handled()


## The open radio takes its keys before the rest of the game (Esc would open the pause menu, H
## toggles the flight-data bar, V re-centres the view, 1-4 change the camera).
func _input(e: InputEvent) -> void:
	if not _open or session == null or not (e is InputEventKey) or not e.pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var plain: bool = not (e.ctrl_pressed or e.alt_pressed or e.shift_pressed or e.meta_pressed)
	var key: int = e.keycode
	var handled := true
	if key == KEY_UP or key == KEY_DOWN:
		_move(-1 if key == KEY_UP else 1)  # also while a key is held
	elif e.echo:
		handled = key in [KEY_ESCAPE, KEY_QUOTELEFT, KEY_ENTER, KEY_H, KEY_V, KEY_A, KEY_1, KEY_2, KEY_3, KEY_4]
	elif key == KEY_ESCAPE or key == KEY_QUOTELEFT:
		_set_open(false)
	elif not plain:
		handled = false
	elif key == KEY_ENTER:
		if not _history:
			_perform(_sel)
	elif key >= KEY_1 and key <= KEY_4:
		if not _history:
			_perform(key - KEY_1)
	elif key == KEY_H:
		_toggle_history()
	elif key == KEY_V:
		_toggle_voice()
	elif key == KEY_A:
		_say_again()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _set_open(on: bool) -> void:
	_open = on
	_history = false
	_sel = 0
	Props.set_v("ui/radio_open", on)
	_refresh()


func _move(d: int) -> void:
	if _history:
		_box.history_view().scroll_lines(d * 3)
	elif not _actions.is_empty():
		_sel = posmod(_sel + d, _actions.size())
		_refresh()


## Make the call with this number in the list; the list closes.
func _perform(i: int) -> void:
	if session == null or i < 0 or i >= _actions.size():
		return
	session.pick(_actions[i])
	_set_open(false)


func _say_again() -> void:
	if session != null and session.c.s.last_instr != "":
		session.pick({"id": "say_again"})
		_set_open(false)


func _toggle_history() -> void:
	_history = not _history
	_refresh()


func _toggle_voice() -> void:
	UserOptions.set_v("atc_voice", not AtcVoice.enabled())
	if AtcVoice.enabled():
		SpeechService.request()  # starts the one-time probe; the button says if there is no voice
	_refresh()


# ---- drawing ----

## The bar shows in free flight (a lesson keeps it hidden until ` opens it, and ATC never speaks
## by itself there); never over the crash card or a replay.
func _refresh() -> void:
	if session == null:
		return
	if not (_open or not AtcSession.in_lesson()) or Props.get_b("damage/crashed") or Props.get_b("replay/active"):
		_box.visible = false
		return
	var c := session.c
	_actions = session.actions() if _open else []
	_sel = clampi(_sel, 0, maxi(_actions.size() - 1, 0))
	_box.show_model(_model(c, session.w))
	_box.reset_size()
	call_deferred("_place")


func _model(c: AtcController, w: Dictionary) -> Dictionary:
	var sm := AtcFacilities.summary(w)
	var labels: Array = _actions.map(func(a): return str(a.label))
	var hint := c.next_hint(w)
	if _open and _actions.is_empty() and hint == "":
		hint = "Nothing to call right now"
	var voice := "Voice on" if AtcVoice.enabled() else "Voice off"
	if session.voice.missing():
		voice = "Voice: none found"
	return {"width": AtcLayout.bar_width(get_viewport_rect().size), "open": _open, "history": _history,
		"freq": "%.3f" % float(w.get("com1_mhz", 118.1)), "unit": str(sm.text), "tone": str(sm.tone),
		"hint": hint, "msg": _cards.bar_line(), "actions": labels, "sel": _sel,
		"note": AtcAssist.tune_note(c, w, _actions[_sel]) if _open and not _actions.is_empty() else "",
		"log": c.log, "can_again": c.s.last_instr != "" and bool(w.get("com1_ok", true)), "voice": voice,
		"keys": "H  back to calls     ↑ ↓  scroll     Esc  close" if _history
			else "↑ ↓  choose     Enter or 1-4  call     Esc  close"}


func _place() -> void:
	var vp := get_viewport_rect().size
	var home := AtcLayout.home(vp)
	_box.size = _box.get_combined_minimum_size()
	_box.position = AtcLayout.place(_box.size, vp, _busy(), home) if _open else home


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
