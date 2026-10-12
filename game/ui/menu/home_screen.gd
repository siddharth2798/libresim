extends VBoxContainer
## Start screen, first page: one question, "What would you like to do?", and two large
## cards: Free flight or Training. Saved flights, Controls and Options sit quietly below.
## Left / Right or 1 / 2 pick a card, Enter confirms; the last choice is remembered
## (UserOptions start_mode) and focused next time.

signal choose(mode: String)  # "flight" | "training"
signal open_page(page: String)  # "saves" | "controls" | "options"

const Card := preload("res://ui/menu/choice_card.gd")
const LOGO := "res://branding/logo.png"
const MODES := [
	["flight", "Free flight", "Fly anywhere: pick the airport, aircraft, weather and failures.", "Press 1"],
	["training", "Training", "Guided lessons: take off, cruise and land, one step at a time.", "Press 2"],
]
const MORE := [["Saved flights", "saves"], ["Controls", "controls"], ["Options", "options"]]

var _cards: Array[Button] = []
var _logo: TextureRect
var _title: Label
var _sub: Label
var _question: Label
var _hint: Label
var _more: Array[Button] = []


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
	names.add_child(_title)
	_sub = _label("Mumbai – Kochi · Western Ghats", MenuTheme.DIM, HORIZONTAL_ALIGNMENT_LEFT)
	names.add_child(_sub)
	add_child(_gap(16))
	_question = _label("What would you like to do?", MenuTheme.TEXT)
	add_child(_question)
	add_child(_gap(10))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 32)
	add_child(row)
	for m in MODES:
		var c: Button = Card.new()
		c.setup(m[0], m[1], m[2], m[3])
		c.pressed.connect(func(): choose.emit(m[0]))
		row.add_child(c)
		_cards.append(c)
	add_child(_gap(10))
	var more := HBoxContainer.new()
	more.alignment = BoxContainer.ALIGNMENT_CENTER
	more.add_theme_constant_override("separation", 12)
	add_child(more)
	for item in MORE:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(150, 38)
		b.add_theme_font_size_override("font_size", 16)
		MenuTheme.style_quiet(b)
		b.pressed.connect(func(): open_page.emit(item[1]))
		more.add_child(b)
		_more.append(b)
	_hint = _label("Left / Right or 1 / 2 to choose  ·  Enter to confirm", Color(MenuTheme.TEXT, 0.75))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(_hint)
	_link_focus()
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale()


## Arrow keys: Left / Right between the two cards (the default geometric search would jump
## to the small buttons below), Down to the small buttons, Up back to a card.
func _link_focus() -> void:
	var n := _more.size()
	for i in _cards.size():
		var c := _cards[i]
		c.focus_neighbor_left = c.get_path_to(_cards[maxi(i - 1, 0)])
		c.focus_neighbor_right = c.get_path_to(_cards[mini(i + 1, _cards.size() - 1)])
		c.focus_neighbor_top = c.get_path_to(c)
		c.focus_neighbor_bottom = c.get_path_to(_more[0 if i == 0 else n - 1])
	for i in n:
		var b := _more[i]
		b.focus_neighbor_left = b.get_path_to(_more[maxi(i - 1, 0)])
		b.focus_neighbor_right = b.get_path_to(_more[mini(i + 1, n - 1)])
		b.focus_neighbor_top = b.get_path_to(_cards[1 if i == n - 1 else 0])
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


## Bigger window, bigger home screen (1.0 at 1280x720, at most 1.4).
func _apply_scale() -> void:
	var k := clampf(get_viewport_rect().size.y / 720.0, 1.0, 1.4)
	if _logo:
		_logo.custom_minimum_size = Vector2.ONE * 84.0 * k
	_title.add_theme_font_size_override("font_size", int(46 * k))
	_sub.add_theme_font_size_override("font_size", int(18 * k))
	_question.add_theme_font_size_override("font_size", int(26 * k))
	_hint.add_theme_font_size_override("font_size", int(14 * k))
	for c in _cards:
		c.set_scale_k(k)
	for b in _more:
		b.custom_minimum_size = Vector2(150, 38) * k


## Called each time the home screen is shown: focus the card chosen last time.
func enter() -> void:
	var last: String = str(UserOptions.get_v("start_mode"))
	_cards[1 if last == "training" else 0].grab_focus()


func _pick(i: int) -> void:
	_cards[i].grab_focus()


func _unhandled_key_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not e.pressed or e.echo:
		return
	match e.keycode:
		KEY_1, KEY_KP_1:
			_pick(0)
		KEY_2, KEY_KP_2:
			_pick(1)
		KEY_LEFT, KEY_RIGHT:
			if get_viewport().gui_get_focus_owner() == null:  # a focused card moves the focus itself
				_pick(0 if e.keycode == KEY_LEFT else 1)
		KEY_ENTER, KEY_KP_ENTER:
			if get_viewport().gui_get_focus_owner() == null:  # a focused button presses itself
				enter()
		_:
			return
	get_viewport().set_input_as_handled()
