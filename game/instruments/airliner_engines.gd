class_name AirlinerEngines
extends Node
## Engine indications of a turbofan airliner in display units, per engine n (1-based):
## instruments/engines/<n>/{n1_pct, n2_pct, egt_c, ff_kgh, oil_psi, running} and engines/count.
## In (SI, from the FDM): engines/<n>/{n1, n2 (fractions of rated, 1.0 = 100 %), egt_k, ff (kg/s; falls
## back to fuel_flow_kgs), oil_press_pa, running}. Needle lag so the digits do not jump.

const LAG := 4.0  # 1/s
const PA_PER_PSI := 6894.757

var _v := {}


## The display values for one engine (pure).
static func to_display(n1: float, n2: float, egt_k: float, ff_kgs: float, oil_pa: float) -> Dictionary:
	return {"n1_pct": n1 * 100.0, "n2_pct": n2 * 100.0, "egt_c": Units.k_to_c(egt_k),
		"ff_kgh": ff_kgs * 3600.0, "oil_psi": oil_pa / PA_PER_PSI}


func _physics_process(dt: float) -> void:
	publish(dt)


func publish(dt: float) -> void:
	var count := int(Props.get_f("engine/count", 2.0))
	Props.set_v("instruments/engines/count", count)
	for n in range(1, count + 1):
		var b := "engines/%d/" % n
		var ff: float = Props.get_f(b + "ff", Props.get_f(b + "fuel_flow_kgs"))
		var tgt := to_display(Props.get_f(b + "n1"), Props.get_f(b + "n2"), Props.get_f(b + "egt_k", 288.15), ff, Props.get_f(b + "oil_press_pa"))
		for k in tgt:
			var key := "%d/%s" % [n, k]
			var cur: float = _v.get(key, tgt[k])
			cur = lerpf(cur, tgt[k], clampf(LAG * dt, 0.0, 1.0))
			_v[key] = cur
			Props.set_v("instruments/engines/" + key, cur)
		Props.set_v("instruments/engines/%d/running" % n, Props.get_b(b + "running"))
