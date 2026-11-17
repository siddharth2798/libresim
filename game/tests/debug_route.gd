extends Node
## Debug: screenshots of the Free-flight Route step (ui/menu/route_page.gd) to $FREESIM_SHOTS/route_<tag>.png (default
## user://), then quit. Needs a display; run with --audio-driver Dummy.
##   FREESIM_SIZE=1920x1080   window size (default 1280x720)
##   ROUTE_KIND=airway         auto-route VABB -> VAPO with this kind first (direct | vor | airway; default airway)
##   ROUTE_TEXT="VABB ... VAPO"  a typed route instead
##   FREESIM_START=air        start-at choice (shows the "start on a leg" list)
##   FREESIM_AIRCRAFT=a320    choose that aircraft first
## Shots: route_empty (no route), route_planned (the route, second waypoint selected).

var _s: Control
var _out := ""


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	Session.interactive_override = 0  # nothing is saved
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.airport = "VABB"
	Session.setup.runway = "27"
	Session.setup.route = {}
	if OS.get_environment("FREESIM_AIRCRAFT") != "":
		Session.setup.aircraft = OS.get_environment("FREESIM_AIRCRAFT")
		Session.apply_payload_defaults(AircraftDef.load_def(Session.setup.aircraft))
	if OS.get_environment("FREESIM_START") != "":
		Session.setup.start = OS.get_environment("FREESIM_START")
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	await get_tree().create_timer(0.6).timeout
	_s.go("flight")
	var f: Control = _s.screen("flight")
	f.show_step(3)
	var page: Control = f.pages[3]
	await _shot("empty")
	page.set_destination("VAPO")
	if OS.get_environment("ROUTE_TEXT") != "":
		page.enter_text(OS.get_environment("ROUTE_TEXT"))
	else:
		var kind := OS.get_environment("ROUTE_KIND")
		page.auto_route(kind if kind != "" else "airway")
	page.add_point(Vector2(10000.0, -2000.0), "")
	page.select(1)
	await get_tree().create_timer(0.8).timeout
	print("route: ", Session.setup.route)
	print("page min size: ", page.get_combined_minimum_size(), " map ", page.map.size)
	await _shot("planned")
	if OS.get_environment("ROUTE_DRAG") != "":  # hold a drag on the middle of the first leg (the insert preview)
		var m: RouteMap = page.map
		var l: Dictionary = m.legs[0]
		var mid := m.view.to_px((l.a + l.b) * 0.5)
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = true
		e.position = mid
		m._gui_input(e)
		var mv := InputEventMouseMotion.new()
		mv.position = mid + Vector2(30, 60)
		m._gui_input(mv)
		await _shot("drag")
	get_tree().quit()


func _shot(tag: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var p := _out.path_join("route_%s%s.png" % [OS.get_environment("FREESIM_TAG"), tag])
	get_viewport().get_texture().get_image().save_png(p)
	print("saved ", p)
