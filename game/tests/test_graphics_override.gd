extends RefCounted
## override.cfg (the renderer saved for the next start, core/graphics_settings.gd): a real first start saves the
## preset's renderer, but a --quality= run, a non-interactive run (tests, probes) and a pending cancel never leave
## a file that changes the player's next start. All in a scratch folder; nothing touches the real override.cfg.

const DIR := "user://test_graphics_override"


func _graphics(preset: String, running: String) -> Node:
	DirAccess.make_dir_recursive_absolute(DIR)
	DirAccess.remove_absolute(DIR + "/override.cfg")
	var g: Node = load("res://core/graphics_settings.gd").new()
	g.override_dir = DIR
	g.running_override = running
	g.preset = preset
	return g


func _saved() -> String:
	return FileAccess.get_file_as_string(DIR + "/override.cfg") if FileAccess.file_exists(DIR + "/override.cfg") else ""


func _done(g: Node) -> void:
	g.free()
	DirAccess.remove_absolute(DIR + "/override.cfg")
	Session.interactive_override = -1


func test_first_start_saves_the_presets_renderer() -> String:
	var g := _graphics("medium", "forward_plus")  # a Medium player on the Forward+ default
	Session.interactive_override = 1
	g._match_renderer_once()
	var text := _saved()
	var pending: String = g._pending_renderer
	_done(g)
	return "" if text.contains("\"mobile\"") and pending == "mobile" else "first start saved '%s' / pending '%s', want mobile" % [text, pending]


func test_quality_flag_never_saves_a_renderer() -> String:
	var g := _graphics("low", "forward_plus")
	g._quality_cli = true  # --quality=low
	Session.interactive_override = 1
	g._match_renderer_once()
	var text := _saved()
	_done(g)
	return "" if text == "" else "a --quality= run saved an override.cfg: " + text


func test_non_interactive_run_never_writes() -> String:
	var g := _graphics("low", "forward_plus")
	Session.interactive_override = 0
	g._match_renderer_once()
	g.set_renderer("mobile")
	var text := _saved()
	var pending: String = g._pending_renderer  # the menus still know a switch was asked for
	var needed: bool = g.restart_needed()
	_done(g)
	if text != "":
		return "a non-interactive run wrote override.cfg: " + text
	return "" if pending == "mobile" and needed else "pending state lost (%s, %s)" % [pending, needed]


func test_a_chosen_renderer_is_saved_and_can_be_cancelled() -> String:
	var g := _graphics("high", "forward_plus")
	Session.interactive_override = 1
	g.set_renderer("mobile")  # the F10 toggle / the Options renderer row
	var first := _saved()
	g.set_renderer("forward_plus")  # back to the running one: the saved file says so, the switch is cancelled
	var second := _saved()
	var needed: bool = g.restart_needed()
	_done(g)
	if not first.contains("\"mobile\""):
		return "choosing Mobile did not save it: " + first
	return "" if second.contains("\"forward_plus\"") and not needed else "cancel failed: '%s', restart needed %s" % [second, needed]


func test_an_existing_override_is_left_alone() -> String:
	var g := _graphics("medium", "forward_plus")
	Session.interactive_override = 1
	var f := FileAccess.open(DIR + "/override.cfg", FileAccess.WRITE)
	f.store_string("[rendering]\nrenderer/rendering_method=\"forward_plus\"\n")
	f.close()
	g._match_renderer_once()  # a renderer was chosen before: do not overwrite it
	var text := _saved()
	_done(g)
	return "" if text.contains("forward_plus") else "an existing choice was overwritten: " + text
