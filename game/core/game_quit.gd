class_name GameQuit
extends RefCounted
## Every way out of the game goes through quit(): Quit on the pause and start screens, the renderer restart, and the
## window's close button / Cmd+Q while a session recording runs (ui/session_recorder.gd takes those over then). A
## recording still running is stopped first and its frame read-backs are let finish.
## Why: the recorder reads each frame back with RenderingDevice.texture_get_data_async, whose callback is a GDScript
## lambda. Quitting with read-backs in flight let the rendering device call them during engine shutdown, after
## GDScript's own mutex was gone, and the game aborted ("recursive_mutex lock failed: Invalid argument", macOS,
## 2026-11-25: one quit in three with recording on).

const GROUP := "session_recorder"  # nodes with a finish() coroutine that must end before the engine stops


## Stop every recorder in the tree, wait for them, then quit (or call `quitter` instead: tests).
static func quit(tree: SceneTree, code := 0, quitter := Callable()) -> void:
	for r in tree.get_nodes_in_group(GROUP):
		if is_instance_valid(r) and r.has_method("finish"):
			await r.finish()
	if quitter.is_valid():
		quitter.call(code)
	else:
		tree.quit(code)
