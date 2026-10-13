class_name AtcMenu
extends RefCounted
## The full list of radio calls: only the ones that make sense in the current state (atc_state.gd),
## then "Tune COM1 to <unit>" when COM1 is on the wrong unit for the next call and radio assist is
## off (with assist on the call retunes COM1 itself), then "Say again". The panel shows a shorter,
## ordered list of it: AtcAssist.actions().

## The calls that make sense now: [{id, label, kind: call | tune | again, ...}], at most six.
static func build(c: AtcController, w: Dictionary) -> Array:
	var out := []
	var ids := AtcState.available(c.s, w)
	for id in ids:
		out.append({"id": id, "label": label(id, w, str(c.s.state)), "kind": "call"})
	var t := {} if c.assist else _tune_entry(w, ids)
	if not t.is_empty():
		out.append(t)
	if c.s.last_instr != "":
		out.append({"id": "say_again", "label": "Say again", "kind": "again"})
	return out.slice(0, 6)


## Plain-language text of a call ("Ask Ground for taxi"); `st` is the state (lined up changes "ready").
static func label(id: String, w: Dictionary, st := "") -> String:
	var d: Dictionary = AtcState.INTENTS[id]
	if str(w.get("ctl", "")) == "uncontrolled":
		return str(d.get("blind", "Blind call: " + id))
	var who := str(AtcFacilities.WORD.get(AtcFacilities.role_for(w, str(d.service)), "ATC"))
	var t := str(d.label)
	if id == "atis" and AtcFacilities.role_for(w, "atis") != "ATIS":
		t = str(d.label_info)
	elif st == "lined_up" and d.has("label_lined"):
		t = str(d.label_lined)
	return t.replace("{who}", who)


static func _tune_entry(w: Dictionary, ids: Array) -> Dictionary:
	if str(w.get("ctl", "")) != "published":
		return {}
	var order := ids.filter(func(i): return i != "atis") + ids.filter(func(i): return i == "atis")
	if order.is_empty():
		return {}
	var svc := AtcState.service_of(order[0])  # only the next call decides: tune for that one
	if AtcFacilities.handles(w, svc):
		return {}
	var f := AtcFacilities.facility_for(w, svc)
	if float(f.mhz) <= 0.0:
		return {}
	return {"id": "tune", "mhz": f.mhz, "name": f.name, "kind": "tune", "label": "Tune COM1 to %s %.3f" % [f.name, f.mhz]}
