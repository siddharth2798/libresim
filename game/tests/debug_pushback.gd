extends Node
## Debug: VABB gate start, release brake, pushback, report the motion.
var t := 0.0
var f: Node
var h0 := 0.0
var p0 := Vector3.ZERO
func _ready():
	f = load("res://world/flight.tscn").instantiate(); add_child(f)
func _process(dt):
	t += dt
	var fn: FdmNode = f.get_node("Fdm")
	if t > 2.0 and t - dt <= 2.0:
		Props.set_v("controls/parking_brake", false); f.get_node("Controls").parking_brake = false
		h0 = rad_to_deg(fn.fdm.euler().z); p0 = fn.position_enu()
		f.get_node("GroundOps").start_pushback()
	if t > 2.0 and int(t) != int(t - dt) and int(t) % 10 == 0:
		print("PB t %.0f moved %.1f m heading %.0f -> %.0f  msg: %s" % [t, Vector2(fn.position_enu().x - p0.x, fn.position_enu().y - p0.y).length(), h0, rad_to_deg(fn.fdm.euler().z), f.get_node("GroundOps")._banner.text])
	if t > 55.0:
		get_tree().quit()
