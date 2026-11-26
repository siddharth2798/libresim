class_name CaptainMapText
extends RefCounted
## The words of the Captain Pack map (ui/menu/captain_map_panel.gd): the connection chip, the note under the title, and the detail strip of
## the selected control. Pure functions of plain data, so tests can read them without any widget.


## {"text", "good"}: "Pack connected" / "No pack connected" / "Only the sidestick found". `have` / `miss` = device names.
static func status(have: Array, miss: Array) -> Dictionary:
	if miss.is_empty():
		return {"text": "●  Pack connected", "good": true}
	if have.is_empty():
		return {"text": "○  No pack connected", "good": false}
	return {"text": "●  Only the %s found" % have[0], "good": false}


static func note(preview: bool, profile_loaded: bool, aircraft_name: String, unconfirmed: int) -> String:
	var unsure := "" if unconfirmed == 0 else " %d controls are marked ? (number not confirmed): turn Identify on and press them." % unconfirmed
	if preview:
		return "No pack is connected, so this is the default mapping of the Captain Pack profile (for %s). Plug the pack in (switch on the back of the sidestick on PC) and the numbers light up live. Use Reset to load the profile and then assign freely.%s" % [aircraft_name, unsure]
	if not profile_loaded:
		return "The Captain Pack profile is not loaded, so most controls show unbound. Use Reset below, or Choose action for each control. Shown for %s.%s" % [aircraft_name, unsure]
	return "What each control does for your saved bindings, for %s.%s" % [aircraft_name, unsure]


## "axis 0" / "button 5" / "buttons 8, 9" / "number not known yet" of pad numbers {"axis", "button"}.
static func numbers(e: Dictionary) -> String:
	var out: PackedStringArray = []
	if int(e.get("axis", -1)) >= 0:
		out.append("axis %d" % e.axis)
	if int(e.get("button", -1)) >= 0:
		out.append("button %d" % e.button)
	return ", ".join(out) if not out.is_empty() else "number not known yet"


static func confidence_line(conf: String, src_text: String) -> String:
	match conf:
		"measured":
			return "Number measured on the pack."
		"documented":
			return "Number from a public list, not yet seen on this pack. %s" % src_text
	return "UNCONFIRMED number. %s Turn Identify on and press it to settle this." % src_text


## The detail strip. `parts` = how many parts the marker has; `acts` = CaptainMap.part_actions of the selected part.
static func detail(m: Dictionary, p: Dictionary, e: Dictionary, acts: Dictionary, aircraft_name: String, raw: String, conf: String, src_text: String) -> String:
	var parts: Array = m.get("parts", [])
	var title := str(m.get("label", m.id)) if parts.size() < 2 else "%s: %s" % [m.get("label", m.id), p.get("label", "")]
	var line1 := "%s  (%s%s)" % [title, numbers(e), "   raw %s" % raw if raw != "" else ""]
	var names: PackedStringArray = []
	for a in acts.now:
		names.append(CaptainMap.action_name(a))
	var line2 := "On %s: %s." % [aircraft_name, ", ".join(names) if not names.is_empty() else ("not used (bound for another aircraft)" if not acts.other.is_empty() else "nothing, unbound")]
	var hint := CaptainMap.test_hint(m)
	return "%s\n%s\n%s%s" % [line1, line2, confidence_line(conf, src_text), "\nTo test: " + hint if hint != "" else ""]
