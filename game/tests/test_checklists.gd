extends Node
## The aircraft checklists (aircraft/<id>/checklists.json, ui/checklist_panel.gd): conditions with "all" / "any", the A320
## flap steps read the flap setting (0, 1, 1+F, 2, 3, FULL = 0..5), and every switch a step checks can be worked from that
## aircraft's Controls page (or a click in its cockpit, which the same audit covers).

var _saved := {}


func teardown() -> void:
	for p in _saved:
		if _saved[p] == null:
			Props._p.erase(p)
		else:
			Props.set_v(p, _saved[p])
	_saved.clear()


func _put(p: String, v: Variant) -> void:
	if not _saved.has(p):
		_saved[p] = Props.get_v(p, null)
	Props.set_v(p, v)


func _lists(id: String) -> Array:
	return AircraftDef.load_def(id).json("checklists").lists


func _item(id: String, list: String, starts: String) -> Dictionary:
	for l in _lists(id):
		if l.name == list:
			for it in l.items:
				if str(it.text).begins_with(starts):
					return it
	return {}


static func _conds(item: Dictionary) -> Array:
	if item.has("all"):
		return item.all
	if item.has("any"):
		return item.any
	return [item] if item.has("prop") else []


func test_all_and_any_conditions() -> String:
	var both := {"all": [{"prop": "test/ck_a", "eq": true}, {"prop": "test/ck_b", "range": [1, 2]}]}
	var either := {"any": [{"prop": "test/ck_a", "eq": true}, {"prop": "test/ck_b", "range": [1, 2]}]}
	_put("test/ck_a", true)
	_put("test/ck_b", 5)
	if ChecklistPanel._met(both) or not ChecklistPanel._met(either):
		return "all needs every condition, any needs one"
	_put("test/ck_b", 1.5)
	if not ChecklistPanel._met(both):
		return "all should tick once every condition holds"
	_put("test/ck_a", false)
	_put("test/ck_b", 0)
	if ChecklistPanel._met(either) or ChecklistPanel._met({"all": []}):
		return "any with nothing true, or an empty all, must stay open"
	return ""


func test_a320_flap_steps_use_the_flap_setting() -> String:
	var to := _item("a320", "Before Takeoff", "Flaps")
	var ldg := _item("a320", "Landing", "Flaps")
	if to.is_empty() or ldg.is_empty():
		return "missing a flap step"
	for s in [[1, false, false], [2, true, false], [3, true, false], [4, true, true], [5, false, true]]:
		_put("fdm/flap_lever", s[0])
		if ChecklistPanel._met(to) != s[1]:
			return "takeoff flaps at setting %d (%s) should be %s" % [s[0], DispMath.conf_text(s[0], 0.0), s[1]]
		if ChecklistPanel._met(ldg) != s[2]:
			return "landing flaps at setting %d (%s) should be %s" % [s[0], DispMath.conf_text(s[0], 0.0), s[2]]
	return ""


func test_every_checked_switch_is_operable_on_that_aircraft() -> String:
	var audit: GDScript = load("res://tests/test_cockpit_controls_audit.gd")
	for id in ["c172", "a320"]:
		var page: Dictionary = audit._page_props(AircraftControls.for_def(AircraftDef.load_def(id)))
		for l in _lists(id):
			if l.items.is_empty():
				return "%s list %s is empty" % [id, l.name]
			for it in l.items:
				if str(it.get("text", "")) == "":
					return "%s %s has a step with no text" % [id, l.name]
				for c in _conds(it):
					if not (c.has("eq") or (c.has("range") and c.range.size() == 2 and c.range[0] <= c.range[1])):
						return "%s step '%s' has a condition with no eq or range" % [id, it.text]
					var p := str(c.prop)
					if p.begins_with("controls/") and not page.has(p):
						return "%s step '%s' checks %s, which nothing on its Controls page sets" % [id, it.text, p]
	return ""


func test_a320_overhead_switches_appear_in_the_checklists() -> String:
	var seen := {}
	for l in _lists("a320"):
		for it in l.items:
			for c in _conds(it):
				seen[str(c.prop)] = true
	for p in ["controls/electrical/bat1", "controls/electrical/bat2", "controls/electrical/gen1", "controls/electrical/gen2",
			"controls/electrical/apu_gen", "controls/electrical/ext_pwr", "controls/hyd/green_edp", "controls/hyd/yellow_edp",
			"controls/hyd/blue_epump", "controls/hyd/yellow_epump", "controls/hyd/ptu", "controls/fuel/pump_left",
			"controls/fuel/pump_centre", "controls/fuel/pump_right", "controls/fuel/crossfeed", "controls/bleed/eng1",
			"controls/bleed/eng2", "controls/bleed/apu", "controls/bleed/pack1", "controls/bleed/pack2",
			"controls/signs/seatbelts", "controls/signs/no_smoking", "controls/apu_master", "controls/engine_mode",
			"controls/lights/takeoff", "controls/lights/rwy_turnoff", "controls/lights/logo"]:
		if not seen.has(p):
			return "no A320 checklist step checks %s" % p
	return ""
