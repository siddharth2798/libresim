extends RefCounted
## Scene setup for tests/debug_showcase.gd: the Session for a flight scene (lesson, weather, aircraft, setup keys),
## the start-screen pages (menu scenes), hiding the UI, and the scripted flight before the aircraft is frozen.
## `s` is the showcase node (it is also the scripted landing pilot's probe: ts, pl, t, st, args).

const MENU := "res://ui/menu/start_screen.tscn"


static func setup_session(def: Dictionary) -> void:
	Session.skip_menu = true
	Session.clean = false
	Session.shot = ""
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.end_lesson()
	if def.has("lesson"):  # the lesson shows its card and markers; "pilot_lesson" only flies it (no training UI)
		var lesson := TrainingLogic.find(def.lesson)
		TrainingLogic.begin(lesson, "full")
	elif def.has("pilot_lesson"):
		var lesson := TrainingLogic.find(def.pilot_lesson)
		TrainingLogic.begin(lesson, "off")
	if def.has("weather"):  # after the lesson, which brings its own
		Session.apply_weather_preset(def.weather)
	choose_aircraft(def)
	for k in def.get("setup", {}):
		Session.setup[k] = def.setup[k]
	Session.setup.record = false
	Session.view = def.get("view", "chase")


## setup.aircraft (e.g. "a320"): choose it the way the start screen does, so its payload defaults apply
## (fuel and loads); the other setup keys are applied after this and override them.
static func choose_aircraft(def: Dictionary) -> void:
	var id: String = def.get("setup", {}).get("aircraft", "")
	if id != "":
		Session.setup.aircraft = id
		Session.apply_payload_defaults(AircraftDef.load_def(id))


## The start-screen pages (home, Training, the free-flight steps); saves the shot.
static func menu(s: Node, def: Dictionary) -> void:
	Session.skip_menu = false
	Session.setup = Session.DEFAULT.duplicate(true)
	choose_aircraft(def)
	for k in def.get("setup", {}):
		Session.setup[k] = def.setup[k]
	Session.setup.air_custom = ["air_ft", "air_nm", "air_kt"].any(func(k): return def.get("setup", {}).has(k))  # explicit numbers stay on the page
	if def.has("weather"):
		Session.apply_weather_preset(def.weather)
	var sc: Control = load(MENU).instantiate()
	s.add_child(sc)
	await s.wait(1.5)
	sc.go(def.menu)
	if def.has("step"):
		sc.screen("flight").show_step(int(def.step))
	await s.wait(1.5)
	if def.has("scroll"):  # scroll the page down by that many pixels (a long page such as the A320's aircraft step)
		for c in sc.find_children("*", "ScrollContainer", true, false):
			if (c as Control).is_visible_in_tree():
				c.scroll_vertical = int(def.scroll)
		await s.wait(0.5)
	await s.save()


## Hide every UI element of the flight scene `f` except `keep` (node names under $UI; "training" = the lesson
## card) and the credits node (it holds the data attribution line).
static func hide_ui(f: Node, keep: Array) -> void:
	f.get_node("ControlsOverlay").visible = false
	for c in f.get_node("UI").get_children():
		var is_keep: bool = c.name in keep or c.name == "Credits" or ("training" in keep and c is TrainingHud)
		if is_keep:
			continue
		c.visible = false
		c.set_process(false)
	if "Hud" in keep:
		f.get_node("UI/Hud").visible = true


## Scripted flight for d.secs seconds before the aircraft is frozen: a climb / cruise through the
## E2E attitude pilot, or (d.landing) the landing lesson's scripted pilot: flaps, 70 kt, the glide
## path, so the shot shows a real stabilised approach (set d.lesson in the scene).
static func fly(s: Node, d: Dictionary) -> void:
	var f: Node = s.f
	for n in ["Controls", "JoystickControls"]:
		f.get_node(n).set_process(false)
		f.get_node(n).set_physics_process(false)
	var pl := Node.new()
	pl.set_script(load("res://tests/e2e/e2e_pilot.gd"))
	s.add_child(pl)
	s.pl = pl
	pl.active = true
	if d.get("landing", false):
		s.ts = f.get_node("Training")
		s.t = 0.0
		s.st = {}
		s.landing_pilot = true
	else:
		pl.pitch_tgt = float(d.get("pitch", 0.0))
		pl.roll_tgt = float(d.get("roll", 0.0))
		Props.set_v("controls/throttle", float(d.get("throttle", 1.0)))
		Props.set_v("controls/mixture", 1.0)
		Props.set_v("controls/flaps", int(d.get("flaps", 0)))
	await s.wait(float(d.get("secs", 8.0)))
	s.landing_pilot = false
	pl.active = false
