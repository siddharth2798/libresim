extends Node
## Tabs (ui/menu/menu_tabs.gd) and the two pages built on them: Options (rail at the left) and Controls
## (tabs on top). Key rules, page switching, signals, and that every old setting still has a control that
## writes its key. Option values are changed in memory only (UserOptions does not save outside a real
## session) and restored; the Controls page uses a throw-away bindings file.

const BINDINGS := "user://test_menu_tabs_bindings.json"

var _opts := {}

const SWITCHES := {"Show the HUD overlay at start (H toggles in flight)": "hud_at_start", "Training callouts (K toggles in flight)": "callouts",
	"Speak them (system voice)": "callouts_voice", "Auto-coordination (rudder follows aileron)": "auto_coordination",
	"Radio assist (tunes COM1 for you, suggests the next call)": "radio_assist", "ATC voice (system text-to-speech)": "atc_voice",
	"Bloom (glow around bright lights)": "bloom"}


func teardown() -> void:
	for k in _opts:
		UserOptions.set_v(k, _opts[k])
	_opts = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BINDINGS))


func _tabs(rail := false, n := 3) -> MenuTabs:
	var t := MenuTabs.new().setup(rail)
	add_child(t)
	for i in n:
		var c := Control.new()
		t.add_tab("t%d" % i, "Tab %d" % i, c)
	return t


func _shown(t: MenuTabs) -> Array:
	return t.ids().filter(func(id): return t.page(id).visible)


func test_step_wraps_and_handles_unknown() -> String:
	if MenuTabs.step(0, 3, 1) != 1 or MenuTabs.step(2, 3, 1) != 0 or MenuTabs.step(0, 3, -1) != 2:
		return "step should wrap at both ends"
	if MenuTabs.step(-1, 3, 1) != 1 or MenuTabs.step(0, 0, 1) != 0:
		return "an unknown current counts as the first tab; no tabs gives 0"
	return ""


func test_key_rules() -> String:
	var K := MenuTabs.delta_for_key
	if K.call(KEY_LEFT, false, false, false) != -1 or K.call(KEY_RIGHT, false, false, true) != 1:
		return "Left / Right move on both layouts"
	if K.call(KEY_UP, false, false, false) != 0 or K.call(KEY_DOWN, false, false, false) != 0:
		return "Up / Down must not switch tabs on a row of tabs (they move focus)"
	if K.call(KEY_UP, false, false, true) != -1 or K.call(KEY_DOWN, false, false, true) != 1:
		return "Up / Down move on a rail"
	if K.call(KEY_TAB, true, false, false) != 1 or K.call(KEY_TAB, true, true, false) != -1:
		return "Ctrl+Tab forwards, Ctrl+Shift+Tab back"
	if K.call(KEY_TAB, false, false, false) != 0 or K.call(KEY_LEFT, true, false, false) != 0 or K.call(KEY_A, false, false, false) != 0:
		return "plain Tab, Ctrl+Left and letters are not tab keys"
	return ""


func test_first_tab_is_selected_and_only_its_page_shows() -> String:
	var t := _tabs()
	var err := ""
	if t.current() != "t0" or _shown(t) != ["t0"]:
		err = "the first tab should be selected alone: %s %s" % [t.current(), _shown(t)]
	elif not t.button("t0").button_pressed or t.button("t1").button_pressed:
		err = "the first tab button should be the pressed one"
	t.free()
	return err


func test_select_switches_page_and_emits_once() -> String:
	var t := _tabs()
	var got := []
	t.tab_changed.connect(func(id): got.append(id))
	t.select("t2")
	t.select("t2")  # same tab: no signal
	t.select("nope")  # unknown: ignored
	t.select("t1", false)  # silent
	var err := ""
	if got != ["t2"]:
		err = "tab_changed should fire once for t2, got %s" % [got]
	elif t.current() != "t1" or _shown(t) != ["t1"] or not t.button("t1").button_pressed:
		err = "select(emit=false) should still switch: %s %s" % [t.current(), _shown(t)]
	t.free()
	return err


func test_clicking_a_tab_button_selects_it() -> String:
	var t := _tabs(true)
	t.button("t2").pressed.emit()
	var ok := t.current() == "t2" and _shown(t) == ["t2"]
	t.free()
	return "" if ok else "a click on the tab should show its page"


func test_arrow_key_on_a_tab_moves_and_wraps() -> String:
	var t := _tabs(false)
	var e := InputEventKey.new()
	e.keycode = KEY_LEFT
	e.pressed = true
	t.button("t0").gui_input.emit(e)  # wraps to the last
	var wrapped := t.current()
	e.keycode = KEY_RIGHT
	t.button("t2").gui_input.emit(e)
	var back := t.current()
	t.free()
	return "" if wrapped == "t2" and back == "t0" else "Left from the first should wrap to the last (%s), Right back (%s)" % [wrapped, back]


func test_rail_layout_flag() -> String:
	var a := _tabs(true)
	var b := _tabs(false)
	var ok := not a.vertical and b.vertical and a.rail and not b.rail
	a.free()
	b.free()
	return "" if ok else "a rail puts the tabs left of the pages, a row puts them above"


func _options() -> Control:
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/options_page.gd"))
	add_child(p)
	return p


func test_options_tabs_and_one_call_sign_field() -> String:
	var p := _options()
	var ids: Array = p.tabs.ids()
	var calls := p.find_children("*", "CallsignField", true, false).size()
	var gfx: Array = p.tabs.page("graphics").find_children("*", "Button", true, false).map(func(b): return b.text)
	var fx := p.find_children("*", "PostFxToggles", true, false).size()
	p.free()
	if ids != ["sound", "graphics", "display", "controls", "radio", "aids"]:
		return "tabs: %s" % [ids]
	if calls != 1:
		return "exactly one call sign field on Options, got %d" % calls
	for pr in Graphics.ORDER:
		if not pr.capitalize() in gfx:
			return "preset %s missing from the Graphics tab" % pr
	return "" if fx == 1 else "the post effect switches belong to the Graphics tab"


func test_options_switches_and_choices_write_their_keys() -> String:
	for k in ["hud_at_start", "callouts", "callouts_voice", "auto_coordination", "radio_assist", "atc_voice", "alt_unit", "speed_unit", "pressure_unit", "keyboard_mode", "control_smoothing", "ui_scale", "bloom"]:
		_opts[k] = UserOptions.get_v(k)
	var p := _options()
	var err := ""
	var switches: Array = p.find_children("*", "SwitchRow", true, false)
	var by_title := {}
	for s in switches:
		by_title[s._title.text] = s
	for want in SWITCHES:
		var key: String = SWITCHES[want]
		if not by_title.has(want):
			err = "no switch '%s'" % want
			break
		var before := bool(UserOptions.get_v(key))
		by_title[want].toggled.emit(not before)
		if bool(UserOptions.get_v(key)) == before:
			err = "switch '%s' did not write %s" % [want, key]
			break
	if err == "":
		var segs: Array = p.find_children("*", "Segmented", true, false)
		var seen := []
		for s in segs:
			for key in ["alt_unit", "speed_unit", "pressure_unit", "keyboard_mode", "control_smoothing", "ui_scale"]:
				if s.get_value() == UserOptions.get_v(key) and s.button_of(UserOptions.CHOICES[key][-1]) != null and (s.button_of(UserOptions.CHOICES[key][0]) != null):
					seen.append(key)
					var other: Variant = UserOptions.CHOICES[key][-1] if UserOptions.get_v(key) != UserOptions.CHOICES[key][-1] else UserOptions.CHOICES[key][0]
					s.button_of(other).pressed.emit()
					if UserOptions.get_v(key) != other and key != "ui_scale":
						err = "choice %s did not write" % key
					break
		if err == "" and seen.size() < 6:
			err = "only found choices for %s" % [seen]
	p.free()
	return err


func _controls(extra := {}) -> Control:
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/controls_page.gd"))
	p.set("bindings_path", BINDINGS)
	for k in extra:
		p.set(k, extra[k])
	add_child(p)
	return p


func test_controls_tabs_and_start_tab() -> String:
	var p := _controls()
	var ids: Array = p.tabs.ids()
	var first: String = p.tabs.current()
	p.free()
	var j := _controls({"start_tab": "joystick"})
	var second: String = j.tabs.current()
	j.free()
	var bad := _controls({"start_tab": "nonsense"})
	var third: String = bad.tabs.current()
	bad.free()
	if ids != ["keyboard", "joystick", "other"]:
		return "tabs: %s" % [ids]
	return "" if first == "keyboard" and second == "joystick" and third == "keyboard" else "start tabs: %s %s %s" % [first, second, third]


func test_controls_keyboard_joystick_and_reference_stay_reachable() -> String:
	var p := _controls()
	var slots: Dictionary = p.keys.get("_slots")
	var rows: Dictionary = p.get("_rows")
	var ref: int = p.tabs.page("other").find_children("*", "GridContainer", true, false).size()
	var ok_k: bool = slots.has("pitch_up") and slots.has("throttle_up")
	var ok_j: bool = rows.has("throttle") and rows.has("pitch") or rows.size() > 5
	var ok_page: bool = p.tabs.page("keyboard") == p.keys
	p.free()
	if not ok_k or not ok_page:
		return "keyboard tab should hold the key slots"
	if not ok_j:
		return "joystick tab should hold the axis and button rows"
	return "" if ref >= 1 else "other keys tab should hold the hotkey reference"


func test_controls_tune_line_opens_for_an_inverted_axis() -> String:
	var p := _controls()
	var row = p.get("_rows")["roll"] if p.get("_rows").has("roll") else null
	if row == null:
		p.free()
		return "no roll axis row to test"
	var has_tune: bool = row.tune != null
	row.b["deadzone"] = 0.0
	row.b["invert"] = false
	row.b["range"] = "full"
	var plain: bool = row._is_tuned()
	row.b["deadzone"] = 0.07
	var dz_only: bool = row._is_tuned()
	row._edit("invert", true)  # edits the dictionary and saves to the test file
	var inv: bool = bool(row.b.invert)
	var tuned: bool = row._is_tuned() and not dz_only
	p.free()
	if plain or not tuned or not inv or not has_tune:
		return "tune state: plain %s tuned %s invert %s" % [plain, tuned, inv]
	return ""


func test_controls_capture_is_cancelled_by_switching_tab() -> String:
	var p := _controls({"start_tab": "joystick"})
	p._start_capture("throttle")
	var waiting: bool = p.get("_capture") == "throttle"
	p.tabs.select("keyboard")
	var cleared: bool = p.get("_capture") == ""
	p.free()
	return "" if waiting and cleared else "leaving the joystick tab should cancel a binding capture"


func test_long_names_are_clipped_with_an_ellipsis_and_a_tooltip() -> String:
	var p := _controls({"controls": AircraftControls.default_set()})
	var err := ""
	var rows: Dictionary = p.get("_rows")
	var any_row: Control = rows.values()[0]
	var name_lbl: Label = any_row.get_child(0).get_child(0)
	if not name_lbl.clip_text or name_lbl.text_overrun_behavior != TextServer.OVERRUN_TRIM_ELLIPSIS or name_lbl.tooltip_text != name_lbl.text:
		err = "the name column should clip with an ellipsis and carry the full name as tooltip"
	var kl: Label = p.keys.get("_grid").get_child(0).get_child(0)
	if err == "" and (not kl.clip_text or kl.tooltip_text != kl.text):
		err = "key rows: same rule"
	p.free()
	return err
