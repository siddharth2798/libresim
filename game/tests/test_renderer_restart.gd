extends Node
## Switching renderer (core/renderer_restart.gd, ui/menu/restart_prompt.gd, Graphics._ask_restart): the relaunch keeps
## the command line minus an old --rendering-method, a flight is resumed by --resume-flight=, and a change the player
## made asks "Restart now?" (Later closes it). Scratch override.cfg folder; nothing relaunches in a test.

const DIR := "user://test_renderer_restart"

var _made: Array = []


func teardown() -> void:
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()
	DirAccess.remove_absolute(DIR + "/override.cfg")
	Session.interactive_override = -1


func test_relaunch_arguments_drop_the_old_renderer_and_carry_the_flight() -> String:
	var a := RendererRestart.arguments(PackedStringArray(["--path", "game", "--rendering-method", "mobile", "--audio-driver", "Dummy"]),
		PackedStringArray(["--airport=VABB", "--resume-flight=old"]), "_renderer_restart")
	var want := PackedStringArray(["--path", "game", "--audio-driver", "Dummy", "--", "--airport=VABB", "--resume-flight=_renderer_restart"])
	if a != want:
		return "got %s, want %s" % [a, want]
	var b := RendererRestart.arguments(PackedStringArray(["--rendering-method=forward_plus"]), PackedStringArray(), "")
	if not b.is_empty():
		return "nothing to carry: an empty command line, got %s" % [b]
	if RendererRestart.resume_file(want.slice(5)) != "_renderer_restart" or RendererRestart.resume_file(PackedStringArray(["--airport=VABB"])) != "":
		return "resume_file should read --resume-flight= and nothing else"
	return ""


func test_prompt_says_what_happens_to_the_flight() -> String:
	var fly := RestartPrompt.message("Forward+", true)
	var menu := RestartPrompt.message("Mobile", false)
	if not fly.contains("Forward+") or not fly.contains("flight is saved"):
		return "in flight the prompt should name the renderer and say the flight carries on: " + fly
	if menu.contains("flight") or not menu.contains("Mobile"):
		return "from the menus there is no flight to mention: " + menu
	return ""


func test_a_players_change_asks_and_later_closes_it() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var g: Node = load("res://core/graphics_settings.gd").new()
	g.override_dir = DIR
	g.running_override = "mobile"
	g.preset = "medium"
	add_child(g)
	_made.append(g)
	Session.interactive_override = 1
	g.set_renderer("forward_plus", true)
	if not g.restart_needed():
		return "choosing Forward+ on Mobile needs a restart"
	g._ask_restart()
	var layer: CanvasLayer = g._prompt
	if not is_instance_valid(layer) or layer.get_child_count() != 1 or not layer.get_child(0) is RestartPrompt:
		return "the player's change should open the Restart now? prompt"
	_made.append(layer)
	var p: RestartPrompt = layer.get_child(0)
	if not p.title_text().contains("Forward+"):
		return "the prompt should name the renderer it switches to"
	p.later.emit()
	if not layer.is_queued_for_deletion():
		return "Later should close the prompt"
	return ""
