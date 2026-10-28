class_name AircraftSystems
extends Node
## Builds the systems of the aircraft being flown from its aircraft.json "systems.profile":
## - "ga" (default): nothing. world/flight.tscn keeps its C172 nodes (Electrical, Fuel, Vacuum, PitotStatic).
## - "airliner": AirlinerElectrical, AirlinerHydraulics, AirlinerFuel, AirlinerLights, AirlinerCabin and
##   AirlinerWarnings as children, and PitotStatic (data-driven, "systems.pitot_static") when no sibling or
##   child has one. The C172-only sibling nodes in GA_NODES (piston electrical, selector fuel, vacuum pump)
##   are removed from the parent, so put this node first under Systems in the scene (their _ready never
##   runs, no stale controls/electrical/master_bat Props). The APU node is not made here: FdmNode adds it.
## Every part reads its own "systems.<name>" section of aircraft.json, merged over its DEFAULTS.

const GA_NODES := ["Electrical", "Fuel", "Vacuum"]
const PROFILES := ["ga", "airliner"]

var def: AircraftDef  # tests set it; otherwise the current aircraft
var parts: Array = []


## "ga" or "airliner" (an unknown profile counts as "ga").
static func profile_of(d: AircraftDef) -> String:
	var p := str(d.section("systems").get("profile", "ga"))
	return p if p in PROFILES else "ga"


func _ready() -> void:
	build()


## Creates the part nodes (once); returns them.
func build() -> Array:
	if not parts.is_empty():
		return parts
	if def == null:
		def = AircraftDef.current()
	if profile_of(def) != "airliner":
		return parts
	var parent := get_parent()
	if parent:
		for n in GA_NODES:
			var old := parent.get_node_or_null(n)
			if old:
				parent.remove_child(old)
				old.queue_free()
	var make := [
		["Electrical", AirlinerElectrical], ["Hydraulics", AirlinerHydraulics], ["Fuel", AirlinerFuel],
		["Lights", AirlinerLights], ["Cabin", AirlinerCabin], ["Warnings", AirlinerWarnings],
	]
	for m in make:
		var node: Node = m[1].new()
		node.name = "Airliner" + m[0]
		node.set("def", def)
		add_child(node)
		parts.append(node)
	if (parent == null or parent.get_node_or_null("PitotStatic") == null) and get_node_or_null("PitotStatic") == null:
		var ps := PitotStatic.new()
		ps.name = "PitotStatic"
		add_child(ps)
		parts.append(ps)
	return parts
