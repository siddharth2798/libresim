extends Node
## Non-interactive runs (tests, probes, --shot, --clean, command-line flights, FREESIM_NO_SAVE) must not
## write the player's files (core/save_guard.gd); a normal start from the start screen still saves.
## Session.save_path points at a scratch file here, so the real user://last_flight.json is never touched.

const TMP := "user://_save_guard_test.json"

var _path := ""
var _override := -1


func _begin() -> void:
	_path = Session.save_path
	_override = Session.interactive_override
	Session.save_path = TMP
	_remove()


func _end() -> void:
	_remove()
	Session.save_path = _path
	Session.interactive_override = _override


func _remove() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)


func _decide(args: Array, headless := false, env := "", shot := "", clean := false, skip := false) -> bool:
	return SaveGuard.decide(PackedStringArray(args), headless, env, shot, clean, skip)


func test_decide_interactive_only_for_a_plain_start() -> String:
	if not _decide(["--path", "game"]):
		return "a plain start from the start screen must be interactive"
	if not _decide(["--path", "game", "--", "--quality=low", "--menu"]):
		return "--quality / --menu alone must stay interactive"
	if not _decide(["--path", "game", "res://tests/e2e/e2e_menu.tscn"]):
		return "the e2e menu scene emulates a player and checks persistence"
	return ""


func test_decide_blocks_probes_shots_and_cmdline_flights() -> String:
	var cases := {
		"test scene": _decide(["res://tests/debug_a320_look.tscn"]),
		"e2e runner": _decide(["res://tests/e2e/e2e_runner.tscn", "--", "--aircraft=a320"]),
		"--shot": _decide(["--"], false, "", "x.png"),
		"--clean": _decide(["--"], false, "", "", true),
		"command-line flight": _decide(["--"], false, "", "", false, true),
		"headless": _decide([], true),
		"env var": _decide([], false, "1"),
	}
	for k in cases:
		if cases[k]:
			return "%s must not be interactive" % k
	return "" if _decide([], false, "0") else "FREESIM_NO_SAVE=0 should not block saving"


func test_session_save_skipped_when_not_interactive() -> String:
	_begin()
	Session.interactive_override = 0
	Session.save()
	var err := "a non-interactive run wrote the last flight" if FileAccess.file_exists(TMP) else ""
	_end()
	return err


func test_session_save_written_for_an_interactive_start() -> String:
	_begin()
	Session.interactive_override = 1
	var keep_aircraft = Session.setup.aircraft
	Session.setup.aircraft = "a320"
	Session.save()
	Session.setup.aircraft = keep_aircraft
	var err := ""
	if not FileAccess.file_exists(TMP):
		err = "an interactive start did not save"
	else:
		var d = JSON.parse_string(FileAccess.get_file_as_string(TMP))
		if not (d is Dictionary) or d.get("aircraft") != "a320":
			err = "saved file lacks the chosen setup"
	_end()
	return err


func test_this_test_run_is_not_interactive() -> String:
	var keep := Session.interactive_override
	Session.interactive_override = -1
	var ok := not Session.interactive()
	Session.interactive_override = keep
	return "" if ok else "the test runner would write the player's files"


func test_cmdline_state_decides_through_session() -> String:
	var keep := [Session.shot, Session.clean, Session.skip_menu, Session.interactive_override]
	Session.interactive_override = -1
	Session.shot = "a.png"
	var shot_blocks := not Session.interactive()
	Session.shot = keep[0]
	Session.interactive_override = keep[3]
	return "" if shot_blocks else "--shot must block saving"
