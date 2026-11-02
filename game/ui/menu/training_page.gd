extends HBoxContainer
## Start screen: Training. Pick a lesson (Takeoff, Cruise, Landing), choose how much help you
## want, and start. Each lesson is a short guided exercise with a step-by-step card, live
## target gauges, 3D markers and coach messages, graded with 1-3 stars at the end
## (best stars are remembered in user://training.json). Lessons live in training/lessons.json.
## The START LESSON button is the start screen's bottom bar (it calls start()), so it never
## scrolls out of sight; summary() is the text next to it.

signal changed
signal start_requested

const ASSISTS := [
	["full", "Full guidance", "Step card, hints, live gauges, 3D markers (runway line, glide-path rings) and callouts."],
	["light", "Hints only", "Step card, hints and callouts. No gauges or markers."],
	["off", "Minimal", "Just the step list, graded at the end. Like a check ride."],
]

var _lessons: Array = []
var _sel := 0
var _buttons: Array[Button] = []
var _title: Label
var _summary: Label
var _learn: Label
var _meta: Label
var _assist_note: Label
var _assist := "full"


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	# the lessons written for the chosen aircraft; if it has none (a new aircraft), all of them, and
	# starting one switches to the aircraft it is written for
	var mine := TrainingLogic.lessons_for(str(Session.setup.get("aircraft", AircraftDef.DEFAULT_ID)))
	_lessons = mine if not mine.is_empty() else TrainingLogic.load_lessons()
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	left.add_child(MenuTheme.heading("Lessons"))
	var group := ButtonGroup.new()
	var stars := TrainingLogic.load_stars()
	for i in _lessons.size():
		var l: Dictionary = _lessons[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 64)
		var n := int(stars.get(l.id, 0))
		b.text = "%d   %s\n      %s" % [i + 1, l.title, ("★".repeat(n) + "☆".repeat(3 - n)) if n > 0 else "not flown yet"]
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_select.bind(i))
		left.add_child(b)
		_buttons.append(b)
	left.add_child(MenuTheme.note("Fly them in order, or pick the one you want to practise. Lessons start at Pune in calm, clear weather. Your free-flight setup is not changed."))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	right.add_child(_title)
	_meta = MenuTheme.note("")
	right.add_child(_meta)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_summary)
	right.add_child(MenuTheme.heading("You will learn"))
	_learn = Label.new()
	_learn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_learn)
	right.add_child(MenuTheme.heading("How much help?"))
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 8)
	right.add_child(ah)
	var ag := ButtonGroup.new()
	for a in ASSISTS:
		var b := Button.new()
		b.text = a[1]
		b.toggle_mode = true
		b.button_group = ag
		b.button_pressed = a[0] == _assist
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func():
			_assist = a[0]
			_assist_note.text = a[2]
			changed.emit())
		ah.add_child(b)
	_assist_note = MenuTheme.note(ASSISTS[0][2])
	right.add_child(_assist_note)
	if not _lessons.is_empty():
		_buttons[0].button_pressed = true
		_select(0)


func _select(i: int) -> void:
	_sel = i
	var l: Dictionary = _lessons[i]
	_title.text = l.title
	_meta.text = "About %d minutes · %d steps · starts at %s runway %s" % [int(l.get("minutes", 5)), l.steps.size(), l.setup.airport, l.setup.runway]
	_summary.text = str(l.summary)
	_learn.text = "\n".join(l.get("learn", []).map(func(t): return "•  " + str(t)))
	changed.emit()


## One line for the start screen's bar: the chosen lesson and help level.
func summary() -> String:
	if _lessons.is_empty():
		return "No lessons found."
	return "%s  ·  %s" % [_lessons[_sel].title, ASSISTS.filter(func(a): return a[0] == _assist)[0][1]]


## START LESSON: write the lesson into Session.setup and ask the start screen to fly it.
func start() -> void:
	if _lessons.is_empty():
		return
	var l: Dictionary = _lessons[_sel]
	TrainingLogic.begin(l, _assist)
	start_requested.emit()
