extends Node
## Debug: screenshots of the Airport step for aircraft x airports x start modes at one or two window sizes, in one
## run, to $FREESIM_SHOTS/airport_<tag><aircraft>_<airport>_<mode>_<w>.png. Needs a display. Does not write saves.
##   FREESIM_AIRCRAFTS=c172,a320   FREESIM_AIRPORTS=VABB,VAPO,VOCI   FREESIM_MODES=runway,stand,air
##   FREESIM_SIZES=1280x720,1920x1080   FREESIM_WIND=270/12   FREESIM_TAG=u5_   FREESIM_HOVER=1 (hover a stand)

var _out := ""


func _env(k: String, d: String) -> PackedStringArray:
	return (OS.get_environment(k) if OS.get_environment(k) != "" else d).split(",")


func _ready() -> void:
	_out = OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	await get_tree().create_timer(1.0).timeout
	s.go("flight")
	var flow: Control = s.screen("flight")
	var page: Control = flow.pages[1]
	var wind := OS.get_environment("FREESIM_WIND") if OS.get_environment("FREESIM_WIND") != "" else "270/12"
	Session.setup.wind_dir_deg = float(wind.get_slice("/", 0))
	Session.setup.wind_kt = float(wind.get_slice("/", 1))
	for size in _env("FREESIM_SIZES", "1280x720"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
		await get_tree().create_timer(0.5).timeout
		for ac in _env("FREESIM_AIRCRAFTS", "c172,a320"):
			Session.setup.aircraft = ac
			Session.apply_payload_defaults(AircraftDef.load_def(ac))
			Session.setup.air_custom = false
			for icao in _env("FREESIM_AIRPORTS", "VABB,VAPO,VOCI"):
				for mode in _env("FREESIM_MODES", "runway,stand,air"):
					flow.show_step(0)
					flow.show_step(1)
					page.pick_airport(icao)
					page._put("start", mode)
					if OS.get_environment("FREESIM_HOVER") != "" and not page.stand_rows().is_empty():
						var d: AirportDiagram = page._diagram
						var st: Dictionary = page.stand_rows()[0].stand
						var m := InputEventMouseMotion.new()
						m.position = AirportMapMath.to_screen(AirportMapMath.view(AirportMapMath.bounds(d.runways, d.stands), d.size, 6.0), Vector2(st.x, st.y))
						d._gui_input(m)
					await get_tree().create_timer(0.4).timeout
					await RenderingServer.frame_post_draw
					var f := "airport_%s%s_%s_%s_%s.png" % [OS.get_environment("FREESIM_TAG"), ac, icao, mode, size.get_slice("x", 0)]
					get_viewport().get_texture().get_image().save_png(_out.path_join(f))
	get_tree().quit()
