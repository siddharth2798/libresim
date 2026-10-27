extends Control
## Esc: the full-screen pause screen, in the style of Microsoft Flight Simulator. The flight model
## pauses and the frozen 3D scene stays visible behind a blurred, dimmed backdrop (nothing is
## reloaded; resuming is instant). A big "PAUSED" title with a context line, a left column of
## big items and, on the right, the selected page embedded (ui/pause_pages.gd: Options, Weather &
## time, Controls & keys, Save / Load, Failures; the home page shows where the flight stands).
## Keys: arrows move (Left / Right also cross into a page), Enter selects, Esc backs out one level
## (text field, then page, then resume); every other key is swallowed so the flight hotkeys do
## nothing underneath. Props ui/pause_open tells the keyboard controls to ignore held keys.
## Restart, Quit to main menu and Quit game ask for a second click.

const Pages := preload("res://ui/pause_pages.gd")
const Summary := preload("res://ui/pause_summary.gd")
const BACKDROP := preload("res://ui/pause_backdrop.gdshader")
const Layout := preload("res://ui/pause_layout.gd")
const MENU := "res://ui/menu/start_screen.tscn"
const MAX_WIDTH := 1560.0  # UI units; a wider window centres the layout
const CONFIRM_S := 3.0
## Keys the menu itself uses; every other key is swallowed while it is open (modifiers are harmless).
const PASS_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_TAB,
		KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END, KEY_BACKSPACE, KEY_DELETE, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

var flight: Node  # world/flight.gd
var cur := "home"
var _nav := {}  # id -> Button
var _pages := {}  # id -> page root (built the first time it is shown)
var _host: MarginContainer
var _content: PanelContainer
var _margin: MarginContainer
var _title: Label
var _sub: Label
var _context: Label
var _esc_hint: Label
var _hidden: Array[CanvasItem] = []  # the HUD and other UI hidden while paused (they would show as a blurred ghost)
var _armed := ""
var _arm_serial := 0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP  # clicks never reach the HUD or the map underneath
	theme = MenuTheme.make()
	var bd := ColorRect.new()
	bd.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bd.mouse_filter = MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP
	bd.material = mat
	add_child(bd)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_margin.add_child(root)
	var head := Layout.header()
	_context = head.context
	root.add_child(head.root)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)
	var nav := Layout.nav_column(Pages.ITEMS, _on_nav, _on_nav_focus)
	_nav = nav.buttons
	body.add_child(nav.root)
	var panel := Layout.content_panel()
	_content = panel.root
	_title = panel.title
	_sub = panel.sub
	_host = panel.host
	body.add_child(panel.root)
	var foot := Layout.footer()
	_esc_hint = foot.esc_hint
	root.add_child(foot.root)
	resized.connect(_fit)
	_fit()
	_move_to_top.call_deferred()


## Side margins keep the layout at most MAX_WIDTH units wide on ultrawide windows.
func _fit() -> void:
	var side := maxf(24.0, (size.x - MAX_WIDTH) * 0.5)  # the pages need ~930 units beside the menu at 1280
	for s in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + s, int(side))
	_margin.add_theme_constant_override("margin_top", 26)
	_margin.add_theme_constant_override("margin_bottom", 22)


## Later siblings (the lesson card is added after this node) would draw over it.
func _move_to_top() -> void:
	if get_parent():
		get_parent().move_child(self, -1)


func open() -> void:
	if visible:
		return
	_move_to_top()
	for c in get_parent().get_children():
		if c is CanvasItem and c != self and c.visible:
			c.visible = false
			_hidden.append(c)
	visible = true
	flight.fdm_node.paused = true
	Props.set_v("ui/pause_open", true)
	_context.text = Summary.context(flight)
	show_page("home")
	_focus_nav("resume")


func close() -> void:
	if not visible:
		return
	_disarm()
	visible = false
	for c in _hidden:
		if is_instance_valid(c):
			c.visible = true
	_hidden.clear()
	flight.fdm_node.paused = false
	Props.set_v("ui/pause_open", false)
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.release_focus()


func _exit_tree() -> void:
	Props.set_v("ui/pause_open", false)


func show_page(id: String) -> void:
	if not _pages.has(id):
		var n := Pages.build(id, flight, self)
		_host.add_child(n)
		_pages[id] = n
		var p: Control = n.get_meta("page") if n.has_meta("page") else n
		if p.has_signal("closed"):  # a load from the saves page resumes the flight
			p.connect("closed", close)
	cur = id
	_content.size_flags_vertical = SIZE_SHRINK_BEGIN if id == "home" else SIZE_EXPAND_FILL  # home leaves the scene visible below
	for k in _pages:
		_pages[k].visible = k == id
	var it := Pages.item(id)
	_title.text = it.get("title", Pages.HOME_TITLE)
	_sub.text = it.get("sub", Pages.HOME_SUB)
	for k in _nav:
		if Pages.item(k).kind == "page":
			Layout.style_nav(_nav[k], k == id and k != _armed, false)
	_disarm()
	Pages.refresh(id, _pages[id], flight)
	_esc_hint.text = "Resume" if id == "home" else "Back"


func _focus_nav(id: String) -> void:
	if _nav.has(id):
		_nav[id].grab_focus()


func _on_nav_focus(id: String) -> void:
	if _armed != "" and _armed != id:
		_disarm()
	if Pages.item(id).kind == "page" and cur != id:  # arrowing down the column previews each page
		show_page(id)


func _on_nav(id: String) -> void:
	if Pages.item(id).kind == "page":
		show_page(id)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):  # Enter: go into the page
			_focus_into(_pages[id])
	else:
		_act(id)


## First focusable control inside `n` (depth first), so Enter on a menu item lands in its page.
func _focus_into(n: Node) -> bool:
	if n is Control and n.focus_mode == Control.FOCUS_ALL and n.is_visible_in_tree() \
			and not (n is BaseButton and n.disabled):
		n.grab_focus()
		return true
	for c in n.get_children():
		if _focus_into(c):
			return true
	return false


func _act(id: String) -> void:
	if Pages.item(id).get("confirm", false) and _armed != id:
		_arm(id)
		return
	_disarm()
	match id:
		"resume": close()
		"checklists":
			close()
			_press(KEY_F2)
		"replay":
			close()
			flight.get_node("Replay").start_replay(60.0)
		"restart":
			close()
			flight._reset()
		"menu":
			close()
			Session.skip_menu = false
			get_tree().change_scene_to_file(MENU)
		"quit": get_tree().quit()


func _arm(id: String) -> void:
	_disarm()
	_armed = id
	_arm_serial += 1
	var serial := _arm_serial
	_nav[id].text = "Click again to confirm"
	Layout.style_nav(_nav[id], false, true)
	get_tree().create_timer(CONFIRM_S).timeout.connect(func():
		if serial == _arm_serial:
			_disarm())


func _disarm() -> void:
	if _armed == "":
		return
	var b: Button = _nav[_armed]
	b.text = Pages.item(_armed).label
	Layout.style_nav(b, false, false)
	_armed = ""


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


## One level back: a text field gives up the focus, then a page returns to the home page, then the
## flight resumes. A pending "click again" is cancelled first.
func back() -> void:
	if _armed != "":
		_disarm()
	elif get_viewport().gui_get_focus_owner() is LineEdit:
		_focus_nav(cur if _nav.has(cur) else "resume")
	elif cur != "home":
		show_page("home")
		_focus_nav("resume")
	else:
		close()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## While open: Esc goes back, the keys the menu uses reach it, everything else is swallowed.
func _input(e: InputEvent) -> void:
	if not visible or not e is InputEventKey or not e.pressed:
		return
	var k: InputEventKey = e
	if k.keycode == KEY_ESCAPE:
		if not k.echo:
			back()
	elif k.keycode in PASS_KEYS or _typing():
		return
	get_viewport().set_input_as_handled()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		open()
		get_viewport().set_input_as_handled()
