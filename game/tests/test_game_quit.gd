extends Node
## Quitting with a session recording running (core/game_quit.gd, ui/session_recorder.gd): the recorder finishes and its
## frame read-backs come back before the engine stops. Quitting with read-backs in flight aborted the game on macOS
## ("recursive_mutex lock failed"); tests/debug_exit_leaks.tscn -- --record reproduces it in a real window.


class FakeRecorder:
	extends Node
	var finished := false

	func _ready() -> void:
		add_to_group(GameQuit.GROUP)

	func finish() -> void:
		finished = true


func test_game_quit_finishes_recorders_first() -> String:
	var r := FakeRecorder.new()
	add_child(r)
	var log := []
	GameQuit.quit(get_tree(), 3, func(code: int): log.append([code, r.finished]))
	r.free()
	if log != [[3, true]]:
		return "quit runs once, after the recorder finished, with its exit code: %s" % [log]
	var none := []
	GameQuit.quit(get_tree(), 0, func(code: int): none.append(code))
	return "" if none == [0] else "nothing to wait for: quit at once (%s)" % [none]


func test_recorder_waits_for_readbacks() -> String:
	if not SessionRecorder.should_wait(2, 0) or not SessionRecorder.should_wait(1, SessionRecorder.FINISH_FRAMES - 1):
		return "read-backs out: keep waiting"
	if SessionRecorder.should_wait(0, 0) or SessionRecorder.should_wait(5, SessionRecorder.FINISH_FRAMES):
		return "none out, or out of patience: stop waiting"
	var rec := SessionRecorder.new()
	add_child(rec)
	var err := "" if rec.is_in_group(GameQuit.GROUP) else "the recorder joins GameQuit's group"
	var done := [false]
	var run := func():
		await rec.finish()
		done[0] = true
	run.call()  # nothing pending, not recording: finish() returns at once
	if err.is_empty() and not done[0]:
		err = "finish() with nothing pending must not wait"
	rec.free()
	return err


func test_quit_paths_use_game_quit() -> String:
	for p in ["res://ui/pause_menu.gd", "res://ui/menu/start_screen.gd", "res://core/renderer_restart.gd"]:
		var src := FileAccess.get_file_as_string(p)
		if src.contains("tree().quit(") or src.contains("tree.quit("):
			return "%s quits directly; use GameQuit.quit so a recording finishes first" % p
		if not src.contains("GameQuit.quit("):
			return "%s should quit through GameQuit.quit" % p
	return ""
