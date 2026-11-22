class_name RunwayBake
extends RefCounted
## Bakes the static look of one runway (world/runway_bake.gdshader: pavement tone, lanes, patches, sealant, wheel
## tracks, oil, rubber stain, worn paint, all deterministic from RunwayMarkings' seed) into a mipmapped RGBA8 texture
## that world/runway_v2.gdshader reads with one fetch (its `bake_tex`); only the near field stays procedural.
## One GPU pass in a throw-away SubViewport (a RenderingServer canvas item, drawn at once with force_draw), read
## back for the mipmaps. TEXEL metres per texel (across, along); a runway longer than MAX_PX x TEXEL.y gets coarser texels along.
## Needs a rendering device: with the headless dummy renderer bake() returns null.

const TEXEL := Vector2(0.2, 0.5)
const MAX_PX := 16384
const SHADER := "res://world/runway_bake.gdshader"


## Metres per texel (across, along) for runway record r.
static func texel_for(r: Dictionary) -> Vector2:
	return Vector2(TEXEL.x, maxf(TEXEL.y, float(r.length) / MAX_PX))


static func size_for(r: Dictionary) -> Vector2i:
	var t := texel_for(r)
	return Vector2i(mini(ceili(float(r.width) / t.x), MAX_PX), ceili(float(r.length) / t.y))


## Bytes of the baked texture with its mipmaps.
static func bytes_for(r: Dictionary) -> int:
	var s := size_for(r)
	return int(s.x * s.y * 4 * 4 / 3.0)


## The baked texture for runway r with uniforms u (RunwayMarkings.uniforms(r)), at once (force_draw: tools, tests,
## the preview); host: any node in the tree. null when nothing can be rendered (headless).
static func bake(r: Dictionary, u: Dictionary, host: Node) -> ImageTexture:
	var job := begin(r, u, host)
	if job.is_empty():
		return null
	RenderingServer.force_draw(false)
	var img := read(job)
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Sets the pass up; it is drawn with the next frame (or a force_draw), then read() it. {} when nothing can be
## rendered (headless, host outside the tree).
static func begin(r: Dictionary, u: Dictionary, host: Node) -> Dictionary:
	if DisplayServer.get_name() == "headless" or host == null or not host.is_inside_tree():
		return {}
	var size := size_for(r)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	for k in u:
		mat.set_shader_parameter(k, u[k])
	mat.set_shader_parameter("glyphs", RunwayGlyphs.texture())
	mat.set_shader_parameter("rw_noise_tex", RunwayNoise.texture())
	mat.set_shader_parameter("texel_m", Vector2(float(r.width) / size.x, float(r.length) / size.y))
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	# a canvas item made through the RenderingServer (a ColorRect only queues its draw for the next idle frame)
	var ci := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ci, vp.find_world_2d().canvas)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2.ZERO, Vector2(size)), Color.WHITE)
	RenderingServer.canvas_item_set_material(ci, mat.get_rid())
	return {"vp": vp, "ci": ci, "mat": mat}


## The drawn pass as an RGBA8 Image without mipmaps (build them off the main thread); frees the pass. null if empty.
static func read(job: Dictionary) -> Image:
	var vp: SubViewport = job.vp
	var img := vp.get_texture().get_image()
	cancel(job)
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Frees a pass that was begun.
static func cancel(job: Dictionary) -> void:
	if job.is_empty() or not is_instance_valid(job.vp):
		return
	RenderingServer.free_rid(job.ci)
	job.vp.get_parent().remove_child(job.vp)
	job.vp.free()
