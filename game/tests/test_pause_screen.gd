extends Node
## Full-screen pause (ui/pause_menu.gd): open / close state, Esc levels, key swallowing, the
## "click again" confirm, the page list and that the embedded panels build in embedded mode.
## Built headless without frames, so layout is checked by screenshots (tests/showcase_scenes.gd
## "pause_*"), not here.

const Pause := preload("res://ui/pause_menu.gd")
const Pages := preload("res://ui/pause_pages.gd")


class StubFdm extends Node:
	var paused := false
	var replaying := false


class StubFlight extends Node:
	var fdm_node := StubFdm.new()
	var _apt := "VAJJ"


func _make() -> Control:
	var f := StubFlight.new()
	f.add_child(f.fdm_node)
	add_child(f)
	var p := Control.new()
	p.set_script(Pause)
	p.set("flight", f)
	f.add_child(p)
	return p


func _free(p: Control) -> void:
	p.get_parent().free()


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_open_pauses_and_close_resumes() -> String:
	var p := _make()
	var f: Node = p.get("flight")
	var err := ""
	p.open()
	if not p.visible or not f.fdm_node.paused or not Props.get_b("ui/pause_open"):
		err = "open should show the screen, pause the flight and set ui/pause_open"
	elif p.cur != "home" or get_viewport().gui_get_focus_owner() != p._nav["resume"]:
		err = "it should open on the home page with Resume focused"
	p.close()
	if err == "" and (p.visible or f.fdm_node.paused or Props.get_b("ui/pause_open")):
		err = "close should hide it, resume the flight and clear ui/pause_open"
	_free(p)
	return err


func test_esc_backs_out_one_level_then_resumes() -> String:
	var p := _make()
	var err := ""
	p.open()
	p.show_page("options")
	p._input(_key(KEY_ESCAPE))
	if not p.visible or p.cur != "home":
		err = "Esc on a page should return to the home page, still paused (cur=%s, visible=%s)" % [p.cur, p.visible]
	p._input(_key(KEY_ESCAPE))
	if err == "" and p.visible:
		err = "Esc on the home page should resume"
	_free(p)
	return err


func test_esc_cancels_a_pending_confirm_first() -> String:
	var p := _make()
	var err := ""
	p.open()
	p._act("quit")  # first click only arms it; the game must still be running (this test is running)
	if p._armed != "quit" or p._nav["quit"].text == "Quit game":
		err = "Quit game should ask for a second click"
	p._input(_key(KEY_ESCAPE))
	if err == "" and (p._armed != "" or p._nav["quit"].text != "Quit game" or not p.visible):
		err = "Esc should only cancel the confirmation"
	_free(p)
	return err


func test_other_keys_are_swallowed_but_navigation_keys_pass() -> String:
	var p := _make()
	var err := ""
	p.open()
	for code in [KEY_C, KEY_F9, KEY_F10, KEY_J, KEY_QUOTELEFT, KEY_N]:
		get_viewport().push_input(_key(KEY_SHIFT))  # clears the handled flag
		p._input(_key(code))
		if not get_viewport().is_input_handled():
			err = "key %s should be swallowed while paused" % OS.get_keycode_string(code)
	for code in [KEY_DOWN, KEY_UP, KEY_ENTER, KEY_LEFT, KEY_RIGHT, KEY_TAB]:
		get_viewport().push_input(_key(KEY_SHIFT))  # clears the handled flag
		p._input(_key(code))
		if get_viewport().is_input_handled():
			err = "navigation key %s must reach the menu" % OS.get_keycode_string(code)
	p.close()
	p._input(_key(KEY_C))  # closed: nothing is swallowed
	_free(p)
	return err


func test_held_keys_do_not_fly_the_aircraft_while_paused() -> String:
	var k := KeyboardControls.new()
	add_child(k)
	Props.set_v("ui/pause_open", true)
	var held := k._k("pitch_up")
	Props.set_v("ui/pause_open", false)
	k.free()
	return "" if not held else "held keys must count for nothing while the pause screen is open"


func test_every_item_is_well_formed() -> String:
	var ids := {}
	for it in Pages.ITEMS:
		if it.has("sep"):
			continue
		if ids.has(it.id):
			return "duplicate item " + it.id
		ids[it.id] = true
		if it.kind == "page" and (not it.has("title") or not it.has("sub")):
			return "page item %s needs a title and a sub-title" % it.id
		if it.kind == "page" and not ["failures", "saves"].has(it.id):  # those two need the flight scene
			var n := Pages.build(it.id, null, null)
			if n == null:
				return "page %s does not build" % it.id
			n.free()
	return "" if ids.has("resume") and ids.has("quit") and ids.has("menu") else "Resume, Quit to menu and Quit game must be there"


func test_pages_are_built_once_and_only_the_current_one_shows() -> String:
	var p := _make()
	var err := ""
	p.open()
	p.show_page("options")
	p.show_page("controls")
	p.show_page("options")
	if p._pages.size() != 3:  # home, options, controls
		err = "expected 3 built pages, got %s" % [p._pages.keys()]
	else:
		for k in p._pages:
			if p._pages[k].visible != (k == "options"):
				err = "page %s visibility is wrong" % k
	p.close()
	_free(p)
	return err


func test_embedded_panels_have_no_hotkeys_and_stay_shown() -> String:
	for path in ["res://ui/settings_menu.gd", "res://ui/failures_panel.gd"]:
		var c := PanelContainer.new()
		c.set_script(load(path))
		c.set("embedded", true)
		add_child(c)
		var shown: bool = c.visible
		var e := InputEventKey.new()
		e.keycode = KEY_F10 if path.contains("settings") else KEY_F9
		e.pressed = true
		c._unhandled_key_input(e)
		var still: bool = c.visible
		c.free()
		if not shown or not still:
			return "%s: an embedded panel must stay visible and ignore its hotkey" % path
	return ""


func test_context_line_names_aircraft_airport_and_time() -> String:
	var p := _make()
	var s: String = load("res://ui/pause_summary.gd").context(p.get("flight"))
	_free(p)
	for need in ["Cessna 172", "VAJJ", "IST"]:
		if not s.contains(need):
			return "context line '%s' lacks '%s'" % [s, need]
	return ""
