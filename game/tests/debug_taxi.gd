extends Node
## Debug: request a taxi route from a stand and print it.
var t := 0.0
var f: Node
func _ready():
	f = load("res://world/flight.tscn").instantiate(); add_child(f)
func _process(dt):
	t += dt
	if t > 2.0:
		var g: GroundOps = f.get_node("GroundOps")
		g.request_taxi()
		var length := 0.0
		for i in range(g._route.size() - 1): length += (g._route[i] as Vector2).distance_to(g._route[i + 1])
		print("TAXI ", Props.get_v("ops/taxi_route", "none"), " | ", g._route.size(), " points, ", int(length), " m")
		get_tree().quit()
