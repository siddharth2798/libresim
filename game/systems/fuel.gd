class_name FuelSystem
extends Node
## Which tanks feed the engines and whether they get fuel at all. Line fuel keeps the engines
## running ~line_s seconds after the supply is lost (starvation is not instant).
## The aircraft's aircraft.json "systems.fuel" sets "feed": "selector" (C172: selector OFF / LEFT /
## RIGHT / BOTH picks the tanks by side) or "all" (every tank with fuel feeds, no selector),
## "line_s", "unusable_kg_per_tank" and "leak_kg_per_h" (what a leaking tank loses).
## Inputs: controls/fuel/selector (0 off, 1 left, 2 right, 3 both), controls/fuel/shutoff
##         (true = closed), fuel/tank_kg (per tank, from the FDM),
##         failures/fuel_leak_left / _right (true -> the tanks on that side drain extra).
## Outputs: fuel/feed (per tank, fractions summing to 1), fuel/leak_kgs (per tank), fuel/available.

const DEFAULTS := {"feed": "selector", "line_s": 6.0, "unusable_kg_per_tank": 4.08, "leak_kg_per_h": 13.6}

var _p := DEFAULTS.duplicate()
var _sides: Array[String] = []  # per tank: left | right | centre
var _line := 0.0


func _ready() -> void:
	var def := AircraftDef.current()
	_p.merge(def.section("systems").get("fuel", {}), true)
	_sides.clear()
	for t in def.config().tanks:
		var y: float = t.pos_m[1]
		_sides.append("left" if y < -0.1 else ("right" if y > 0.1 else "centre"))
	_line = _p.line_s
	if not Props.has("controls/fuel/selector"):
		Props.set_v("controls/fuel/selector", 3)
	if not Props.has("controls/fuel/shutoff"):
		Props.set_v("controls/fuel/shutoff", false)


func _physics_process(dt: float) -> void:
	var kg = Props.get_v("fuel/tank_kg", null)
	var feed: Array = []
	var leak: Array = []
	var sel: int = Props.get_v("controls/fuel/selector", 3)
	var closed := Props.get_b("controls/fuel/shutoff")
	var leak_kgs: float = _p.leak_kg_per_h / 3600.0
	var total := 0.0
	for i in _sides.size():
		var has_fuel: bool = kg is Array and i < kg.size() and float(kg[i]) > float(_p.unusable_kg_per_tank)
		var fed: bool = _p.feed == "all" or sel == 3 or (sel == 1 and _sides[i] == "left") or (sel == 2 and _sides[i] == "right")
		var w := 1.0 if has_fuel and fed and not closed else 0.0
		feed.append(w)
		total += w
		leak.append(leak_kgs if _sides[i] != "centre" and Props.get_b("failures/fuel_leak_" + _sides[i]) else 0.0)
	if total > 0.0:
		_line = _p.line_s
		for i in feed.size():
			feed[i] /= total
	else:
		_line = maxf(_line - dt, 0.0)
	Props.set_v("fuel/feed", feed)
	Props.set_v("fuel/leak_kgs", leak)
	Props.set_v("fuel/available", total > 0.0 or _line > 0.0)
