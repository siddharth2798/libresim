extends Node
## Debug: approach to VABB 27 with NAV2 on the ILS; renders cockpit, full panel overlay and map.
var t := 0.0
var f: Node
var shots := 0
func _ready():
	f = load("res://world/flight.tscn").instantiate(); add_child(f)
func _process(dt):
	t += dt
	var SP := (OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()) + "/"
	if t > 1.0 and t - dt <= 1.0:
		Props.set_v("controls/nav2/freq_mhz", 108.1)
		Props.set_v("controls/nav2/obs_deg", 270.0)
		Props.set_v("controls/gps/target", "VAPO")
	if t > 4.0 and shots == 0:
		f.get_node("Camera").set_mode(CameraRig.Mode.COCKPIT); shots = 1
	elif t > 5.0 and shots == 1:
		get_viewport().get_texture().get_image().save_png(SP + "p_cockpit.png"); shots = 2
		f.get_node("Camera").set_mode(CameraRig.Mode.CHASE); var pn = f.get_node("UI/Panel"); pn.layout = 0; pn._build()
	elif t > 6.0 and shots == 2:
		get_viewport().get_texture().get_image().save_png(SP + "p_full.png"); shots = 3
		var pn = f.get_node("UI/Panel"); pn.layout = 4; pn._build(); f.get_node("UI/Map").visible = true
	elif t > 7.5 and shots == 3:
		get_viewport().get_texture().get_image().save_png(SP + "p_map.png"); get_tree().quit()
