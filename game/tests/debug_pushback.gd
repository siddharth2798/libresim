extends Node
## Debug: gate start, release the brake, push back, report the motion. With --pb-shot=<png> an overhead picture of the
## aircraft is saved when the run ends (wheels against the pavement after the tug stops). --setup=<json> starts from a
## saved last_flight.json (airport, stand, aircraft); default is the command line / last flight.
##   godot --path game --audio-driver Dummy res://tests/debug_pushback.tscn -- [--setup=<json>] [--pb-shot=<png>] [--secs=55]
var t := 0.0
var f: Node
var h0 := 0.0
var p0 := Vector3.ZERO
var _shot := ""
var _secs := 55.0


func _ready():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pb-shot="):
			_shot = a.substr(10)
		elif a.begins_with("--secs="):
			_secs = float(a.substr(7))
		elif a.begins_with("--setup="):
			var d = JSON.parse_string(FileAccess.get_file_as_string(a.substr(8)))
			for k in d:
				if Session.setup.has(k):
					Session.setup[k] = d[k]
			Session.setup.start = "stand"
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
	if t > _secs and _shot != "" and t - dt <= _secs:
		var cam := Camera3D.new()
		add_child(cam)
		var m: Node3D = f.model
		cam.global_position = m.global_position + Vector3(0.0, 90.0, 0.0)
		cam.look_at(m.global_position, Vector3.FORWARD)
		cam.fov = 45.0
		cam.make_current()
		f.get_node("UI").visible = false
	if t > _secs + (1.5 if _shot != "" else 0.0):
		if _shot != "":
			get_viewport().get_texture().get_image().save_png(_shot)
			print("PB shot ", _shot)
		get_tree().quit()
