extends RefCounted
## The systems' part of a saved situation (core/situation_systems.gd): every node in the group
## "saveable" saves and loads its own state, and saves made before the hook (flat soc / suction /
## fuel_line / pitot_frozen keys) still load.

const SAVEABLE_SRC := "extends Node\nvar level := 1.0\nvar names: Array = []\nvar mode := \"off\"\n" \
	+ "func _ready() -> void:\n\tadd_to_group(\"saveable\")\n" \
	+ "func save_key() -> String:\n\treturn \"apu\"\n" \
	+ "func save_state() -> Dictionary:\n\treturn {\"level\": level, \"names\": names, \"mode\": mode}\n" \
	+ "func load_state(d: Dictionary) -> void:\n\tlevel = float(d.get(\"level\", level))\n\tnames = d.get(\"names\", names)\n\tmode = d.get(\"mode\", mode)\n"


## A scene like world/flight.tscn's Systems: the four real systems + a test APU, in the tree.
func _systems() -> Node:
	var root := Node.new()
	var sys := Node.new()
	sys.name = "Systems"
	root.add_child(sys)
	for spec in [["Electrical", Electrical], ["Vacuum", Vacuum], ["Fuel", FuelSystem], ["PitotStatic", PitotStatic]]:
		var n: Node = spec[1].new()
		n.name = spec[0]
		sys.add_child(n)
	var s := GDScript.new()
	s.source_code = SAVEABLE_SRC
	s.reload()
	var apu: Node = s.new()
	apu.name = "Apu"
	sys.add_child(apu)
	for n in sys.get_children():  # no scene tree here (the runner is still setting up): _ready by hand
		n._ready()
	return root


func _via_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d, "", false, true))


func test_situation_saveable_round_trip() -> String:
	var root := _systems()
	var e: Electrical = root.get_node("Systems/Electrical")
	var v: Vacuum = root.get_node("Systems/Vacuum")
	var fu: FuelSystem = root.get_node("Systems/Fuel")
	var p: PitotStatic = root.get_node("Systems/PitotStatic")
	var apu = root.get_node("Systems/Apu")
	e.soc = 0.42
	v.suction = 3.3
	fu._line = 2.5
	p._pitot_frozen = 99000.0
	p._static_frozen = 88000.0
	apu.level = 0.8
	apu.names = ["start", "bleed"]
	apu.mode = "run"
	var saved := _via_json(SituationSystems.capture(root))
	e.soc = 0.9
	v.suction = 0.0
	fu._line = 6.0
	p._pitot_frozen = 0.0
	p._static_frozen = 0.0
	apu.level = 0.0
	apu.names = []
	apu.mode = "off"
	SituationSystems.apply(root, saved)
	var keys := saved.keys()
	keys.sort()
	var err := ""
	if keys != ["apu", "electrical", "fuel", "pitot_static", "vacuum"]:
		err = "saved keys %s" % [keys]
	elif e.soc != 0.42 or v.suction != 3.3 or fu._line != 2.5 or p._pitot_frozen != 99000.0 or p._static_frozen != 88000.0:
		err = "system state not restored: %s %s %s %s %s" % [e.soc, v.suction, fu._line, p._pitot_frozen, p._static_frozen]
	elif apu.level != 0.8 or apu.names != ["start", "bleed"] or apu.mode != "run":
		err = "test system not restored: %s %s %s" % [apu.level, apu.names, apu.mode]
	# a system missing from the file keeps its state; a key without a system is ignored
	saved.erase("vacuum")
	saved["hydraulics"] = {"psi": 3000.0}
	v.suction = 1.5
	SituationSystems.apply(root, saved)
	if err == "" and v.suction != 1.5:
		err = "a system without a saved entry must keep its state"
	root.free()
	return err


func test_situation_old_systems_format_loads() -> String:
	var root := _systems()
	# the flat dictionary core/situation.gd wrote before the saveable hook
	var old := {"soc": 0.5, "suction": 2.0, "fuel_line": 3.0, "pitot_frozen": 99000.0, "static_frozen": 88000.0}
	SituationSystems.apply(root, _via_json(old))
	var e: Electrical = root.get_node("Systems/Electrical")
	var v: Vacuum = root.get_node("Systems/Vacuum")
	var fu: FuelSystem = root.get_node("Systems/Fuel")
	var p: PitotStatic = root.get_node("Systems/PitotStatic")
	var err := ""
	if e.soc != 0.5 or v.suction != 2.0 or fu._line != 3.0 or p._pitot_frozen != 99000.0 or p._static_frozen != 88000.0:
		err = "old-format systems not loaded: %s %s %s %s %s" % [e.soc, v.suction, fu._line, p._pitot_frozen, p._static_frozen]
	var mig := SituationSystems.migrate(old)
	if err == "" and (mig.electrical != {"soc": 0.5} or mig.pitot_static.size() != 2 or SituationSystems.migrate(mig) != mig):
		err = "migrate: %s" % [mig]
	root.free()
	return err


func test_situation_prop_prefixes() -> String:
	for pre in ["engines/", "ap/", "apu/", "fcu/", "hyd/", "engine/", "controls/", "fuel/"]:
		if not pre in Situation.PROP_PREFIXES:
			return "prefix %s not saved" % pre
	return ""
