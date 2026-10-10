extends Node
## Debug: request a taxi route from a stand and print it.
var t := 0.0
var f: Node
func _ready():
	f = load("res://world/flight.tscn").instantiate(); add_child(f)
func _process(dt):
	t += dt
	var g: GroundOps = f.get_node("GroundOps")
	if t > 2.0 and t - dt <= 2.0:
		g.request_taxi()
	if t > 2.0 and t < 12.0:
		if int(t) != int(t - dt):
			print("FOLLOW t %.0f car at %.0f m along route, car exists %s" % [t, g._follow_s, g._follow != null])
		return
	if t > 12.0:
		var length := 0.0
		for i in range(g._route.size() - 1): length += (g._route[i] as Vector2).distance_to(g._route[i + 1])
		print("TAXI ", Props.get_v("ops/taxi_route", "none"), " | ", g._route.size(), " points, ", int(length), " m")
		get_tree().quit()
