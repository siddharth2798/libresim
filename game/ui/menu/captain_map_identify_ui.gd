class_name CaptainMapIdentifyUi
extends RefCounted
## Identify mode of the Captain Pack map, the widget side (the pad logic is core/captain_identify.gd): an event selects the matching
## marker and part; a number the map does not know (or a wrong one) gets a "This is:" list and Save, which teaches the number
## (CaptainMap.learn, user://captain_map_learned.json).


static func set_on(p: CaptainMapPanel, on: bool) -> void:
	p.identifying = on
	p.ident_row.visible = false
	if on:
		p.ident.start(p.devices(), p.read_axis, p.read_button)
		p.say("Identify is on: press a button or move an axis on the pack.")
	else:
		p.say("Identify is off.")


static func event(p: CaptainMapPanel, ev: Dictionary) -> void:
	var found := CaptainMap.find_part(ev.device, ev.kind, ev.idx)
	var what := "%s %s %d" % [str(ev.device).capitalize(), ev.kind, ev.idx]
	var why := CaptainIdentify.unmapped_reason(ev.device, ev.kind, ev.idx)
	if found.is_empty() and why != "":
		p.say("%s: %s." % [what, why])
		return
	p.ident_event = ev
	p.ident_parts.clear()
	p.ident_pick.clear()
	for pass_unsure in [true, false]:  # the controls whose number is not confirmed come first
		for m in CaptainMap.markers(ev.device):
			for part in m.parts:
				if CaptainMap.part_kind(m, part) != ev.kind or (CaptainMap.part_conf(ev.device, m, part) == "unconfirmed") != pass_unsure:
					continue
				var n: int = p.ident_pick.item_count
				p.ident_pick.add_item(str(part.label) if m.parts.size() == 1 else "%s: %s" % [m.label, part.label])
				p.ident_parts.append([ev.device, m, part])
				if not found.is_empty() and found.part == part:
					p.ident_pick.select(n)
	if found.is_empty():
		p.ident_label.text = "%s: not on the map yet. This is:" % what
		p.say("Pick the control you pressed and Save: libresim remembers it from now on.", true)
	else:
		p.select(ev.device, found.marker.id, found.part.id)
		p.ident_label.text = "%s is %s. Wrong? This is:" % [what, found.part.label]
		p.say("%s found." % what)
	p.ident_row.visible = p.ident_pick.item_count > 0


static func save(p: CaptainMapPanel) -> void:
	var i: int = p.ident_pick.selected
	if i < 0 or i >= p.ident_parts.size() or p.ident_event.is_empty():
		return
	var d: Array = p.ident_parts[i]
	var ok := CaptainMap.learn(d[0], CaptainMap.uid(d[1], d[2]), p.ident_event.kind, p.ident_event.idx)
	p.ident_row.visible = false
	p.refresh()
	p.select(d[0], d[1].id, d[2].id)
	p.say("Saved: %s is %s %d.%s" % [d[2].label, p.ident_event.kind, p.ident_event.idx, "" if ok else " (the file could not be written)"], not ok)
