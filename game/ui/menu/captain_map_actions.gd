class_name CaptainMapActions
extends RefCounted
## What the buttons of the Captain Pack map do (ui/menu/captain_map_panel.gd calls these): Choose action (the picker), assign, Clear,
## Invert, Bind (press the control) and Reset to the profile. Every change goes through commit(): the same saved table and the same
## save as the Controls page, which redraws its rows, so the page and the map always agree.


## Save, refresh the open Controls page and the map, and say `text`.
static func commit(p: CaptainMapPanel, text: String, warn := false) -> void:
	if p.page != null:
		p.page.call("_save")
		var rows = p.page.get("_rows")
		if rows is Dictionary:
			for a in rows:
				rows[a].refresh()
	else:
		InputBindings.save_bump(p.table, p.save_path if p.save_path != "" else CaptainDetect.bindings_path)
	p.refresh()
	p.say(text, warn)


static func open_picker(p: CaptainMapPanel) -> void:
	var c := p.current()
	if c.is_empty() or p.preview:
		return
	var pads := CaptainDetect.connected_pads()
	var sections := CaptainAssign.choices(p.controls, CaptainAssign.kind_of(c.e), bool(c.part.get("latching", false)))
	var where := {}
	for s in sections:
		for a in s[1]:
			var b: Dictionary = p.table[a]
			where[a] = CaptainAssign.describe_from(b, pads) if int(b.get("axis", -1)) >= 0 or int(b.get("button", -1)) >= 0 else ""
	p.picker = CaptainMapPicker.new().setup("Choose an action for %s on %s" % [c.part.label, p.aircraft_name()], sections, where, p.bind_target())
	p.picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.picker.chosen.connect(p.assign)
	p.picker.cancelled.connect(p.close_picker)
	p.stack.add_child(p.picker)
	p.main.visible = false
	p.picker.search.grab_focus.call_deferred()


static func close_picker(p: CaptainMapPanel) -> void:
	if p.picker != null:
		p.picker.queue_free()
		p.picker = null
	p.main.visible = true
	p.choose_btn.grab_focus.call_deferred()


## Binds the selected control to `action` (replacing what it did on this aircraft; says what moved) and saves.
static func assign(p: CaptainMapPanel, action: String) -> void:
	var c := p.current()
	close_picker(p)
	if c.is_empty() or p.preview:
		return
	var pads := CaptainDetect.connected_pads()
	var r := CaptainAssign.assign(p.table, p.selected[0], c.e, action, p.controls, pads)
	if not r.ok:
		p.say(r.error, true)
		return
	var text := "%s is now on %s." % [CaptainMap.action_name(action), c.part.label]
	if not r.from.is_empty():
		text += " It was on %s, which is now free." % CaptainAssign.describe_from(r.from, pads)
	if not r.cleared.is_empty():
		text += " Replaced: %s." % ", ".join(r.cleared.map(func(a): return CaptainMap.action_name(a)))
	commit(p, text, not r.from.is_empty())


static func clear_selected(p: CaptainMapPanel) -> void:
	var c := p.current()
	if c.is_empty() or p.preview:
		return
	var gone := CaptainAssign.clear(p.table, p.selected[0], c.e, p.controls, CaptainDetect.connected_pads())
	if gone.is_empty():
		p.say("Nothing is bound to it on %s." % p.aircraft_name())
	else:
		commit(p, "Cleared: %s." % ", ".join(gone.map(func(a): return CaptainMap.action_name(a))))


static func set_invert(p: CaptainMapPanel, on: bool) -> void:
	var a := p.bind_target()
	if a != "" and not p.preview:
		p.table[a].invert = on
		commit(p, "%s: on and off are %s." % [CaptainMap.action_name(a), "swapped" if on else "as the switch sends them"])


static func start_bind(p: CaptainMapPanel) -> void:
	var tgt := p.bind_target()
	if p.page == null or tgt == "":
		return
	p.waiting = true
	p.page.call("_start_capture", tgt)
	p.bind_btn.text = "Move or press the control…"
	p.bind_btn.disabled = true


## First press asks, the second loads the profile into the saved table (the Controls page's Reset: Airbus Captain Pack).
static func reset_profile(p: CaptainMapPanel) -> void:
	if not p.armed:
		p.armed = true
		p.reset_btn.text = "Press again to confirm"
		p.get_tree().create_timer(3.0).timeout.connect(func():
			if p.armed and is_instance_valid(p.reset_btn):
				p.armed = false
				p.refresh())
		return
	p.armed = false
	InputProfiles.apply_to(p.saved, InputProfiles.CAPTAIN_PACK)
	CaptainDetect.set_state(CaptainDetect.APPLIED)
	p.preview = false
	p.table = p.saved
	commit(p, "The Airbus Captain Pack profile is loaded.")
