class_name LiveryPaint
extends RefCounted
## The livery compositor: one GPU pass over an atlas (SubViewport + livery.gdshader, the way RegistrationPaint.render_glyphs
## draws its text) that recolours the regions of aircraft.json "livery" and returns the result as an Image. Pure rule and
## data are in livery.gd. L0 colours only; stickers become a second pass after this one (L3), and the registration number is
## stamped on the result afterwards (RegistrationPaint wipes the old number from the recoloured rows around it, which is why
## the registration boxes are outside every mask).
## compose() does not generate mipmaps: the caller does, once, after everything else is drawn on the image
## (img.generate_mipmaps(); ImageTexture.create_from_image(img)), as RegistrationPaint.texture does.

const SHADER := preload("res://aircraft/common/livery.gdshader")
const ABORTED := &"livery_aborted"  # host meta: it left the tree during a pass


## The atlas `atlas_id` of the aircraft recoloured with `colors` ({region key: Color}, Livery.colors_of), as an RGBA8 image of the
## atlas size without mipmaps. null = "use the original": the livery is the factory one, no region is on this atlas, a mask is
## missing or of another size, or the renderer gives no pixels (headless / dummy). Awaits one drawn frame.
static func compose(host: Node, def: AircraftDef, atlas_id: String, atlas: Texture2D, colors: Dictionary) -> Image:
	var lv := Livery.of(def)
	if atlas == null or lv.regions.is_empty() or Livery.is_identity(lv, colors):
		return null
	var regs := Livery.regions_on(lv, atlas_id)
	if regs.is_empty() or not is_instance_valid(host) or not host.is_inside_tree() or host.has_meta(ABORTED):
		return null
	var src := atlas.get_image()
	if src == null or src.is_empty():
		return null
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(src))
	var black := ImageTexture.create_from_image(_flat(Vector2i(1, 1)))
	var lumas := Vector4(1, 1, 1, 1)
	for i in Livery.MAX_SLOTS:
		var tex: Texture2D = black
		var col := Vector3.ZERO
		if i < regs.size():
			var m := mask_image(def, regs[i].mask)
			if m == null or m.get_size() != src.get_size():
				push_warning("LiveryPaint: mask %s is missing or not the size of the atlas" % regs[i].mask)
				return null
			tex = ImageTexture.create_from_image(m)
			var c: Color = colors.get(regs[i].key, regs[i].default)
			col = Vector3(c.r, c.g, c.b)
			lumas[i] = regs[i].luma
		mat.set_shader_parameter("mask%d" % i, tex)
		mat.set_shader_parameter("colour%d" % i, col)
	mat.set_shader_parameter("lumas", lumas)
	return await _draw(host, mat, src.get_size())


## A region mask as an 8-bit grey image (R8), loaded through the resource loader (so it also works in an export); null if missing.
static func mask_image(def: AircraftDef, rel: String) -> Image:
	var p: String = def.dir + "/" + rel
	if not ResourceLoader.exists(p):
		return null
	var t := load(p) as Texture2D
	var img := t.get_image() if t != null else null
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_R8)
	return img


static func _flat(size: Vector2i) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_R8)
	img.fill(Color.BLACK)
	return img


## Draws a full-size ColorRect with the material into a one-shot SubViewport and reads it back. null without pixels.
static func _draw(host: Node, mat: ShaderMaterial, size: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = mat
	vp.add_child(rect)
	host.add_child(vp)
	# Resumed after the next drawn frame, or at once (ok = false) when the viewport leaves the tree first: see
	# RegistrationPaint.render_glyphs, a chain of awaits that never resumes would leak at exit.
	vp.add_user_signal("drawn", [{"name": "ok", "type": TYPE_BOOL}])
	RenderingServer.frame_post_draw.connect(vp.emit_signal.bind("drawn", true), CONNECT_ONE_SHOT)
	vp.tree_exiting.connect(vp.emit_signal.bind("drawn", false), CONNECT_ONE_SHOT)
	var ok: bool = await Signal(vp, "drawn")
	if not ok:
		if is_instance_valid(host):
			host.set_meta(ABORTED, true)
		return null
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	if img.get_used_rect().size == Vector2i.ZERO:
		return null  # blank frame (dummy renderer)
	return img
