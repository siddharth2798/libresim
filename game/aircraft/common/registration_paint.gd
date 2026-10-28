class_name RegistrationPaint
extends RefCounted
## Paints the tail number on the exterior model at flight start (aircraft.json "registration"):
##   source   "callsign" (the pilot's call sign, AtcSession.callsign()) | "fixed" (use "text")
##   text     the registration for source "fixed" (an airliner's tail number is not its radio call sign)
##   texture  the atlas the old number is painted on, relative to the aircraft folder
##   targets  [{"erase": [x,y,w,h]   pixels of the old number (plus a margin) to wipe,
##              "text": [x,y,w,h]     box the new number is fitted into (aspect kept),
##              "align": "left|right|center", "color": [r,g,b] 0..1, "italic": true,
##              "rotate": 180   the atlas island is upside down (the A320's other fuselage side): the text is turned}]
## The old number is wiped by interpolating the clean rows just above and below it (the paint is white
## with a soft gradient), the new one is drawn once with a Label in a one-shot SubViewport and blended
## in. The edited atlas is an ImageTexture cached per (aircraft, text) and set as a surface override
## on the glb's surfaces that use the atlas; the file on disk is never changed. A renderer without
## pixels (headless / dummy) returns an empty image: the model then keeps the original number.

const FONT_PX := 200
const SHEAR := 0.22  # synthetic italic (x += SHEAR * y) when the font has no italic of its own

static var _cache := {}  # "<aircraft id>|<TEXT>" -> ImageTexture


## The registration this aircraft shows now ("" = none).
static func text_for(section: Dictionary) -> String:
	match str(section.get("source", "")):
		"callsign": return AtcSession.callsign().to_upper()
		"fixed": return str(section.get("text", "")).strip_edges().to_upper()
	return ""


## Draw plan: one entry per target, the text upper-cased, rectangles as Rect2i. [] for no section / no text.
static func plan(section: Dictionary, text: String) -> Array:
	var t := text.strip_edges().to_upper()
	var out := []
	if t == "" or not section.get("targets") is Array:
		return out
	for tg in section.targets:
		if not tg is Dictionary or not tg.get("erase") is Array or not tg.get("text") is Array:
			continue
		var c: Array = tg.get("color", [0.63, 0.64, 0.61])
		out.append({
			"text": t, "erase": _rect(tg.erase), "box": _rect(tg.text), "align": str(tg.get("align", "left")),
			"color": Color(c[0], c[1], c[2]), "italic": bool(tg.get("italic", true)), "rotate": int(tg.get("rotate", 0)),
		})
	return out


static func _rect(a: Array) -> Rect2i:
	return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


## Where a glyph block of this size lands in a box: scaled down or up to fit, aspect kept, vertically
## centred, horizontally by align.
static func fit(box: Rect2i, align: String, src: Vector2i) -> Rect2i:
	if src.x <= 0 or src.y <= 0:
		return Rect2i(box.position, Vector2i.ZERO)
	var k := minf(float(box.size.x) / src.x, float(box.size.y) / src.y)
	var sz := Vector2i(maxi(1, roundi(src.x * k)), maxi(1, roundi(src.y * k)))
	var x := box.position.x
	if align == "right":
		x += box.size.x - sz.x
	elif align == "center":
		x += (box.size.x - sz.x) / 2
	return Rect2i(Vector2i(x, box.position.y + (box.size.y - sz.y) / 2), sz)


## Wipe a rectangle: each column is the straight line between the pixel row just above and just below
## it, so the gradient of the paint carries through. Needs one clean row on both sides.
static func erase(img: Image, r: Rect2i) -> void:
	var y0 := r.position.y - 1
	var y1 := r.end.y
	if y0 < 0 or y1 >= img.get_height():
		return
	for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
		var a := img.get_pixel(x, y0)
		var b := img.get_pixel(x, y1)
		for y in range(r.position.y, r.end.y):
			img.set_pixel(x, y, a.lerp(b, float(y - y0) / float(y1 - y0)))


## Blend a glyph image (its alpha is the coverage) into img at rect, in color.
static func stamp(img: Image, glyphs: Image, rect: Rect2i, color: Color) -> void:
	var g := glyphs.duplicate() as Image
	g.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_LANCZOS)
	for y in g.get_height():
		for x in g.get_width():
			g.set_pixel(x, y, Color(color.r, color.g, color.b, g.get_pixel(x, y).a))
	img.blend_rect(g, Rect2i(Vector2i.ZERO, g.get_size()), rect.position)


static func cache_key(aircraft_id: String, text: String) -> String:
	return aircraft_id + "|" + text.strip_edges().to_upper()


## The finished texture of an earlier build of this (aircraft, text), else null.
static func cached(aircraft_id: String, text: String) -> Texture2D:
	return _cache.get(cache_key(aircraft_id, text))


## The edited atlas for this registration (cached); null when the plan is empty or nothing could be
## drawn. Awaits one rendered frame the first time.
static func texture(host: Node, aircraft_id: String, section: Dictionary, atlas: Texture2D, text: String) -> Texture2D:
	var key := cache_key(aircraft_id, text)
	if _cache.has(key):
		return _cache[key]
	var steps := plan(section, text)
	if steps.is_empty() or atlas == null:
		return null
	var glyphs := await render_glyphs(host, text.to_upper(), true)
	if glyphs == null:
		return null
	var img := atlas.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for s in steps:
		erase(img, s.erase)
	for s in steps:
		var g := glyphs
		if int(s.get("rotate", 0)) == 180:
			g = glyphs.duplicate()
			g.rotate_180()
		stamp(img, g, fit(s.box, s.align, g.get_size()), s.color)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## White text on transparent, cropped to the glyphs, drawn once with the engine's default font
## (emboldened, sheared). Null when the renderer gives no pixels.
static func render_glyphs(host: Node, text: String, italic: bool) -> Image:
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.55
	if italic:
		fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(SHEAR, 1), Vector2.ZERO)
	var size := Vector2i(fv.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_PX).ceil()) + Vector2i(FONT_PX, FONT_PX)
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var lab := Label.new()
	lab.text = text
	lab.position = Vector2(FONT_PX / 2.0, FONT_PX / 2.0)
	lab.add_theme_font_override("font", fv)
	lab.add_theme_font_size_override("font_size", FONT_PX)
	lab.add_theme_color_override("font_color", Color.WHITE)
	vp.add_child(lab)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image() if is_instance_valid(vp) else null
	if is_instance_valid(vp):
		vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x < 4 or used.size.y < 4:
		return null  # blank frame (dummy renderer)
	return img.get_region(used)


## Called from AircraftModel.build() once the exterior glb is in the tree: repaints the atlas.
static func apply(host: Node, glb_root: Node, def: AircraftDef) -> void:
	var section := def.section("registration")
	var text := text_for(section)
	if text == "" or not section.get("texture") is String:
		return
	var tex_path: String = def.dir + "/" + str(section.texture)
	if not ResourceLoader.exists(tex_path):
		return
	var tex: Texture2D = await texture(host, def.id, section, load(tex_path) as Texture2D, text)
	if tex == null or not is_instance_valid(glb_root):
		return
	for mi in glb_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path == tex_path:
				var d := mat.duplicate() as BaseMaterial3D
				d.albedo_texture = tex
				m.set_surface_override_material(i, d)
