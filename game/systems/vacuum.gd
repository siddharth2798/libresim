class_name Vacuum
extends Node
## Engine-driven vacuum pump powering the attitude and heading indicators.
## Suction rises with RPM (regulated to 5.0 inHg above ~1200 RPM).
## failures/vacuum_pump -> suction decays to zero.
## Publishes systems/vacuum/suction_inhg (0..5.5).

var suction := 0.0


func _physics_process(dt: float) -> void:
	var rpm := Props.get_f("engine/rpm")
	var target := clampf(rpm / 1200.0, 0.0, 1.0) * 5.0
	if Props.get_b("failures/vacuum_pump"):
		target = 0.0
	suction = lerpf(suction, target, clampf(dt * 2.0, 0.0, 1.0))
	Props.set_v("systems/vacuum/suction_inhg", suction)
