extends HBoxContainer
## Start screen: Training. Pick a lesson (cards with your best stars), choose how much help you want, and start. Each
## lesson is a short guided exercise with a step-by-step card, live target gauges, 3D markers and coach messages,
## graded with 1-3 stars at the end (best stars are remembered in user://training.json, TrainingLogic.save_path).
## Lessons live in training/lessons.json; the right side shows the chosen lesson: goal, what you will learn, the
## steps, where you start and the help level's note (texts: lesson_info.gd). The START LESSON button is the start
## screen's bottom bar (it calls start()), so it never scrolls out of sight; summary() is the text next to it.

signal changed
signal start_requested

const ASSISTS := [
	["full", "Full guidance", "Step card, hints, live gauges, 3D markers (runway line, glide-path rings) and callouts."],
	["light", "Hints only", "Step card, hints and callouts. No gauges or markers."],
	["off", "Minimal", "Just the step list, graded at the end. Like a check ride."],
]

var _lessons: Array = []
var _sel := 0
var _cards: Array[LessonCard] = []
var _help: Array[Button] = []
var _title: Label
var _badge: Label
var _chips: HFlowContainer
var _summary: Label
var _learn: VBoxContainer
var _steps: VBoxContainer
var _where: Label
var _markers: Label
var _assist_note: Label
var _assist := "full"


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	# the lessons written for the chosen aircraft; if it has none (a new aircraft), all of them, and
	# starting one switches to the aircraft it is written for
	var mine := TrainingLogic.lessons_for(str(Session.setup.get("aircraft", AircraftDef.DEFAULT_ID)))
	_lessons = mine if not mine.is_empty() else TrainingLogic.load_lessons()
	_build_left()
	_build_right()
	visibility_changed.connect(func(): if is_visible_in_tree(): _refresh_stars())
	if not _lessons.is_empty():
		_cards[0].button_pressed = true
		_select(0)


func _build_left() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	left.add_child(MenuTheme.heading("Lessons"))
	var group := ButtonGroup.new()
	var stars := TrainingLogic.load_stars()
	for i in _lessons.size():
		var l: Dictionary = _lessons[i]
		var c := LessonCard.new().setup(i, l, int(stars.get(l.id, 0)))
		c.button_group = group
		c.pressed.connect(_select.bind(i))
		left.add_child(c)
		_cards.append(c)
	left.add_child(_spaced(MenuTheme.heading("How much help?")))
	var ag := ButtonGroup.new()
	for a in ASSISTS:
		var b := Button.new()
		b.text = a[1]
		b.button_group = ag
		PageStyles.list_item(b, 12.0, 7.0)
		b.button_pressed = a[0] == _assist
		b.pressed.connect(func():
			_assist = a[0]
			_assist_note.text = a[2]
			changed.emit())
		left.add_child(b)
		_help.append(b)
	left.add_child(MenuTheme.note("Fly them in order, or pick the one you want to practise."))


func _build_right() -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 12)
	add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	MenuTheme.use_font(_title, "semibold", MenuTheme.SIZE_TITLE)
	head.add_child(_title)
	_badge = MenuTheme.heading("", 13)
	_badge.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_badge)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 8)
	_chips.add_theme_constant_override("v_separation", 6)
	right.add_child(_chips)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 17)
	right.add_child(_summary)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	right.add_child(cols)
	var a := VBoxContainer.new()
	a.size_flags_horizontal = SIZE_EXPAND_FILL
	a.add_theme_constant_override("separation", 6)
	cols.add_child(a)
	a.add_child(MenuTheme.heading("You will learn"))
	_learn = _list_box(a)
	a.add_child(_spaced(MenuTheme.heading("Steps")))
	_steps = _list_box(a)
	var b := VBoxContainer.new()
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(230, 0)
	b.add_theme_constant_override("separation", 8)
	cols.add_child(b)
	b.add_child(MenuTheme.heading("Where you start"))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", PageStyles.inset())
	b.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)
	_where = _wrapped(cv, "")
	_markers = MenuTheme.note("")
	cv.add_child(_markers)
	_assist_note = MenuTheme.note(ASSISTS[0][2])
	b.add_child(_assist_note)
	b.add_child(MenuTheme.note("Lessons start at Pune in calm, clear weather. Your free-flight setup is not changed."))


func _list_box(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	parent.add_child(v)
	return v


func _wrapped(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(180, 0)
	parent.add_child(l)
	return l


func _spaced(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 8)
	m.add_child(c)
	return m


func _select(i: int) -> void:
	_sel = i
	var l: Dictionary = _lessons[i]
	_title.text = l.title
	_badge.text = LessonInfo.aircraft_name(l).to_upper()
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	for t in LessonInfo.chips(l):
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.08), 999, Color(1, 1, 1, 0.12), 12.0))
		var lb := Label.new()
		lb.text = t
		p.add_child(lb)
		_chips.add_child(p)
	_summary.text = str(l.summary)
	_fill(_learn, LessonInfo.learn(l), false)
	_fill(_steps, LessonInfo.step_titles(l), true)
	_where.text = LessonInfo.where(l)
	_markers.text = LessonInfo.markers(l)
	_markers.visible = _markers.text != ""
	changed.emit()


## Bullets (or "1. title" lines) of a lesson's list.
func _fill(box: VBoxContainer, items: Array, numbered: bool) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for k in items.size():
		_wrapped(box, ("%d.  %s" % [k + 1, items[k]]) if numbered else "•  " + str(items[k]))


func _refresh_stars() -> void:
	var stars := TrainingLogic.load_stars()
	for i in _cards.size():
		_cards[i].set_stars(int(stars.get(_lessons[i].id, 0)), int(_lessons[i].get("minutes", 5)))


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
