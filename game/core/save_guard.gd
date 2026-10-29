class_name SaveGuard
extends RefCounted
## Decides whether this run may write the player's persistent files (user://last_flight.json,
## training.json, ui.cfg, options.cfg, graphics.cfg, audio.cfg). Reach it as Session.interactive().
## A run is NOT interactive when it is a probe, test, screenshot or command-line flight, so
## agents and scripts never overwrite what the player chose on the start screen.
## Key / input bindings and saved situations are only written on an explicit user action, not guarded.

const ENV := "FREESIM_NO_SAVE"  # any non-empty value other than "0" turns saving off
## Scenes under res://tests/ that emulate a player and check persistence across restarts
## (tools/e2e.sh backs the user files up and restores them around them).
const PERSISTENCE_SCENES := ["res://tests/e2e/e2e_menu"]


## args: all command-line arguments (engine ones carry the scene path), so a probe started as
## `godot --path game res://tests/debug_x.tscn` is recognised.
static func decide(args: PackedStringArray, headless: bool, env: String, shot: String, clean: bool, skip_menu: bool) -> bool:
	if env != "" and env != "0":
		return false
	if shot != "" or clean or skip_menu or headless:
		return false  # a screenshot, a clean promo shot, a command-line flight, a test run
	for a in args:
		if a.begins_with("res://tests/") or a.begins_with("res://tests."):
			for p in PERSISTENCE_SCENES:
				if a.begins_with(p):
					return true
			return false  # a test or probe scene
	return true
