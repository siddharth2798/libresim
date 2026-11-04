extends VBoxContainer
## Start screen, first page: one question, "What would you like to do?", and two large cards: Free
## flight or Training. When there is history each card also offers a shortcut: "Fly again" (the last
## Free-flight setup) and "Continue: <next lesson>" (data and rules in home_shortcuts.gd). Saved flights,
## Controls and Options sit quietly below. Left / Right or 1 / 2 pick a card, R / C use a shortcut, Enter
## confirms; the last choice is remembered (UserOptions start_mode) and focused next time. Focus order
## (arrows and Tab): the cards, the shortcuts that are shown, the quiet links.

signal choose(mode: String)  # "flight" | "training"
signal open_page(page: String)  # "saves" | "controls" | "options"
signal fly_again  # start the last Free-flight setup (start_screen runs the readiness check)
signal continue_lesson(id: String)  # start this lesson (the one after the last one flown)

const Card := preload("res://ui/menu/choice_card.gd")
const Tile := preload("res://ui/menu/home_tile.gd")
const LOGO := "res://branding/logo.png"
const MODES := [
	["flight", "Free flight", "Fly anywhere: pick the airport, aircraft, weather and failures.", "Press 1"],
	["training", "Training", "Guided lessons: take off, cruise and land, one step at a time.", "Press 2"],
]
## [icon, title, page, line under the title]; the Saved flights line is the newest save.
const MORE := [["save", "Saved flights", "saves", ""], ["pad", "Controls", "controls", "Keyboard, joystick, gamepad"],
	["gear", "Options", "options", "Sound, graphics, units"]]
const MIN_K := 0.5
const MAX_K := 1.4
const MARGIN_X := 56.0  # the start screen's side margins (start_screen.gd)
const CARDS_W := 884.0  # two cards (410) + their gap (24) + a little air
const HINT := "Left / Right or 1 / 2 to choose  ·  Enter to confirm"

var _cards: Array[Button] = []
var _logo: TextureRect
var _title: Label
var _sub: Label
var _question: Label
var _hint: Label
var _more: Array[Button] = []
## Controls outside the home screen that belong to its Tab ring (the top bar's Handbook / Credits / Quit, set by start_screen.gd):
## Tab continues from the last quiet link into them and Shift+Tab from the first card goes back to them.
var outer: Array[Control] = []
var _next_lesson := {}  # the lesson "Continue" starts, {} = no shortcut


func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	var brand := HBoxContainer.new()  # logo beside the name
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 18)
	add_child(brand)
	if ResourceLoader.exists(LOGO):
		_logo = TextureRect.new()
		_logo.texture = load(LOGO)
		_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		brand.add_child(_logo)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	brand.add_child(names)
	_title = _label("libresim", Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_title.add_theme_font_override("font", MenuTheme.font("semibold"))
	names.add_child(_title)
	_sub = _label("Mumbai – Kochi · Western Ghats", Color("d7dfeb"), HORIZONTAL_ALIGNMENT_LEFT)
	names.add_child(_sub)
	add_child(_gap(8))
	_question = _label("What would you like to do?", MenuTheme.TEXT)
	_question.add_theme_font_override("font", MenuTheme.font("medium"))
	add_child(_question)
	add_child(_gap(4))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	for m in MODES:
		var c: Button = Card.new()
		c.setup(m[0], m[1], m[2], m[3])
		c.pressed.connect(func(): choose.emit(m[0]))
		row.add_child(c)
		_cards.append(c)
	_cards[0].action_btn.pressed.connect(_on_fly_again)
	_cards[1].action_btn.pressed.connect(_on_continue)
	add_child(_gap(4))
	var more := HBoxContainer.new()
	more.alignment = BoxContainer.ALIGNMENT_CENTER
	more.add_theme_constant_override("separation", 12)
	add_child(more)
	for item in MORE:
		var t: Button = Tile.new()
		t.setup(item[0], item[1], item[3])
		t.pressed.connect(func(): open_page.emit(item[2]))
		more.add_child(t)
		_more.append(t)
	_hint = _label(HINT, Color(MenuTheme.TEXT, 0.8))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)
	get_viewport().size_changed.connect(_apply_scale)
	refresh()
	_apply_scale()


## Read the history again and show or hide the shortcuts (on every visit: a flight or lesson changes it).
func refresh() -> void:
	var last := HomeShortcuts.last_flight()
	var info := HomeShortcuts.fly_again_info(last)
	var fc: Button = _cards[0]
	fc.set_last("Last flight", info.get("title", ""), info.get("detail", ""))
	fc.set_action("Fly again  (R)" if not info.is_empty() else "", false, "Start the last flight again, straight away (key R)")
	var stars := TrainingLogic.load_stars()
	var list := HomeShortcuts.lessons(str(last.get("aircraft", Session.setup.get("aircraft", AircraftDef.DEFAULT_ID))))
	var prog := HomeShortcuts.progress_info(list, stars)
	_next_lesson = HomeShortcuts.next_lesson(list, stars)
	var tc: Button = _cards[1]
	tc.set_last(prog.get("detail", ""), prog.get("title", ""))
	tc.set_marks(HomeShortcuts.lesson_marks(list, stars) if not prog.is_empty() else [])
	tc.set_action("Continue: %s  (C)" % _next_lesson.title if not _next_lesson.is_empty() else "", true, "Start the next lesson (key C)")
	_more[0].set_sub(HomeShortcuts.saves_line(Situation.list_saves()))
	_hint.text = HINT + ("  ·  R fly again" if fc.action_btn.visible else "") + ("  ·  C continue" if tc.action_btn.visible else "")
	_link_focus()
	_apply_scale()


## Arrow keys and Tab: Left / Right between the cards (the default geometric search would jump to the
## small buttons below), Down to the card's shortcut, then the quiet links; Up goes back the same way.
func _link_focus() -> void:
	var n := _more.size()
	var sc: Array[Button] = []  # shortcuts that are shown, in card order
	for c in _cards:
		if c.action_btn.visible:
			sc.append(c.action_btn)
	var order: Array[Control] = []
	order.append_array(_cards)
	order.append_array(sc)
	order.append_array(_more)
	order.append_array(outer)
	for i in order.size():
		order[i].focus_next = order[i].get_path_to(order[(i + 1) % order.size()])
		order[i].focus_previous = order[i].get_path_to(order[(i - 1 + order.size()) % order.size()])
	for i in _cards.size():
		var c: Button = _cards[i]
		var low: Control = c.action_btn if c.action_btn.visible else _more[0 if i == 0 else n - 1]
		c.focus_neighbor_left = c.get_path_to(_cards[maxi(i - 1, 0)])
		c.focus_neighbor_right = c.get_path_to(_cards[mini(i + 1, _cards.size() - 1)])
		c.focus_neighbor_top = c.get_path_to(c)
		c.focus_neighbor_bottom = c.get_path_to(low)
		var s: Button = c.action_btn
		var side := sc.find(s)
		s.focus_neighbor_left = s.get_path_to(sc[maxi(side - 1, 0)] if side >= 0 else s)
		s.focus_neighbor_right = s.get_path_to(sc[mini(side + 1, sc.size() - 1)] if side >= 0 else s)
		s.focus_neighbor_top = s.get_path_to(c)
		s.focus_neighbor_bottom = s.get_path_to(_more[0 if i == 0 else n - 1])
	for i in n:
		var b := _more[i]
		var up: Control = _cards[1 if i == n - 1 else 0]
		if up.action_btn.visible:
			up = up.action_btn
		b.focus_neighbor_left = b.get_path_to(_more[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(_more[mini(i + 1, n - 1)])
		b.focus_neighbor_top = b.get_path_to(up)
		b.focus_neighbor_bottom = b.get_path_to(b)


func _label(text: String, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", col)
	return l


func _gap(h: float) -> Control:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	return g


## The home screen follows the room it has, in UI units (the window divided by the UI scale): 1.0 at 1280x720, up to
## 1.4 in a bigger window, and down to 0.5 when a large UI scale (125 to 200 %) or a small window leaves less than the
## design size, so the two cards and the three links always fit side by side instead of running off the screen.
## It reads the viewport size, which already is the window in UI units (UiScale).
func _apply_scale() -> void:
	var k := scale_for(get_viewport_rect().size)
	if _logo:
		_logo.custom_minimum_size = Vector2.ONE * 72.0 * k
	_title.add_theme_font_size_override("font_size", int(44 * k))
	_sub.add_theme_font_size_override("font_size", int(17 * k))
	_question.add_theme_font_size_override("font_size", int(26 * k))
	_hint.add_theme_font_size_override("font_size", int(14 * k))
	for c in _cards:
		c.set_scale_k(k)
	for b in _more:
		b.set_scale_k(k)
		b.custom_minimum_size.x = 236.0 * k


## The home screen's scale for a viewport of this many UI units: the height sets it (720 = 1.0), the width caps it so
## two cards (410 each) with their gap and the screen margins fit. Clamped to MIN_K .. MAX_K.
static func scale_for(units: Vector2) -> float:
	return clampf(minf(units.y / 720.0, (units.x - MARGIN_X) / CARDS_W), MIN_K, MAX_K)


## Called each time the home screen is shown: refresh the shortcuts, focus the card chosen last time.
func enter() -> void:
	refresh()
	var last: String = str(UserOptions.get_v("start_mode"))
	_cards[1 if last == "training" else 0].grab_focus()


func _pick(i: int) -> void:
	_cards[i].grab_focus()


func _on_fly_again() -> void:
	fly_again.emit()


func _on_continue() -> void:
	if not _next_lesson.is_empty():
		continue_lesson.emit(str(_next_lesson.id))


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.pressed or e.echo or e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		return
	match e.keycode:
		KEY_1, KEY_KP_1:
			_pick(0)
		KEY_2, KEY_KP_2:
			_pick(1)
		KEY_R:
			if not _cards[0].action_btn.visible:
				return
			_on_fly_again()
		KEY_C:
			if not _cards[1].action_btn.visible:
				return
			_on_continue()
		KEY_LEFT, KEY_RIGHT:
			if get_viewport().gui_get_focus_owner() == null:  # a focused card moves the focus itself
				_pick(0 if e.keycode == KEY_LEFT else 1)
		KEY_ENTER, KEY_KP_ENTER:
			if get_viewport().gui_get_focus_owner() == null:  # a focused button presses itself
				enter()
		_:
			return
	get_viewport().set_input_as_handled()
