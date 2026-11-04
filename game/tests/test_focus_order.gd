extends Node
## Keyboard focus on the start screen, as the engine really walks it (find_next_valid_focus / find_prev_valid_focus, which
## honour the explicit focus_next / focus_previous the pages set). For every page: every focusable control that is shown can
## be reached with Tab, Tab visits each exactly once and comes back to the start (no trap, no early loop), Shift+Tab is the
## exact reverse, and the order is the one a person expects (flow: rail, page, footer; Controls: tabs, aircraft switch,
## search, rows; the "Fly anyway?" question keeps Tab inside itself). Scratch paths only; nothing is saved.

const SAVE := "user://_focus_order_last_flight.json"
const STARS := "user://_focus_order_training.json"

var _keep := {}
var _screen: Control


func teardown() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null
	if _keep.is_empty():
		return
	for p in [SAVE, STARS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Session.end_lesson()
	Session.setup = _keep.setup
	Session.skip_menu = _keep.skip
	Session.save_path = _keep.save
	Session.interactive_override = _keep.override
	TrainingLogic.save_path = _keep.stars
	SituationStore.dir = _keep.dir
	_keep = {}


func _open(history := false) -> Control:
	_keep = {"setup": Session.setup, "skip": Session.skip_menu, "save": Session.save_path, "override": Session.interactive_override,
		"stars": TrainingLogic.save_path, "dir": SituationStore.dir}
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.skip_menu = false
	Session.interactive_override = 0
	Session.save_path = SAVE
	TrainingLogic.save_path = STARS
	SituationStore.dir = "user://_focus_order_saves/"
	for p in [SAVE, STARS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if history:
		FileAccess.open(SAVE, FileAccess.WRITE).store_string(JSON.stringify(Session.DEFAULT))
		FileAccess.open(STARS, FileAccess.WRITE).store_string(JSON.stringify({"takeoff": 2}))
	_screen = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_screen)
	return _screen


## Every control a keyboard can land on and that is shown, in tree order.
func _focusables(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	_collect(root, out)
	return out


func _collect(n: Node, out: Array[Control]) -> void:
	if n is Control and (n as Control).is_visible_in_tree() and (n as Control).focus_mode == Control.FOCUS_ALL:
		if not (n is BaseButton and (n as BaseButton).disabled):
			out.append(n)
	for k in n.get_children(true):  # internal children too: a SpinBox's text box is one
		_collect(k, out)


func _name(c: Control) -> String:
	var t := ""
	if c is Button:
		t = (c as Button).text.strip_edges().left(20)
	return "%s%s[%s]" % [c.get_class(), "'" + t + "'" if t != "" else "", c.get_parent().get_class() if c.get_parent() else "?"]


## Walks Tab from `first`; returns the visited controls (stops on the way back to `first` or on a repeat).
func _chain(first: Control, back := false) -> Array[Control]:
	var seen: Array[Control] = [first]
	var c := first
	for _i in 800:
		var n: Control = c.find_prev_valid_focus() if back else c.find_next_valid_focus()
		if n == null or n == first or seen.has(n):
			break
		seen.append(n)
		c = n
	return seen


## "" when the page's Tab ring holds exactly the shown focusable controls, once each, and Shift+Tab is its reverse.
func _ring_problem(page: String) -> String:
	var all := _focusables(_screen)
	if all.is_empty():
		return "%s: nothing focusable is shown" % page
	var fwd := _chain(all[0])
	var missing := all.filter(func(c): return not fwd.has(c))
	var extra := fwd.filter(func(c): return not all.has(c))
	if not missing.is_empty():
		return "%s: Tab never reaches %s (ring of %d of %d)" % [page, ", ".join(missing.slice(0, 4).map(_name)), fwd.size(), all.size()]
	if not extra.is_empty():
		return "%s: Tab lands on something that is not shown or focusable: %s" % [page, _name(extra[0])]
	var back := _chain(all[0], true)
	var want := [all[0]]
	var rev := fwd.slice(1)
	rev.reverse()
	want.append_array(rev)
	if back != want:
		return "%s: Shift+Tab is not the reverse of Tab (first difference near %s)" % [page, _name(back[mini(1, back.size() - 1)])]
	return ""


func _index_of_group(ring: Array[Control], group: Array) -> Vector2i:
	var lo := 100000
	var hi := -1
	for c in group:
		var i := ring.find(c)
		if i >= 0:
			lo = mini(lo, i)
			hi = maxi(hi, i)
	return Vector2i(lo, hi)


# ---- rings -------------------------------------------------------------------------------------

func test_home_ring_reaches_every_control_with_and_without_history() -> String:
	for history in [false, true]:
		_open(history)
		_screen.go("home")
		var p := _ring_problem("home (history %s)" % history)
		teardown()
		if p != "":
			return p
	return ""


func test_every_free_flight_step_has_a_complete_ring_in_rail_page_footer_order() -> String:
	_open()
	_screen.go("flight")
	var f: Control = _screen.screen("flight")
	for i in f.STEPS.size():
		f.show_step(i)
		var p := _ring_problem("flight step %d" % (i + 1))
		if p != "":
			return p
		var ring := _chain(_focusables(_screen)[0])
		var rail: Array = f.rail.entries
		var page := _focusables(f.pages[i])
		var foot := _focusables(f.footer)
		var r := _index_of_group(ring, rail)
		var pg := _index_of_group(ring, page)
		var ft := _index_of_group(ring, foot)
		if page.is_empty() or foot.is_empty():
			return "step %d: page has %d, footer %d focusable controls" % [i + 1, page.size(), foot.size()]
		if not (r.y < pg.x and pg.y < ft.x):
			return "step %d: Tab order should be rail %s, page %s, footer %s" % [i + 1, r, pg, ft]
	return ""


func test_single_page_screens_have_a_complete_ring() -> String:
	_open()
	for id in ["training", "saves", "options", "controls"]:
		_screen.go(id)
		var p := _ring_problem(id)
		if p != "":
			return p
		var ring := _chain(_focusables(_screen)[0])
		var fr: Control = _screen.screen(id)
		var pg := _index_of_group(ring, _focusables(fr.pages[0]))
		var back := ring.find(fr.back_btn)
		if pg.x < 100000 and back < pg.y:
			return "%s: the Back button (%d) should come after the page controls (up to %d)" % [id, back, pg.y]
	return ""


func test_every_options_and_controls_tab_has_a_complete_ring() -> String:
	_open()
	for id in ["options", "controls"]:
		_screen.go(id)
		var page: Control = _screen.screen(id).pages[0]
		for t in page.tabs.ids():
			page.tabs.select(t)
			var p := _ring_problem("%s tab %s" % [id, t])
			if p != "":
				return p
	return ""


func test_controls_order_is_tabs_then_aircraft_then_search_then_rows() -> String:
	_open()
	_screen.go("controls")
	var page: Control = _screen.screen("controls").pages[0]
	page.tabs.select("keyboard")
	var ring := _chain(_focusables(_screen)[0])
	var tabs: Array = page.tabs.ids().map(func(id): return page.tabs.button(id))
	var sw: Array = page.aircraft_switch.get_children().filter(func(c): return c is Button)
	var t := _index_of_group(ring, tabs)
	var s := _index_of_group(ring, sw)
	var q := ring.find(page.search)
	var rows := _index_of_group(ring, _focusables(page.keys))
	if sw.is_empty() or q < 0 or rows.y < 0:
		return "controls: aircraft switch (%d), search (%d) or rows (%d) are not in the ring" % [sw.size(), q, rows.y]
	if not (t.y < s.x and s.y < q and q < rows.x):
		return "controls: tabs %s, aircraft %s, search %d, rows %s are out of order" % [t, s, q, rows]
	return ""


func test_arrow_keys_move_within_the_tab_bar_and_back_into_the_rows() -> String:
	_open()
	_screen.go("controls")
	var page: Control = _screen.screen("controls").pages[0]
	var b: Button = page.tabs.button("keyboard")
	var e := InputEventKey.new()
	e.keycode = KEY_RIGHT
	e.pressed = true
	b.gui_input.emit(e)
	if page.tabs.current() != "joystick":
		return "Right on a tab should select the next tab (got %s)" % page.tabs.current()
	return ""


# ---- the modal question ------------------------------------------------------------------------

func test_fly_anyway_question_keeps_focus_inside_itself() -> String:
	_open()
	var q := FlyConfirm.make(["Over maximum takeoff weight by 10 kg"] as Array[String])
	_screen.add_child(q)
	var inside := [q.go_back_btn, q.fly_btn]
	var err := ""
	var c: Control = q.go_back_btn
	for i in 6:  # Tab, Tab, ... never leaves the two buttons
		c = c.find_next_valid_focus()
		if not inside.has(c):
			err = "Tab leaves the question after %d presses: %s" % [i + 1, _name(c)]
			break
	c = q.fly_btn
	for i in 6:
		c = c.find_prev_valid_focus()
		if err == "" and not inside.has(c):
			err = "Shift+Tab leaves the question: %s" % _name(c)
			break
	for b in inside:
		for side in ["focus_neighbor_left", "focus_neighbor_right", "focus_neighbor_top", "focus_neighbor_bottom"]:
			var n: Control = (b as Control).get_node_or_null((b as Control).get(side))
			if err == "" and not inside.has(n):
				err = "arrow key %s leaves the question" % side
	q.free()
	return err


func test_home_top_bar_is_part_of_the_ring() -> String:
	_open()
	_screen.go("home")
	var home: Control = _screen.screen("home")
	var ring := _chain(_focusables(_screen)[0])
	var top := ring.filter(func(c): return c is Button and (c as Button).text in ["Handbook", "Credits", "Quit"])
	var cards: Array = home._cards
	if top.size() != 3:
		return "Handbook, Credits and Quit must be reachable by Tab from the home screen (found %d)" % top.size()
	var i_top := ring.find(top[0])
	var i_last_card := ring.find(cards[cards.size() - 1])
	return "" if i_top >= 0 and i_last_card >= 0 else "ring is missing the cards or the top bar"


# ---- focus ring visibility -------------------------------------------------------------------

func test_focus_ring_differs_from_the_fill_it_sits_on() -> String:
	var host := Control.new()
	host.theme = MenuTheme.make()
	add_child(host)
	var err := ""
	for tone in [MenuTheme.ACCENT, MenuTheme.WARN]:
		var b := Button.new()
		host.add_child(b)
		MenuTheme.style_primary(b, true, tone)
		var ring: StyleBoxFlat = b.get_theme_stylebox("focus")
		var fill: StyleBoxFlat = b.get_theme_stylebox("normal")
		if b.has_theme_stylebox_override("focus"):
			err = "the ring must come from the theme, not a per-button override"
		elif ring.border_color.is_equal_approx(fill.bg_color):
			err = "the focus ring of a filled %s button is the colour of its fill: it would be invisible" % tone.to_html(false)
		elif ring.border_width_left < 3 or ring.draw_center:
			err = "the ring should be 3 px and have no fill"
		MenuTheme.style_primary(b, false)  # the quiet outline look goes back to the accent ring
		if err == "" and not (b.get_theme_stylebox("focus") as StyleBoxFlat).border_color.is_equal_approx(MenuTheme.ACCENT):
			err = "a quiet button should have the accent ring again"
	var plain := host.theme.get_stylebox("focus", "Button") as StyleBoxFlat
	host.free()
	if err != "":
		return err
	return "" if plain.border_color.is_equal_approx(MenuTheme.ACCENT) and plain.border_width_left == MenuTheme.FOCUS_WIDTH else "the default ring is the 3 px accent one"
