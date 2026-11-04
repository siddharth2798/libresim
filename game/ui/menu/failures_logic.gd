class_name FailuresLogic
extends RefCounted
## The pure part of the Failures step (failures_page.gd): Session.setup.failures is {id: [mode, value]} with the
## mode an index into FailureCatalog.MODES (0 = off is never stored). Reads and edits that dictionary, builds the
## armed list ("what you will get") and its texts. No nodes, so it is tested headless (tests/test_failures_page.gd).

## The four triggers a failure can be armed with: [mode, segment label, hover text].
const TRIGGERS := [
	[1, "At start", "The failure is there from the moment the flight starts."],
	[2, "After time", "The failure happens this many minutes into the flight."],
	[3, "Altitude", "The failure happens when the aircraft climbs through this height above the ground."],
	[4, "Airspeed", "The failure happens when the airspeed passes this value."],
]
const DEFAULTS := [0.0, 0.0, 10.0, 1000.0, 100.0]  # the value a mode starts with


static func default_value(mode: int) -> float:
	return DEFAULTS[clampi(mode, 0, DEFAULTS.size() - 1)]


static func mode_of(failures: Dictionary, id: String) -> int:
	return int(failures[id][0]) if failures.has(id) else 0


static func value_of(failures: Dictionary, id: String) -> float:
	return float(failures[id][1]) if failures.has(id) else 0.0


## Arm `id` with trigger `mode` (0 disarms it). Without `value` the mode's default is used.
static func set_trigger(failures: Dictionary, id: String, mode: int, value := -1.0) -> void:
	if mode <= 0:
		failures.erase(id)
	else:
		failures[id] = [mode, default_value(mode) if value < 0.0 else value]


## A number without a trailing ".0" (10 -> "10", 7.5 -> "7.5").
static func fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else String.num(v)


## "At start", "After 10 min", "Above 1000 ft AGL", "Above 100 kt".
static func trigger_text(mode: int, value: float) -> String:
	match mode:
		1: return "At start"
		2: return "After %s min" % fmt(value)
		3: return "Above %s ft AGL" % fmt(value)
		4: return "Above %s kt" % fmt(value)
	return "Off"


## The armed failures of this aircraft's catalog, in catalog order: [{id, label, category, mode, value, text}].
## (An id left over from the other aircraft is not in the catalog and is not listed.)
static func armed(failures: Dictionary, cats: Array) -> Array:
	var out := []
	for c in cats:
		for f in c[1]:
			var m := mode_of(failures, f[0])
			if m > 0:
				var v := value_of(failures, f[0])
				out.append({"id": f[0], "label": f[1], "category": c[0], "mode": m, "value": v, "text": trigger_text(m, v)})
	return out


## How many failures of one catalog category ([name, [[id, label], ...]]) are armed.
static func armed_in(failures: Dictionary, cat: Array) -> int:
	var n := 0
	for f in cat[1]:
		if mode_of(failures, f[0]) > 0:
			n += 1
	return n


## The armed list's line for random failures ("" while they are off).
static func random_text(random: Dictionary, cat_names: Array) -> String:
	if not bool(random.get("enabled", false)):
		return ""
	var n := int(random.get("count", 1))
	var chosen: Array = cat_names.filter(func(c): return c in random.get("categories", []))
	var from: String
	if chosen.is_empty():
		from = "no system chosen"
	elif chosen.size() == cat_names.size():
		from = "any system"
	else:
		from = ", ".join(chosen)
	return "%d random failure%s, %s to %s min in: %s" % [n, "" if n == 1 else "s", fmt(float(random.get("from_min", 2.0))), fmt(float(random.get("to_min", 30.0))), from]


## Is anything armed (scheduled or random)? Decides whether "Clear all" is offered.
static func any_armed(setup: Dictionary) -> bool:
	for id in setup.failures:
		if int(setup.failures[id][0]) > 0:
			return true
	return bool(setup.random.get("enabled", false))


## "Clear all scheduled failures": the schedule is emptied and random failures go off.
static func clear_all(setup: Dictionary) -> void:
	setup.failures = {}
	setup.random.enabled = false
