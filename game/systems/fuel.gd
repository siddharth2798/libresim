class_name FuelSystem
extends Node
## Fuel selector (LEFT / RIGHT / BOTH / OFF) and shutoff valve. Decides which
## tanks feed and whether the engine gets fuel. Line fuel keeps the engine
## running ~LINE_S seconds after the supply is lost (starvation is not instant).
## Inputs: controls/fuel/selector (0 off, 1 left, 2 right, 3 both),
##         controls/fuel/shutoff (true = closed), fuel/left_kg, fuel/right_kg (from FDM),
##         failures/fuel_leak_left / _right (true -> that tank drains ~5 gal/h extra).
## Outputs: fuel/feed_left, fuel/feed_right (fractions), fuel/available.

const LINE_S := 6.0
const UNUSABLE_KG := 1.5 * 2.72  # per tank
const LEAK_KGS := 5.0 * 2.72 / 3600.0

var _line := LINE_S


func _ready() -> void:
	if not Props.has("controls/fuel/selector"):
		Props.set_v("controls/fuel/selector", 3)
	if not Props.has("controls/fuel/shutoff"):
		Props.set_v("controls/fuel/shutoff", false)


func _physics_process(dt: float) -> void:
	var sel: int = Props.get_v("controls/fuel/selector", 3)
	var left_ok := Props.get_f("fuel/left_kg") > UNUSABLE_KG
	var right_ok := Props.get_f("fuel/right_kg") > UNUSABLE_KG
	var fl := 0.0
	var fr := 0.0
	match sel:
		1: fl = 1.0 if left_ok else 0.0
		2: fr = 1.0 if right_ok else 0.0
		3:
			fl = 1.0 if left_ok else 0.0
			fr = 1.0 if right_ok else 0.0
	if Props.get_b("controls/fuel/shutoff"):
		fl = 0.0
		fr = 0.0
	var supply := fl + fr > 0.0
	if supply:
		_line = LINE_S
		var s := fl + fr
		fl /= s
		fr /= s
	else:
		_line = maxf(_line - dt, 0.0)
	Props.set_v("fuel/feed_left", fl)
	Props.set_v("fuel/feed_right", fr)
	Props.set_v("fuel/available", supply or _line > 0.0)
	Props.set_v("fuel/leak_left_kgs", LEAK_KGS if Props.get_b("failures/fuel_leak_left") else 0.0)
	Props.set_v("fuel/leak_right_kgs", LEAK_KGS if Props.get_b("failures/fuel_leak_right") else 0.0)
