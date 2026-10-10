extends Label
## FPS / frame-time / draw-call overlay plus camera position (F3 toggles).

@export var terrain_path: NodePath
var _terrain: TerrainQuadtree


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F3:
		visible = not visible


func _process(_dt: float) -> void:
	if not visible:
		return
	var fps := Engine.get_frames_per_second()
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var cam := get_viewport().get_camera_3d()
	var txt := "%d FPS  %.1f ms  draws %d  tris %dk" % [fps, 1000.0 / maxf(fps, 1), draws, prims / 1000]
	if cam:
		var w := FloatingOrigin.to_world(cam.global_position)
		var ll := Geo.to_latlon(w.x, w.y)
		var agl := w.z - (_terrain.height_at(w.x, w.y) if _terrain else 0.0)
		txt += "\n%.5fN %.5fE  alt %.0f m  AGL %.0f m" % [ll.x, ll.y, w.z, agl]
	if _terrain:
		txt += "\nterrain nodes %d" % _terrain.visible_nodes
	text = txt
