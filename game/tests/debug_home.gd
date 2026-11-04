extends Node
## Debug: screenshot of the home screen (needs a display), with or without history. Scratch files only: the
## player's last_flight.json, training.json and options are never read or written.
##   FREESIM_SIZE=1920x1080  window size (default 1280x720)
##   HOME_DATA=1             a saved A320 flight and one lesson flown (shortcuts shown); 0 = none
##   HOME_FOCUS=fly|continue|more  focus the Fly again / Continue button or the first quiet link
##   FREESIM_SHOTS=<dir>, FREESIM_TAG=<prefix>   where / how the file is named (home_<tag>.png)


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	Session.skip_menu = false
	Session.interactive_override = 0
	Session.save_path = "user://_debug_home_last_flight.json"
	TrainingLogic.save_path = "user://_debug_home_training.json"
	for p in [Session.save_path, TrainingLogic.save_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if OS.get_environment("HOME_DATA") == "1":
		var s := Session.DEFAULT.duplicate(true)
		s.merge({"aircraft": "a320", "airport": "VOMM", "runway": "09", "fuel_gal": 8000.0}, true)
		FileAccess.open(Session.save_path, FileAccess.WRITE).store_string(JSON.stringify(s))
		FileAccess.open(TrainingLogic.save_path, FileAccess.WRITE).store_string(JSON.stringify({"takeoff": 2}))
	var scr: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(scr)
	var home: Control = scr.screen("home")
	match OS.get_environment("HOME_FOCUS"):
		"fly": home._cards[0].action_btn.grab_focus()
		"continue": home._cards[1].action_btn.grab_focus()
		"more": home._more[0].grab_focus()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var out := OS.get_environment("FREESIM_SHOTS")
	if out == "":
		out = OS.get_user_data_dir()
	get_viewport().get_texture().get_image().save_png(out.path_join("home_%s.png" % OS.get_environment("FREESIM_TAG")))
	for p in [Session.save_path, TrainingLogic.save_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	get_tree().quit()
