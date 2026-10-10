extends Node
## Debug: render the aircraft from 4 fixed angles to <out>/tt_*.png.
## godot --path game res://tests/debug_turntable.tscn -- --out=<dir>
var t := 0.0
var shots := [[0.0, -0.15, "rear"], [PI / 2, -0.1, "left"], [PI, -0.1, "front"], [-PI * 0.75, -0.5, "top34"]]
var i := 0
var flight: Node
func _ready():
	flight = load("res://world/flight.tscn").instantiate()
	add_child(flight)
func _process(dt):
	t += dt
	if t < 4.0 + i * 0.6:
		return
	if i >= shots.size():
		get_tree().quit(); return
	var cam = flight.get_node("Camera")
	cam.mode = CameraRig.Mode.ORBIT
	cam._look = Vector2(shots[i][0], shots[i][1])
	cam._dist = 14.0
	if t > 4.3 + i * 0.6:
		var out := "/tmp"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--out="): out = a.substr(6)
		get_viewport().get_texture().get_image().save_png(out + "/tt_" + shots[i][2] + ".png")
		i += 1
