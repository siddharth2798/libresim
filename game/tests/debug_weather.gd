extends Node
## Debug: screenshots of the Weather & time step (step 3 of the free-flight flow) for a given setup, to
## $FREESIM_SHOTS/menu_<tag>weather.png (default user://), then quit. Needs a display. Nothing is saved.
##   FREESIM_SIZE=1920x1080  window size (default 1280x720)
##   FREESIM_AIRCRAFT=a320   choose that aircraft first
##   FREESIM_WIND=000/25     wind "dir/kt" (or "dir/kt/gust")
##   FREESIM_RUNWAY=27       runway of VABB (default 27)
##   FREESIM_START=stand     runway | stand | air
##   FREESIM_TIME=21.5       time of day, IST hours
##   FREESIM_DAY=45          day of the year
##   FREESIM_WEATHER=Broken  a weather preset
##   FREESIM_OPEN=1          open "More weather"
##   FREESIM_TAG=u6_         file name prefix

var _s: Control


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	Session.save_path = "user://debug_weather_last.json"  # never the player's real save
	Session.setup = Session.DEFAULT.duplicate(true)  # not the player's last flight
	if OS.get_environment("FREESIM_AIRCRAFT") != "":
		Session.setup.aircraft = OS.get_environment("FREESIM_AIRCRAFT")
		Session.apply_payload_defaults(AircraftDef.load_def(Session.setup.aircraft))
	Session.setup.airport = "VABB"
	Session.setup.runway = OS.get_environment("FREESIM_RUNWAY") if OS.get_environment("FREESIM_RUNWAY") != "" else "27"
	if OS.get_environment("FREESIM_START") != "":
		Session.setup.start = OS.get_environment("FREESIM_START")
	if OS.get_environment("FREESIM_WEATHER") != "":
		Session.apply_weather_preset(OS.get_environment("FREESIM_WEATHER"))
	if OS.get_environment("FREESIM_WIND") != "":
		var p := OS.get_environment("FREESIM_WIND").split("/")
		Session.setup.wind_dir_deg = float(p[0])
		Session.setup.wind_kt = float(p[1])
		Session.setup.gust_kt = float(p[2]) if p.size() > 2 else 0.0
	if OS.get_environment("FREESIM_TIME") != "":
		Session.setup.time_h = float(OS.get_environment("FREESIM_TIME"))
	if OS.get_environment("FREESIM_DAY") != "":
		Session.setup.day_of_year = float(OS.get_environment("FREESIM_DAY"))
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	await get_tree().create_timer(1.0).timeout
	_s.go("flight")
	_s.screen("flight").show_step(2)
	if OS.get_environment("FREESIM_OPEN") != "":
		_s.screen("flight").pages[2]._show_more(true)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	print("weather page minimum size: ", _s.screen("flight").pages[2].get_combined_minimum_size())
	var out := OS.get_environment("FREESIM_SHOTS")
	if out == "":
		out = OS.get_user_data_dir()
	get_viewport().get_texture().get_image().save_png(out.path_join("menu_%sweather.png" % OS.get_environment("FREESIM_TAG")))
	get_tree().quit()
