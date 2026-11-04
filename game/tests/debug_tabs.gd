extends Node
## Debug: open the start screen's Options and Controls pages and save a screenshot of every tab to
## $FREESIM_SHOTS/<tag>options_<tab>.png and <tag>controls_<tab>.png (default user://), then quit. Needs a
## display. Nothing is changed or saved. FREESIM_SIZE=1920x1080 sets the window, FREESIM_TAG the file prefix,
## FREESIM_AIRCRAFT=a320 the aircraft whose controls are listed, FREESIM_ONLY=options|controls one page only.

var _s: Control
var _out := ""


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	if OS.get_environment("FREESIM_AIRCRAFT") != "":
		Session.setup.aircraft = OS.get_environment("FREESIM_AIRCRAFT")
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	await get_tree().create_timer(1.0).timeout
	var only := OS.get_environment("FREESIM_ONLY")  # options | controls (default both)
	for id in ["options", "controls"]:
		if only != "" and only != id:
			continue
		_s.go(id)
		var page: Control = _s.screen(id).pages[0]
		for t in page.tabs.ids():
			page.tabs.select(t)
			await _shot("%s_%s" % [id, t])
	get_tree().quit()


func _shot(tag: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("%s%s.png" % [OS.get_environment("FREESIM_TAG"), tag]))
