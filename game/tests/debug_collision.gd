extends Node
## Debug: fly low through dense Mumbai and report what the damage model hits.
## godot --path game res://tests/debug_collision.tscn
var t := 0.0
var f: Node
func _ready():
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
func _process(dt):
	t += dt
	if t > 2.0 and t - dt <= 2.0:
		var fn: FdmNode = f.get_node("Fdm")
		fn.place_airborne(-60300.0, 25262.0, 110.0, 90.0, 90.0)  # 110 m AMSL, east toward a 282 m tower
	if t > 2.0 and int(t * 2) != int((t - dt) * 2):
		var fd: FDM = f.get_node("Fdm").fdm
		var ob: Array = fd.obstacles.call(fd.pos_e, fd.pos_n, 8.0, fd.altitude() - 8.0, fd.altitude() + 8.0)
		var b: Buildings = f.get_node("Buildings")
		print("COL t %.1f e %.0f n %.0f alt %.0f agl %.0f solids within 8 m %d col_tiles %d crashed %s %s" % [t, fd.pos_e, fd.pos_n, fd.altitude(), Props.get_f("fdm/agl_m"), ob.size(), b.collision.tiles_loaded(), Props.get_b("damage/crashed"), Props.get_v("damage/reason", "")])
	if Props.get_b("damage/crashed") or t > 40.0:
		print("COL RESULT: ", Props.get_v("damage/reason", "no collision"))
		get_tree().quit()
