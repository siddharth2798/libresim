extends Node
## Debug: the default "In the air" start in the real flight scene, hands off. Prints the height above the
## field, the distance to the threshold, speed, gear and flaps at the start and after 30 s. Run:
##   godot --headless --path game res://tests/debug_air_start.tscn --audio-driver Dummy -- --airport=VABB --runway=27 --air [--aircraft=a320]
var f: Node
var t := 0.0
var _next := 3.0


func _ready() -> void:
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _physics_process(dt: float) -> void:
	t += dt
	if t < _next:
		return
	_next += 27.0
	var fn: FdmNode = f.get_node("Fdm")
	var thr: Vector2 = f._start.pos
	var p := fn.position_enu()
	var field: float = f.terrain.height_at(thr.x, thr.y)
	print("AIR t %4.1f s: %.0f ft above the field, %.2f nm from the threshold, %.0f KIAS, vs %.0f fpm, gear %.2f (lever %s), flaps %s (%.1f deg), setup %s" % [
		t, Units.m_to_ft(p.z - field), Vector2(p.x, p.y).distance_to(thr) / 1852.0, Props.get_f("fdm/cas_mps") / 0.514444,
		Units.m_to_ft(Props.get_f("fdm/vs_mps")) * 60.0,
		fn.fdm.gear.gear_pos if "gear_pos" in fn.fdm.gear else 1.0, Props.get_v("controls/gear", 1), Props.get_v("controls/flaps", 0),
		fn.fdm.fcs.flap_deg, [Session.setup.air_ft, Session.setup.air_nm, Session.setup.air_kt, Session.setup.air_custom]])
	if t > 30.0 or Props.get_b("damage/crashed"):
		print("AIR crashed=%s" % Props.get_b("damage/crashed"))
		get_tree().quit()
