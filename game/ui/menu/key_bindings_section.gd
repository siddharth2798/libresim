extends VBoxContainer
## Controls page, keyboard part: one row per flight-control action with up to three
## key slots. Click a slot, then press a key (with Shift / Ctrl / Alt if wanted);
## Esc cancels, Delete / Backspace empties the slot. ✕ clears the row. Conflicts
## (same key on two actions, or on another hotkey) are listed in orange.
## Saves to user://key_bindings.json and bumps Props input/bindings_rev.

signal changed

const SLOT_W := 112.0
const WARN := Color(1.0, 0.7, 0.3)
const MODS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var path := KeyBindings.PATH
var table := {}
var _slots := {}  # action -> Array[Button]
var _warn: Label
var _hint: Label
var _cap_action := ""
var _cap_slot := -1


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	table = KeyBindings.load_from(path)
	var head := HBoxContainer.new()
	add_child(head)
	var h := MenuTheme.heading("Keyboard")
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(h)
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(_reset)
	head.add_child(reset)
	_hint = MenuTheme.note("Click a key slot, then press the new key (modifiers allowed). Esc cancels, Delete empties the slot.")
	add_child(_hint)
	_warn = Label.new()
	_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warn.add_theme_color_override("font_color", WARN)
	_warn.add_theme_font_size_override("font_size", 14)
	add_child(_warn)
	for a in KeyBindings.HELD + KeyBindings.PRESS:
		_add_row(a)
	_refresh()


func _add_row(a: String) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	add_child(r)
	var n := Label.new()
	n.text = KeyBindings.LABELS[a]
	n.custom_minimum_size = Vector2(220, 0)
	r.add_child(n)
	var l := []
	for i in KeyBindings.SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(SLOT_W, 0)
		b.clip_text = true
		b.pressed.connect(_start.bind(a, i))
		r.add_child(b)
		l.append(b)
	_slots[a] = l
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = "Clear all keys for this action"
	x.custom_minimum_size = Vector2(34, 0)
	x.pressed.connect(func():
		table[a] = []
		_save())
	r.add_child(x)


func _refresh() -> void:
	var bad := {}
	for a in table:
		for s in table[a]:
			for b in table:
				if b != a and table[b].any(func(o): return KeyBindings.same(s, o)):
					bad[KeyBindings.describe(s)] = true
			if not s.shift and not s.ctrl and not s.alt and KeyBindings.RESERVED.has(int(s.key)):
				bad[KeyBindings.describe(s)] = true
	for a in _slots:
		var keys: Array = table[a]
		for i in KeyBindings.SLOTS:
			var b: Button = _slots[a][i]
			var waiting: bool = a == _cap_action and i == _cap_slot
			b.text = "press…" if waiting else (KeyBindings.describe(keys[i]) if i < keys.size() else "")
			var c := MenuTheme.TEXT
			if i < keys.size() and bad.has(b.text):
				c = WARN
			b.add_theme_color_override("font_color", c)
			b.add_theme_color_override("font_hover_color", c)
	var cf := KeyBindings.conflicts(table)
	_warn.text = "" if cf.is_empty() else "Conflicts:\n• " + "\n• ".join(cf)
	_warn.visible = not cf.is_empty()


func _start(a: String, slot: int) -> void:
	_cap_action = a
	_cap_slot = mini(slot, table[a].size())  # fill the first empty slot, not a gap
	_hint.text = "%s: press a key…  (Esc cancels, Delete empties the slot)" % KeyBindings.LABELS[a]
	_refresh()


func _input(e: InputEvent) -> void:
	if _cap_action == "" or not e is InputEventKey or not e.pressed or e.echo:
		return
	var k: InputEventKey = e
	if k.keycode in MODS:
		return  # wait for the real key
	get_viewport().set_input_as_handled()
	var keys: Array = table[_cap_action]
	if k.keycode == KEY_ESCAPE:
		_hint.text = "Cancelled."
	elif k.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		if _cap_slot < keys.size():
			keys.remove_at(_cap_slot)
		_hint.text = "Slot emptied."
	else:
		var s := KeyBindings.from_event(k)
		if _cap_slot < keys.size():
			keys[_cap_slot] = s
		else:
			keys.append(s)
		_hint.text = "%s -> %s" % [KeyBindings.LABELS[_cap_action], KeyBindings.describe(s)]
	_cap_action = ""
	_cap_slot = -1
	_save()


func _reset() -> void:
	table = KeyBindings.defaults()
	_cap_action = ""
	_hint.text = "Keys reset to defaults."
	_save()


func _save() -> void:
	KeyBindings.save_to(table, path)
	Props.set_v("input/bindings_rev", int(Props.get_v("input/bindings_rev", 0)) + 1)
	_refresh()
	changed.emit()
