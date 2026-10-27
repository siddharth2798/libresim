class_name TreeAtlas
extends Node
## Bakes the tree impostor atlas once at startup: two SubViewports draw tree_atlas.gdshader (albedo +
## cover, and normal), then each result is copied to an ImageTexture with mipmaps (a viewport
## texture has none, and far trees would shimmer without them). Emits `baked` when done; the
## viewports are freed. Headless runs have no renderer: they get a flat placeholder at once.

signal baked(albedo: Texture2D, normal: Texture2D)

const SPRITE := Vector2i(128, 256)
const GRID := Vector2i(TreeSpecies.VARIANTS, TreeSpecies.COUNT)

var albedo: Texture2D
var normal: Texture2D
var ready_ok := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		var img := Image.create(GRID.x * 2, GRID.y * 2, true, Image.FORMAT_RGBA8)
		img.fill(Color(0.1, 0.2, 0.07, 1.0))
		_finish(ImageTexture.create_from_image(img), ImageTexture.create_from_image(img))
		return
	var vps: Array[SubViewport] = []
	for pass_id in 2:
		var vp := SubViewport.new()
		vp.size = SPRITE * GRID
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var r := ColorRect.new()
		r.size = Vector2(vp.size)
		var m := ShaderMaterial.new()
		m.shader = preload("res://world/tree_atlas.gdshader")
		m.set_shader_parameter("pass_id", pass_id)
		r.material = m
		vp.add_child(r)
		add_child(vp)
		vps.append(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex: Array[Texture2D] = []
	for vp in vps:
		var img := vp.get_texture().get_image()
		img.generate_mipmaps()
		tex.append(ImageTexture.create_from_image(img))
		vp.queue_free()
	_finish(tex[0], tex[1])


func _finish(a: Texture2D, n: Texture2D) -> void:
	albedo = a
	normal = n
	ready_ok = true
	baked.emit(a, n)
