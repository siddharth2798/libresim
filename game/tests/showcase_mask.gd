extends RefCounted
## Cockpit mask for tests/debug_showcase.gd --mask (tools/check_cockpit_clouds.py): everything but the aircraft is hidden
## and the background is flat magenta, so a pixel that is not magenta belongs to the aircraft (the cockpit, in the
## cockpit view). The picture it is taken from is the settled one, so the mask lines up with the shot pixel for pixel.

const WORLD := ["Terrain", "Buildings", "Trees", "Airports", "Terminals", "AirportOps", "TouchdownFx", "RunwayLights", "GroundOps"]
const MAGENTA := Color(1.0, 0.0, 1.0)


static func apply(f: Node) -> void:
	for n in WORLD:
		var node := f.get_node_or_null(n) as Node3D
		if node != null:
			node.visible = false
	f.get_node("SkyTime").process_mode = Node.PROCESS_MODE_DISABLED  # it shows the cloud layer again every frame
	var cam := f.get_node("Camera")
	for c in cam.get_children():
		if c is Node3D:
			(c as Node3D).visible = false  # cloud, rain, haze, fog planes: all ride on the camera
	var layer := cam.get_node_or_null("CloudLayer") as CloudLayer
	if layer != null:
		layer.visible = false
		layer.get_node("CloudUpscale").queue_free()
	var we := f.get_node("WorldEnvironment") as WorldEnvironment
	var env := we.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = MAGENTA
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	env.adjustment_enabled = false
	we.compositor = null
