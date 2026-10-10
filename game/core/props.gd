extends Node
## Autoload "Props": the simulator property tree. A flat map of path -> value,
## e.g. "fdm/ias_mps", "controls/throttle", "systems/electrical/bus_volts".
## Modules communicate only through here. Values are SI unless the name says otherwise.

var _p := {}


func get_f(path: String, default := 0.0) -> float:
	return _p.get(path, default)


func get_b(path: String, default := false) -> bool:
	return _p.get(path, default)


func get_v(path: String, default: Variant = null) -> Variant:
	return _p.get(path, default)


func set_v(path: String, value: Variant) -> void:
	_p[path] = value


func has(path: String) -> bool:
	return _p.has(path)


## All properties under a prefix (for debugging / save files).
func dump(prefix := "") -> Dictionary:
	var out := {}
	for k in _p:
		if k.begins_with(prefix):
			out[k] = _p[k]
	return out


func restore(d: Dictionary) -> void:
	for k in d:
		_p[k] = d[k]
