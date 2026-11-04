extends Node
## Stand names worked out at run time (world/stand_names.gd): the real OSM ref, else a made-up stable "Gate n" /
## "Bay n" numbered in position order and skipping real refs, the nearest terminal as a hint, natural order, and the
## real airport_ops.json (when data/processed exists): Mumbai VABB 27 of 114 stands and Pune VAPO 12 of 24 have no ref.


func _st(ref: String, x: float, y := 0.0, jetbridge := false, kind := "remote") -> Dictionary:
	return {"ref": ref, "x": x, "y": y, "heading_deg": 90.0, "kind": kind, "jetbridge": jetbridge}


func _fixture() -> Array:
	return [_st("Bay 1", 0.0), _st("", 10.0), _st("Bay 3", 20.0), _st("", 5.0), _st("", 30.0),
		_st("", 8.0, 0.0, true, "gate"), _st("", 2.0, 0.0, true, "gate"), _st("7", 40.0, 0.0, true, "gate")]


func test_stand_names_real_ref_kept_and_made_up_skip_used_numbers() -> String:
	var n := StandNames.assign(_fixture())
	# unnamed bays by easting: 5 -> Bay 2 (Bay 1 is real), 10 -> Bay 4 (Bay 3 is real), 30 -> Bay 5; unnamed gates: 2 -> Gate 1, 8 -> Gate 2
	var want := ["Bay 1", "Bay 4", "Bay 3", "Bay 2", "Bay 5", "Gate 2", "Gate 1", "7"]
	return "" if n == want else "names %s, want %s" % [n, want]


func test_stand_names_gate_for_a_jetbridge_or_gate_kind_bay_for_the_rest() -> String:
	var s := [_st("", 0.0, 0.0, true, "gate"), _st("", 1.0, 0.0, false, "gate"), _st("", 2.0, 0.0, false, "remote"), _st("", 3.0, 0.0, false, "ga")]
	var n := StandNames.assign(s)
	if n != ["Gate 1", "Gate 2", "Bay 1", "Bay 2"]:
		return "kinds: %s" % [n]
	var d := StandNames.describe(s)
	return "" if [d[0].kind, d[2].kind, d[0].made] == ["gate", "bay", true] else "describe: %s" % [d]


func test_stand_names_are_deterministic_and_follow_position_not_data_order() -> String:
	var a := _fixture()
	var b := a.duplicate()
	b.reverse()
	var na := StandNames.assign(a)
	var nb := StandNames.assign(b)
	nb.reverse()
	if na != StandNames.assign(a):
		return "two runs differ"
	if na != nb:
		return "the data order changed the names: %s vs %s" % [na, nb]
	# identical positions: the data order breaks the tie, the same way each time
	var tie := [_st("", 5.0, 5.0), _st("", 5.0, 5.0), _st("", 5.0, 5.0)]
	return "" if StandNames.assign(tie) == ["Bay 1", "Bay 2", "Bay 3"] and StandNames.assign(tie) == StandNames.assign(tie) else "tie: %s" % [StandNames.assign(tie)]


func test_stand_names_repeated_real_refs_stay_unique() -> String:
	var n := StandNames.assign([_st("Bay 12", 0.0), _st("Bay 12", 5.0), _st("bay12", 9.0), _st("", 1.0)])
	if n[0] != "Bay 12" or n[1] != "Bay 12 (2)" or n[2] != "bay12 (3)":
		return "repeated refs: %s" % [n]
	if StandNames.find_index([_st("Bay 12", 0.0), _st("Bay 12", 5.0)], "bay 12 (2)") != 1:
		return "a repeated ref's second stand must be reachable by its name"
	return ""


func test_stand_names_nearest_terminal_is_a_hint() -> String:
	var terms := [{"name": "Terminal 1", "x": 0.0, "y": 0.0}, {"name": "Terminal 2", "x": 1000.0, "y": 0.0}]
	var d := StandNames.describe([_st("", 100.0), _st("", 900.0), _st("", 9000.0)], terms)
	if d[0].hint != "near Terminal 1" or d[1].hint != "near Terminal 2":
		return "hints: %s / %s" % [d[0].hint, d[1].hint]
	if d[2].hint != "":
		return "no hint beyond %d m: '%s'" % [int(StandNames.TERMINAL_RADIUS_M), d[2].hint]
	return "" if StandNames.describe([_st("", 1.0)])[0].hint == "" else "no terminals: no hint"


func test_stand_names_natural_order() -> String:
	var names := ["Bay 10", "Bay 2", "Bay A1", "Bay 1", "Gate 3", "12", "2", "Bay 2A", "bay 3"]
	names.sort_custom(StandNames.natural_less)
	var want := ["2", "12", "Bay 1", "Bay 2", "Bay 2A", "bay 3", "Bay 10", "Bay A1", "Gate 3"]
	if names != want:
		return "natural order %s" % [names]
	return "" if StandNames.natural_less("Bay 2", "Bay 10") and not StandNames.natural_less("Bay 10", "Bay 2") and not StandNames.natural_less("Bay 2", "bay 2") else "pairwise"


func test_stand_names_offered_order_by_class_then_natural() -> String:
	var s := [_st("", 0.0, 0.0, true, "gate"), _st("Bay 10", 1.0), _st("Bay 2", 2.0), _st("GA3", 3.0), _st("", 4.0, 0.0, true, "gate")]
	var names := StandNames.assign(s)
	var ord := func(cls: String) -> Array:
		return StandNames.offered_indices(s, names, cls).map(func(i): return names[i])
	var any: Array = ord.call("any")
	var gate: Array = ord.call("gate")
	var ga: Array = ord.call("ga")
	if any != ["Bay 2", "Bay 10", "GA3", "Gate 1", "Gate 2"]:
		return "any: bays then gates, natural: %s" % [any]
	if gate != ["Gate 1", "Gate 2", "Bay 2", "Bay 10"]:
		return "an airliner is offered gates, then remote bays, no GA tie-down: %s" % [gate]
	return "" if ga == ["GA3", "Bay 2", "Bay 10"] else "ga: %s" % [ga]


func test_stand_names_find_stand_resolves_made_up_names() -> String:
	var ops := AirportOps.new()
	ops.data = {"XX": {"stands": _fixture()}}
	var by_real: Dictionary = ops.find_stand("XX", "Bay 3", "any")
	var made: Dictionary = ops.find_stand("XX", "gate 2", "any")
	var bay: Dictionary = ops.find_stand("XX", "Bay2", "any")
	ops.free()
	if by_real.x != 20.0 or made.x != 8.0 or bay.x != 5.0:
		return "find_stand by made-up name: Bay 3 x=%s, Gate 2 x=%s, Bay 2 x=%s" % [by_real.get("x"), made.get("x"), bay.get("x")]
	return ""


## The real data: names are unique at every airport, the unnamed counts match the prototype's, nothing is made up
## that a real stand already has. Skipped (passes) without data/processed.
func test_stand_names_real_airport_ops() -> String:
	var ops = Paths.load_json("airport_ops.json") if FileAccess.file_exists(Paths.data("airport_ops.json")) else null
	if ops == null:
		return ""
	var counts := {}
	for icao in ops:
		var stands: Array = ops[icao].get("stands", [])
		var d := StandNames.describe(stands)
		var seen := {}
		var made := 0
		for i in d.size():
			var key := String(d[i].name).to_lower().replace(" ", "")
			if seen.has(key):
				return "%s: name '%s' used twice" % [icao, d[i].name]
			seen[key] = true
			if d[i].made:
				made += 1
				if not (str(d[i].name).begins_with("Gate ") or str(d[i].name).begins_with("Bay ")):
					return "%s: made-up name '%s'" % [icao, d[i].name]
			elif d[i].name != str(stands[i].ref) and not str(d[i].name).begins_with(str(stands[i].ref) + " ("):
				return "%s: real ref '%s' became '%s'" % [icao, stands[i].ref, d[i].name]
		if StandNames.assign(stands) != d.map(func(x): return x.name):
			return "%s: assign and describe disagree" % icao
		counts[icao] = [made, stands.size()]
	if ops.has("VABB") and counts.VABB != [27, 114]:
		return "VABB made-up / stands %s, expected [27, 114]" % [counts.VABB]
	if ops.has("VAPO") and counts.VAPO != [12, 24]:
		return "VAPO made-up / stands %s, expected [12, 24]" % [counts.VAPO]
	return ""
