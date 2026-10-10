extends Node
## Debug: open the start screen and save a screenshot of each page to
## $FREESIM_SHOTS/menu_<n>.png (default user://), then quit.

var _s: Control


func _ready() -> void:
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	var out := OS.get_environment("FREESIM_SHOTS")
	if out == "":
		out = OS.get_user_data_dir()
	for i in 4:
		_s._show(i)
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(out.path_join("menu_%d.png" % i))
	if OS.get_environment("FREESIM_FLY") != "":  # also launch the flight and grab it
		Session.shot = out.path_join("menu_fly.png")  # the flight scene saves it and quits
		Session.setup.airport = "VABB"
		Session.setup.start = "stand"
		Session.setup.stand = ""
		Session.setup.time_h = 19.0
		_s._fly()
		return
	get_tree().quit()
