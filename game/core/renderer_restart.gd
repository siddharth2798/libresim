class_name RendererRestart
extends RefCounted
## Switching between the Mobile and Forward+ renderers needs a new process: Godot picks the rendering method once, at
## start. After the player confirms (ui/menu/restart_prompt.gd), restart() relaunches libresim with the same command line
## (OS.set_restart_on_exit, every platform), so override.cfg's renderer takes effect. A running flight is saved first
## (user://saves/<RESUME>.json) and resumed straight after the restart (start_screen.gd reads RESUME_ARG); that save is
## deleted once it has been loaded (Situation.load_pending).

const RESUME := "_renderer_restart"
const RESUME_ARG := "--resume-flight="
const FLIGHT := "res://world/flight.tscn"


## Save the flight if there is one, then quit and come back with the same arguments (minus an old renderer override).
static func restart(tree: SceneTree) -> void:
	var resume := ""
	var scene := tree.current_scene
	if scene != null and scene.scene_file_path == FLIGHT and Situation.why_not_save(scene) == "":
		if Situation.save(scene, RESUME) == "":
			resume = SituationStore.file_name(RESUME)
	OS.set_restart_on_exit(true, arguments(OS.get_cmdline_args(), OS.get_cmdline_user_args(), resume))
	tree.quit()


## The relaunch command line: engine arguments without --rendering-method (it would override override.cfg), the user
## arguments without an old resume, plus the resume of this flight when there is one (pure, tested).
static func arguments(engine: PackedStringArray, user: PackedStringArray, resume: String) -> PackedStringArray:
	var out := PackedStringArray()
	var skip := false
	for a in engine:
		if skip:
			skip = false
			continue
		if a == "--rendering-method":
			skip = true
			continue
		if a.begins_with("--rendering-method="):
			continue
		out.append(a)
	var mine := PackedStringArray()
	for a in user:
		if not a.begins_with(RESUME_ARG):
			mine.append(a)
	if resume != "":
		mine.append(RESUME_ARG + resume)
	if not mine.is_empty():
		out.append("--")
		out.append_array(mine)
	return out


## The save to resume after a restart ("" when this start is not one).
static func resume_file(user: PackedStringArray) -> String:
	for a in user:
		if a.begins_with(RESUME_ARG):
			return a.substr(RESUME_ARG.length())
	return ""
