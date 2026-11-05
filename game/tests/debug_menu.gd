extends Node
## Debug: open the start screen and save a screenshot of every screen (home, the five
## free-flight steps, Training, Saved flights, Controls, Options) to
## $FREESIM_SHOTS/menu_<name>.png (default user://), then quit. Needs a display.
##   FREESIM_SIZE=1920x1080  window size (default 1280x720)
##   FREESIM_AIRCRAFT=a320   choose that aircraft first
##   FREESIM_START=stand     start-at choice of step 2, Airport (runway | stand | air)
##   FREESIM_AIRPORT=VAPO    airport of step 2 (default VABB; only with FREESIM_START)
##   FREESIM_OPEN=1          open 'More weather' and the aircraft 'Details' first
##   FREESIM_FLY=1           also launch a flight from VABB and grab it
##   FREESIM_OVERWEIGHT=1    load the chosen aircraft over its maximum takeoff weight (amber Fly anyway)
##   FREESIM_FLOW_ONLY=1     only the five free-flight steps (skip home, Training, Saved flights, Controls, Options)
##   FREESIM_CALLSIGN=VT-SID  type that call sign (Session.setup.callsign) first
##   FREESIM_WIND=360/25     wind direction / speed (deg / kt) in the setup (a crosswind on runway 27 of VABB: reasons list)
##   FREESIM_STAND="Terminal 1 Gate 12A ..."  a long stand name in the setup after the pages are built (footer chip width)
##   FREESIM_FAKE_CAPTAIN=1  only the Captain Pack offer over the home screen (menu_captain_offer.png): a fake sidestick + quadrant, a
##                           scratch bindings path and no saved options, so nothing real is read or written; =linux adds the Linux line
##   FREESIM_TAG=u2_         prefix of the file names (menu_<tag><name>.png)

var _s: Control
var _out := ""


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	if OS.get_environment("FREESIM_AIRCRAFT") != "":  # e.g. a320: the start screen opens with that aircraft chosen
		Session.setup.aircraft = OS.get_environment("FREESIM_AIRCRAFT")
		Session.apply_payload_defaults(AircraftDef.load_def(Session.setup.aircraft))
	if OS.get_environment("FREESIM_CALLSIGN") != "":
		Session.setup.callsign = OS.get_environment("FREESIM_CALLSIGN")
	if OS.get_environment("FREESIM_OVERWEIGHT") != "":
		Session.setup.fuel_gal = 19400.0 if Session.setup.aircraft == "a320" else 20.0
		for k in ["cabin_kg", "cargo_kg", "copilot_kg", "rear_kg", "baggage_kg"]:
			Session.setup[k] = {"cabin_kg": 14000.0, "cargo_kg": 5000.0, "copilot_kg": 120.0, "rear_kg": 200.0, "baggage_kg": 54.0}[k]
		print("checks: ", SetupChecks.checks(Session.setup))
	if OS.get_environment("FREESIM_START") != "":  # runway | stand | air
		Session.setup.start = OS.get_environment("FREESIM_START")
		Session.setup.airport = OS.get_environment("FREESIM_AIRPORT") if OS.get_environment("FREESIM_AIRPORT") != "" else "VABB"
	if OS.get_environment("FREESIM_WIND").contains("/"):
		Session.setup.wind_dir_deg = float(OS.get_environment("FREESIM_WIND").get_slice("/", 0))
		Session.setup.wind_kt = float(OS.get_environment("FREESIM_WIND").get_slice("/", 1))
	var fake_captain := OS.get_environment("FREESIM_FAKE_CAPTAIN")
	if fake_captain != "":
		Session.interactive_override = 0  # nothing is saved
		UserOptions.get_v("captain_pack")
		UserOptions._v["captain_pack"] = ""
		CaptainDetect.bindings_path = "user://_debug_fake_captain_bindings.json"  # not there: the generic defaults
		CaptainDetect.pads_provider = func(): return [{"id": 0, "name": "Thrustmaster TCA Sidestick X Copilot", "guid": "a"}, {"id": 1, "name": "Thrustmaster TCA Q-Eng 1&2", "guid": "b"}]
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	await get_tree().create_timer(1.0).timeout
	if fake_captain != "":
		_s.captain_watch.check()
		if fake_captain == "linux":
			_s.captain_watch.offer.body_label.text = CaptainOffer.body_text("Linux")
		await _shot("captain_offer")
		get_tree().quit()
		return
	if OS.get_environment("FREESIM_FLOW_ONLY") == "":
		await _shot("home")
	_s.go("flight")
	if OS.get_environment("FREESIM_OPEN") != "":
		_s.screen("flight").pages[0]._show_details(true)  # the aircraft page
		_s.screen("flight").pages[2]._show_more(true)
	for i in _s.screen("flight").STEPS.size():
		_s.screen("flight").show_step(i)
		if i == 2 and OS.get_environment("FREESIM_STAND") != "":  # after the Airport step: it replaces a stand it does not know
			Session.setup.stand = OS.get_environment("FREESIM_STAND")
		await _shot("flight_%d" % (i + 1))
	for id in ([] if OS.get_environment("FREESIM_FLOW_ONLY") != "" else ["training", "saves", "controls", "options"]):
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
	get_viewport().get_texture().get_image().save_png(_out.path_join("menu_%s%s.png" % [OS.get_environment("FREESIM_TAG"), tag]))
