extends Control
## Start screen (main scene). It opens on the home screen, which asks one question: Free
## flight or Training? Each choice then shows only its own path:
##   Free flight  start_flow.gd: Aircraft > Airport & start > Weather & time > Failures >
##                Recording > FLY. The choices go into the Session autoload and are
##                remembered for next time.
##   Training     the lesson list and START LESSON (training_page.gd).
## Saved flights, Controls and Options open from the home screen, each with a Back button.
## Screens are built the first time they are shown. Command-line flight options skip all of
## this (Session.skip_menu); Esc is Back everywhere except on the home screen.

const FLIGHT := "res://world/flight.tscn"
const BG := "res://ui/menu/menu_bg.jpg"
const LOGO := "res://branding/logo.png"
const Frame := preload("res://ui/menu/page_frame.gd")
const Home := preload("res://ui/menu/home_screen.gd")
const Flow := preload("res://ui/menu/start_flow.gd")
## Single-page screens: name -> [title, page script, prompt]. Each sits in a Frame with a Back button.
const PAGES := {
	"training": ["Training", "res://ui/menu/training_page.gd", "Learn to take off, cruise and land, one lesson at a time."],
	"saves": ["Saved flights", "res://ui/menu/saves_page.gd", "Pick up where you left off."],
	"controls": ["Controls", "res://ui/menu/controls_page.gd", "Keyboard, joystick and gamepad."],
	"options": ["Options", "res://ui/menu/options_page.gd", "Sound, graphics and flight-control feel."],
}

var _screens := {}  # name -> screen, built on first use
var cur := ""
var _body: VBoxContainer
var _brand: Control
var dry_run := false  # tests: count the flight but do not load the flight scene
var flights_started := 0
var lessons_started := 0  # tests: lessons started from the home screen's Continue (dry_run does not load the flight scene)
var _top_buttons: Array[Control] = []  # Handbook, Credits, Quit
var _confirm: FlyConfirm  # the open "Fly anyway?" question, or null
var _page_margin: MarginContainer  # kept above the attribution line; may already be gone when that line resizes on the way out
var captain_watch: CaptainWatch  # offers the Thrustmaster Captain Pack profile once per launch (captain_watch.gd)


func _ready() -> void:
	if Session.skip_menu:
		_boot_flight()
		return
	BusyOverlay.dismiss(get_tree())
	AudioSettings.apply()
	set_anchors_preset(PRESET_FULL_RECT)
	theme = MenuTheme.make()
	if ResourceLoader.exists(BG):
		var bg := TextureRect.new()
		bg.texture = load(BG)
		bg.set_anchors_preset(PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.45)
	shade.set_anchors_preset(PRESET_FULL_RECT)
	add_child(shade)
	var guard := ScrollContainer.new()  # a window (or UI scale) too small for a page scrolls instead of pushing Fly and Quit off-screen
	guard.set_anchors_preset(PRESET_FULL_RECT)
	guard.follow_focus = true
	add_child(guard)
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	m.size_flags_vertical = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	_page_margin = m
	guard.add_child(m)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	m.add_child(root)
	root.add_child(_top_bar())
	_body = VBoxContainer.new()
	_body.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(_body)
	var credits := Control.new()
	credits.set_script(load("res://ui/credits_screen.gd"))
	credits.name = "Credits"
	credits.set("margin_left", 24.0)  # no instrument stacks here: the line may use the whole width
	credits.set("margin_right", 24.0)
	credits.connect("attribution_resized", _fit_credits)
	add_child(credits)
	Session.end_lesson()  # coming back from a lesson: restore the free-flight setup
	go("home")
	captain_watch = CaptainWatch.new()
	captain_watch.host = self
	add_child(captain_watch)


## The attribution line wraps on a narrow window. It also resizes while the screen is being
## freed, after the margin it pushes has already gone.
func _fit_credits(h: float) -> void:
	if is_instance_valid(_page_margin):
		_page_margin.add_theme_constant_override("margin_bottom", maxi(28, int(h) + 6))


## Top bar: the small logo and name on every screen but the home screen (which shows them
## large), and Handbook / Credits / Quit always.
func _top_bar() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_brand = HBoxContainer.new()
	_brand.add_theme_constant_override("separation", 12)
	_brand.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(_brand)
	if ResourceLoader.exists(LOGO):
		var logo := TextureRect.new()
		logo.texture = load(LOGO)
		logo.custom_minimum_size = Vector2(48, 48)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_brand.add_child(logo)
	var title := Label.new()
	title.text = "libresim"
	title.add_theme_font_size_override("font_size", 32)
	_brand.add_child(title)
	var sub := Label.new()
	sub.text = "Mumbai – Kochi · Western Ghats"
	sub.add_theme_color_override("font_color", MenuTheme.DIM)
	sub.add_theme_font_size_override("font_size", 16)
	sub.size_flags_vertical = SIZE_SHRINK_END
	sub.size_flags_horizontal = SIZE_EXPAND_FILL
	sub.clip_text = true  # a narrow window shortens the line (ellipsis) before it pushes Handbook / Credits / Quit away
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_brand.add_child(sub)
	var gap := Control.new()  # keeps the buttons right when the brand is hidden
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = 0.01
	hb.add_child(gap)
	for item in [["Handbook", _open_handbook], ["Credits", func(): _press(KEY_F12)], ["Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(100, 40)
		b.pressed.connect(item[1])
		hb.add_child(b)
		_top_buttons.append(b)
	return hb


## Opens the HTML handbook (docs/site/index.html) in the system browser.
func _open_handbook() -> void:
	var path := Paths.docs_dir().path_join("docs/site/index.html")
	if FileAccess.file_exists(path):
		OS.shell_open("file://" + path)
	else:
		push_warning("Handbook not found: " + path)


## Show one screen ("home", "flight" or a PAGES key), building it the first time.
func go(id: String) -> void:
	if not _screens.has(id):
		_screens[id] = _build(id)
		_body.add_child(_screens[id])
	cur = id
	for k in _screens:
		_screens[k].visible = k == id
	_brand.visible = id != "home"
	if _screens[id].has_method("enter"):
		_screens[id].enter()


## Another modal is up (the "Fly anyway?" question, the live-weather question) or a flight is loading:
## nothing else may open over it.
func modal_open() -> bool:
	return _confirm != null or BusyOverlay.root_veil(get_tree()) != null or get_node_or_null("LiveWeatherNotice") != null


func screen(id: String) -> Control:
	return _screens.get(id)


func _build(id: String) -> Control:
	if id == "home":
		var h: Control = Home.new()
		h.choose.connect(_choose)
		h.open_page.connect(go)
		h.outer = _top_buttons
		h.fly_again.connect(_fly_again)
		h.continue_lesson.connect(_continue_lesson)
		return h
	if id == "flight":
		var f: Control = Flow.new()
		f.back_pressed.connect(go.bind("home"))
		f.fly_requested.connect(_fly)
		return f
	var info: Array = PAGES[id]
	var fr: Control = Frame.new()
	var p := Frame.make_page(info[1])
	fr.add_page(p)
	fr.prompt.text = "%s  ·  %s" % [info[0], info[2]]
	fr.back_pressed.connect(go.bind("home"))
	if p.has_signal("start_requested"):  # Training: the bar's big button starts the lesson
		fr.set_primary("START LESSON  ▶")
		fr.primary_pressed.connect(p.start)
		p.start_requested.connect(_start_lesson)
		p.changed.connect(func(): fr.summary.text = p.summary())
	return fr


func _choose(mode: String) -> void:
	UserOptions.set_v("start_mode", mode)
	go(mode)


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


## Training page: the lesson was already written into Session.setup (start_requested).
func _start_lesson() -> void:
	_load_flight("Loading lesson…")


## Home "Continue: next lesson": start that lesson with full guidance (the Training page's default help level).
func _continue_lesson(id: String) -> void:
	var lesson := TrainingLogic.find(id)
	if lesson.is_empty():
		return
	TrainingLogic.begin(lesson, "full")
	lessons_started += 1
	if not dry_run:
		await _start_lesson()


## Home "Fly again": the last saved Free-flight setup goes through the same _fly as Fly now (readiness check,
## "Fly anyway?"). The live setup is replaced in place for it and put back if the pilot goes back.
func _fly_again() -> void:
	var saved := HomeShortcuts.last_flight()
	if _confirm != null or saved.is_empty():
		return
	var before := Session.setup.duplicate(true)
	_set_setup(saved)
	await _fly()
	if _confirm != null:
		_confirm.cancelled.connect(_set_setup.bind(before))


func _set_setup(d: Dictionary) -> void:
	Session.setup.clear()
	Session.setup.merge(d.duplicate(true))


## Free flight (Fly now, the FLY button, Ctrl+Enter): a ready setup flies at once; one with a "bad" check
## (SetupChecks: weight, CG, short runway, tailwind, crosswind) first asks "Fly anyway?". Never blocks.
func _fly() -> void:
	if _confirm != null:
		return  # the question is already open
	var bad := SetupChecks.reasons(SetupChecks.checks(Session.setup))
	if bad.is_empty():
		await _fly_now()
		return
	_confirm = FlyConfirm.make(bad)
	_confirm.cancelled.connect(_close_confirm)
	_confirm.confirmed.connect(func():
		_close_confirm()
		_fly_now())
	add_child(_confirm)


func _close_confirm() -> void:
	if _confirm != null:
		_confirm.queue_free()
		_confirm = null


func _fly_now() -> void:
	Session.training = ""  # a free flight, not a lesson
	Session.save()
	flights_started += 1
	if dry_run:
		return
	_load_flight("Loading scenery…")


func _boot_flight() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred(FLIGHT)
		return
	_load_flight("Loading scenery…")


func _load_flight(text: String) -> void:
	BusyOverlay.load_scene(get_tree(), FLIGHT, text)


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo or e.keycode != KEY_ESCAPE or cur == "home":
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:  # Esc leaves the text box first
		get_viewport().gui_release_focus()
	else:
		_screens[cur].go_back()
	get_viewport().set_input_as_handled()
