extends Node
## Debug: start at a stand and render a high orbit view. godot --path game res://tests/debug_stand.tscn -- --airport=VABB --stand
var t := 0.0
var f: Node
func _ready():
	f = load("res://world/flight.tscn").instantiate(); add_child(f)
func _process(dt):
	t += dt
	var cam = f.get_node("Camera")
	if t > 1.0:
		cam.mode = CameraRig.Mode.ORBIT
		cam._dist = 90.0
		cam._look = Vector2(0.6, -0.55)
	if t > 4.0:
		print("STAND ", Props.get_v("ops/stand", "?"))
		get_viewport().get_texture().get_image().save_png("/tmp/claude-1000/-home-siddharth-Documents-tech-projects-free-sim/f135e359-9884-4ff2-83d4-f05bf2eb11b5/scratchpad/a2.png")
		get_tree().quit()
