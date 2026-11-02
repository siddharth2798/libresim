class_name SituationSystems
extends RefCounted
## The systems' own state in a saved situation (core/situation.gd). A system node that carries
## state between ticks joins the group "saveable" in _ready and implements
##   save_key() -> String          stable key in the file ("electrical", "fuel", ...), never renamed
##   save_state() -> Dictionary    JSON-safe values (floats, bools, strings, arrays of those)
##   load_state(d: Dictionary)     put them back; every key optional (read with d.get(k, default))
## so a new system (APU, hydraulics, autoflight) is saved by implementing the three methods, with no
## change here. Old saves keep the flat C172 keys (soc, suction, ...): migrate() reads them.

const GROUP := "saveable"
## File written before the hook existed: flat key -> [system key, key in that system's state].
const LEGACY := {"soc": ["electrical", "soc"], "suction": ["vacuum", "suction"], "fuel_line": ["fuel", "line"],
	"pitot_frozen": ["pitot_static", "pitot_frozen"], "static_frozen": ["pitot_static", "static_frozen"]}


## Every saveable node below `root`.
static func saveables(root: Node) -> Array:
	var out := []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_in_group(GROUP) and n.has_method("save_state") and n.has_method("load_state"):
			out.append(n)
		stack.append_array(n.get_children())
	return out


static func key_of(n: Node) -> String:
	return n.save_key() if n.has_method("save_key") else String(n.name).to_snake_case()


## {save_key: state} of every saveable system.
static func capture(root: Node) -> Dictionary:
	var out := {}
	for n in saveables(root):
		out[key_of(n)] = n.save_state()
	return out


## Hands each system its saved state; a system without an entry keeps its current state (an old
## save from before the system existed), an entry without a system is ignored.
static func apply(root: Node, systems: Dictionary) -> void:
	systems = migrate(systems)
	for n in saveables(root):
		var s: Variant = systems.get(key_of(n), null)
		if s is Dictionary:
			n.load_state(s)


## The old flat format {soc, suction, fuel_line, pitot_frozen, static_frozen} as {system: {key: value}};
## a dictionary already in the new format comes back unchanged (values of both are merged).
static func migrate(systems: Dictionary) -> Dictionary:
	var out := {}
	for k in systems:
		if LEGACY.has(k):
			var m: Array = LEGACY[k]
			if not out.has(m[0]):
				out[m[0]] = {}
			out[m[0]][m[1]] = systems[k]
		else:
			out[k] = systems[k]
	return out
