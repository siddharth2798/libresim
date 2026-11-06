extends Node
## The first-time live weather question is a menu panel on the screen that hosts it, not a window dialog.
## A window dialog ignores the UI scale, so it looked zoomed in and sat in the wrong place.

const SCRATCH := "user://live_weather_notice_test"


func modal_open() -> bool:
	return false


func teardown() -> void:
	var n := get_node_or_null("LiveWeatherNotice")
	if n != null:
		n.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func test_live_weather_notice_is_a_menu_panel() -> String:
	var m := LiveWeatherNotice.new()
	add_child(m)
	var got := []
	m.accepted.connect(func(): got.append("accepted"))
	m.declined.connect(func(): got.append("declined"))
	var err := ""
	if m.anchor_right < 0.99 or m.anchor_bottom < 0.99:
		err = "the panel should cover the screen"
	elif m.not_now_btn.text != "Not now" or m.use_btn.text != "Use live weather":
		err = "buttons: %s / %s" % [m.not_now_btn.text, m.use_btn.text]
	elif not LiveWeatherNotice.BODY.contains("aviationweather.gov"):
		err = "the explanation is missing"
	else:
		var e := InputEventKey.new()
		e.keycode = KEY_ESCAPE
		e.pressed = true
		m._input(e)
		m.use_btn.pressed.emit()
		if got != ["declined"]:
			err = "Esc declines, and a second answer is ignored: %s" % [got]
	m.free()
	return err


func test_live_weather_first_toggle_asks_on_the_screen() -> String:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	var bar := LiveWeatherBar.new()
	bar.seen_path = SCRATCH
	add_child(bar)
	bar._live.set_pressed(true)
	var n := get_node_or_null("LiveWeatherNotice")
	var err := ""
	if n == null or not (n is Control):
		err = "the first toggle should open a panel on the screen"
	elif bar._screen() != self:
		err = "the panel should be parented to the menu, not the small weather bar"
	else:
		n.not_now_btn.pressed.emit()
		var left := get_node_or_null("LiveWeatherNotice")
		if bar._live.button_pressed or bool(Session.setup.get("live_weather", false)):
			err = "Not now leaves live weather off"
		elif left != null and not left.is_queued_for_deletion():
			err = "Not now should close the panel"
	bar.free()
	return err


func test_start_screen_counts_the_live_weather_panel_as_a_modal() -> String:
	var was := Session.skip_menu
	Session.skip_menu = false
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	var err := ""
	if s.modal_open():
		err = "nothing is open yet"
	else:
		var m := LiveWeatherNotice.new()
		s.add_child(m)
		if not s.modal_open():
			err = "the live weather panel should block other prompts"
		m.free()
	s.free()
	Session.skip_menu = was
	return err
