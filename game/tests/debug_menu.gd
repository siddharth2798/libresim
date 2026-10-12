extends Node
## Debug: open the start screen and save a screenshot of every screen (home, the five
## free-flight steps, Training, Saved flights, Controls, Options) to
## $FREESIM_SHOTS/menu_<name>.png (default user://), then quit. Needs a display.
##   FREESIM_SIZE=1920x1080  window size (default 1280x720)
##   FREESIM_FLY=1           also launch a flight from VABB and grab it

var _s: Control
var _out := ""


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	await get_tree().create_timer(1.0).timeout
	await _shot("home")
	_s.go("flight")
	for i in _s.screen("flight").STEPS.size():
		_s.screen("flight").show_step(i)
		await _shot("flight_%d" % (i + 1))
	for id in ["training", "saves", "controls", "options"]:
		_s.go(id)
		await _shot(id)
	if OS.get_environment("FREESIM_FLY") != "":  # also launch the flight and grab it
		Session.shot = _out.path_join("menu_fly.png")  # the flight scene saves it and quits
		Session.setup.airport = "VABB"
		Session.setup.start = "stand"
		Session.setup.stand = ""
		Session.setup.time_h = 19.0
		_s._fly()
		return
	get_tree().quit()


func _shot(tag: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("menu_%s.png" % tag))
