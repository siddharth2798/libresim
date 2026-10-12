class_name AtcMenu
extends RefCounted
## The radio menu: only the calls that make sense in the current state (atc_state.gd), then
## "Tune COM1 to <unit>" when COM1 is on the wrong unit for the next call, then "Say again".

## The calls that make sense now: [{id, label, kind: call | tune | again, ...}], at most six.
static func build(c: AtcController, w: Dictionary) -> Array:
	var out := []
	var ids := AtcState.available(c.s, w)
	for id in ids:
		out.append({"id": id, "label": label(id, w), "kind": "call"})
	var t := _tune_entry(w, ids)
	if not t.is_empty():
		out.append(t)
	if c.s.last_instr != "":
		out.append({"id": "say_again", "label": "Say again", "kind": "again"})
	return out.slice(0, 6)


static func label(id: String, w: Dictionary) -> String:
	var d: Dictionary = AtcState.INTENTS[id]
	var role := AtcFacilities.role_for(w, str(d.service))
	var who: String = "Blind call" if str(w.get("ctl", "")) == "uncontrolled" else str(AtcFacilities.WORD.get(role, "ATC"))
	if id == "atis" and role == "ATIS":
		return str(d.label)
	return str(d.get("label_info", d.label) if id == "atis" else d.label).replace("{who}", who)


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
