extends RefCounted
## What the pause screen (ui/pause_menu.gd) lists: ITEMS is the left column, in order, and build()
## makes the content page of a "page" item the first time it is shown. The pages are the existing
## ones: the start screen's Options and Controls pages, and the in-flight Weather & time (F10),
## Failures (F9) and Saved flights panels in their embedded mode (no frame, no hotkey).
## kind: "page" shows content on the right; "action" does something (confirm: click twice).

const ITEMS := [
	{"id": "resume", "label": "Resume flight", "key": "Esc", "kind": "action"},
	{"id": "options", "label": "Options", "kind": "page", "title": "Options",
		"sub": "Sound, graphics, units, display size and flight-control feel. Saved as you change them."},
	{"id": "settings", "label": "Weather & time", "key": "F10", "kind": "page", "title": "Weather & time",
		"sub": "Graphics preset, time of day, wind, visibility, clouds and pressure. Changes apply when you resume."},
	{"id": "controls", "label": "Controls & keys", "key": "J", "kind": "page", "title": "Controls & key bindings",
		"sub": "Joystick, gamepad and keyboard bindings, and the other hotkeys."},
	{"id": "saves", "label": "Save / Load flight", "key": "F11", "kind": "page", "title": "Save / Load flight",
		"sub": "Save the flight as it is now, or go back to an earlier one. F11 quick-saves, Shift+F11 quick-loads."},
	{"id": "failures", "label": "Failures", "key": "F9", "kind": "page", "title": "Failures",
		"sub": "Fail or repair any system, live."},
	{"sep": true},
	{"id": "checklists", "label": "Checklists", "key": "F2", "kind": "action"},
	{"id": "replay", "label": "Instant replay", "key": "R", "kind": "action"},
	{"id": "restart", "label": "Restart flight", "key": "F5", "kind": "action", "confirm": true},
	{"sep": true},
	{"id": "menu", "label": "Quit to main menu", "kind": "action", "confirm": true},
	{"id": "quit", "label": "Quit game", "kind": "action", "confirm": true},
]
const HOME_TITLE := "Flight paused"
const HOME_SUB := "Nothing changes until you resume. Pick something on the left, or press Esc to carry on flying."


static func item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.get("id", "") == id:
			return it
	return {}


## The content for page `id`, ready to add to the pause screen's page host. `pause` is the pause
## screen (hidden while a save grabs its thumbnail). Pages that need room for a list fill the host;
## the others sit in a vertical scroll area so small windows scroll instead of clipping.
static func build(id: String, flight: Node, pause: Control) -> Control:
	var page: Control
	var scroll := true
	match id:
		"home":
			page = VBoxContainer.new()
			page.set_script(load("res://ui/pause_summary.gd"))
			scroll = false  # short: the panel shrinks to it and the scene shows below
		"options":
			page = _script_page(HBoxContainer.new(), "res://ui/menu/options_page.gd")
		"controls":
			page = _script_page(HBoxContainer.new(), "res://ui/menu/controls_page.gd")
		"settings":
			page = _script_page(PanelContainer.new(), "res://ui/settings_menu.gd")
			page.set("embedded", true)
		"failures":
			page = _script_page(PanelContainer.new(), "res://ui/failures_panel.gd")
			page.set("embedded", true)
			page.set("manager", flight.get_node("Systems/Failures"))
		"saves":
			page = _script_page(PanelContainer.new(), "res://ui/saves_panel.gd")
			page.set("embedded", true)
			page.set("flight", flight)
			page.set("hide_target", pause)
			scroll = false
		_:
			return null
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL if id != "home" else Control.SIZE_FILL
	if not scroll:
		return page
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  # a page wider than the window scrolls instead of pushing the layout out
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_FILL
	var m := MarginContainer.new()  # room on the right for the scroll bar
	m.add_theme_constant_override("margin_right", 8)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(page)
	sc.add_child(m)
	sc.set_meta("page", page)
	return sc


static func _script_page(c: Control, path: String) -> Control:
	c.set_script(load(path))
	return c


## Re-read what a page shows when it is opened again (the flight stands still while paused, but
## the player may have changed things elsewhere).
static func refresh(id: String, node: Control, flight: Node) -> void:
	var page: Control = node.get_meta("page") if node.has_meta("page") else node
	match id:
		"home": page.call("refresh", flight)
		"settings", "failures": page.call("refresh")
		"saves": page.call("open")
