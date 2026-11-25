class_name LoaderHold
extends RefCounted
## Keeps a scene's canvas layers (the flight's HUD, instrument panels, notifications, cockpit tips, controls overlay) hidden
## while the window veil is up, so nothing of the sim can show through or around the loading film. The veil (BusyOverlay.cover)
## owns one: sweep() each frame hides every layer of the current scene and remembers what was visible; release() puts each back
## the way it was when the veil goes. A layer the scene hid itself (a clean shot) stays hidden.

const RESCAN_S := 0.5  # layers a scene adds late; the full sweep of a big scene is not run every frame

var _held: Dictionary = {}  # CanvasLayer -> visible before it was hidden
var _scene: Node
var _since := 0.0


## Hide the layers of `scene` (descendants, not the veil's own layer). Call every frame; the sweep runs when the scene
## changes and then every RESCAN_S.
func sweep(scene: Node, dt: float) -> void:
	if scene == null:
		return
	_since += dt
	if scene == _scene and _since < RESCAN_S:
		return
	_scene = scene
	_since = 0.0
	for n in scene.find_children("*", "CanvasLayer", true, false):
		var layer := n as CanvasLayer
		if not _held.has(layer):
			_held[layer] = layer.visible
		layer.visible = false


func release() -> void:
	for layer in _held:
		if is_instance_valid(layer):
			(layer as CanvasLayer).visible = _held[layer]
	_held.clear()
	_scene = null


func count() -> int:
	return _held.size()
