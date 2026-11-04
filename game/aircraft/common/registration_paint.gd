class_name RegistrationPaint
extends RefCounted
## Paints the tail number on the exterior model at flight start (aircraft.json "registration"):
##   source   "callsign" (the pilot's call sign, Callsign.effective: what was typed on the Aircraft step / in Options, else "text")
##            | "fixed" (always "text": a tail number the pilot cannot change)
##   text     source "callsign": the aircraft's own registration, shown until the pilot types one (C172 VT-LBR, A320 VT-ZZA);
##            source "fixed": the registration
##   texture  the atlas the old number is painted on, relative to the aircraft folder
##   targets  [{"erase": [x,y,w,h]   pixels of the old number (plus a margin) to wipe,
##              "text": [x,y,w,h]     box the new number is fitted into (aspect kept),
##              "align": "left|right|center", "color": [r,g,b] 0..1, "italic": true,
##              "rotate": 90 | 180 | 270   the atlas island is turned (180: the A320's other fuselage side; 90: the C172's wing
##                        undersides, the number runs down the strip): the text is turned clockwise by this much,
##              "erase_axis": "y" (default) | "x"   wipe by interpolating between the clean rows above and below the number,
##                        or, for a vertical number, between the clean columns left and right of it,
##              "texture": another atlas than the section's (the C172's wing atlas), relative to the aircraft folder}]
## The old number is wiped by interpolating the clean pixels on both sides of it (the paint is white
## with a soft gradient), the new one is drawn once with a Label in a one-shot SubViewport and blended
## in. Each edited atlas is an ImageTexture cached per (aircraft, text, atlas) and set as a surface override
## on the glb's surfaces that use the atlas; the file on disk is never changed. A renderer without
## pixels (headless / dummy) returns an empty image: the model then keeps the original number.
## "baked" (optional): the number painted in the atlas as shipped; when the registration is that text nothing is repainted.
## The game paints the livery colours (livery.gd) and this registration in ONE pass per atlas, in this order: recolour, wipe + stamp
## the number, mipmaps (aircraft/common/paint_pipeline.gd). texture() below is the registration-only variant of that pass.

const FONT_PX := 200
const ABORTED := &"registration_aborted"  # host meta: it left the tree during a glyph render
const SHEAR := 0.22  # synthetic italic (x += SHEAR * y) when the font has no italic of its own

static var _cache := {}  # "<aircraft id>|<TEXT>[|<atlas>]" -> ImageTexture (registration only; PaintPipeline has its own cache)


## The registration this aircraft shows now ("" = none).
static func text_for(section: Dictionary) -> String:
	match str(section.get("source", "")):
		"callsign":
			var t := Callsign.typed()
			return (t if t != "" else Callsign.section_default(section)).to_upper()
		"fixed": return str(section.get("text", "")).strip_edges().to_upper()
	return ""


## True when `text` is the number the atlas already carries (section "baked"): no wipe, no stamp.
static func is_baked(section: Dictionary, text: String) -> bool:
	var b := str(section.get("baked", "")).strip_edges().to_upper()
	return b != "" and b == text.strip_edges().to_upper()


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
			"erase_axis": str(tg.get("erase_axis", "y")), "texture": str(tg.get("texture", section.get("texture", ""))),
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
## it, so the gradient of the paint carries through. Needs one clean row on both sides. axis "x": each
## row is the line between the column just left and just right of it (a vertical number).
static func erase(img: Image, r: Rect2i, axis := "y") -> void:
	if axis == "x":
		var x0 := r.position.x - 1
		var x1 := r.end.x
		if x0 < 0 or x1 >= img.get_width():
			return
		for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
			var a := img.get_pixel(x0, y)
			var b := img.get_pixel(x1, y)
			for x in range(r.position.x, r.end.x):
				img.set_pixel(x, y, a.lerp(b, float(x - x0) / float(x1 - x0)))
		return
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


## `atlas`: the target's own atlas when it is not the section's ("" = the section's).
static func cache_key(aircraft_id: String, text: String, atlas := "") -> String:
	return aircraft_id + "|" + text.strip_edges().to_upper() + ("|" + atlas if atlas != "" else "")


## The finished texture of an earlier build of this (aircraft, text), else null.
static func cached(aircraft_id: String, text: String, atlas := "") -> Texture2D:
	return _cache.get(cache_key(aircraft_id, text, atlas))


## The glyph image turned clockwise by 0 / 90 / 180 / 270 degrees.
static func turned(g: Image, deg: int) -> Image:
	var out := g.duplicate() as Image
	match posmod(deg, 360):
		90: out.rotate_90(CLOCKWISE)
		180: out.rotate_180()
		270: out.rotate_90(COUNTERCLOCKWISE)
	return out


## The edited atlas for this registration (cached): `atlas_rel` is the atlas file relative to the aircraft
## folder, "" for the section's own; null when no target paints on it or nothing could be drawn. Awaits one
## rendered frame per glyph style the first time. (Registration only; the game goes through PaintPipeline.)
static func texture(host: Node, aircraft_id: String, section: Dictionary, atlas: Texture2D, text: String, atlas_rel := "") -> Texture2D:
	var own := str(section.get("texture", ""))
	var rel := own if atlas_rel == "" else atlas_rel
	var key := cache_key(aircraft_id, text, "" if rel == own else rel)
	if _cache.has(key):
		return _cache[key]
	var steps := plan(section, text).filter(func(s): return s.texture == rel)
	if steps.is_empty() or atlas == null:
		return null
	var glyphs := {}
	if not await glyph_set(host, text, steps, glyphs):
		return null
	var img := atlas.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	stamp_steps(img, steps, glyphs)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Fills `glyphs` ({italic: Image}, kept between calls) with the glyph image of every style the steps need. False when the
## renderer gives no pixels (headless / dummy) or the host is on its way out.
static func glyph_set(host: Node, text: String, steps: Array, glyphs: Dictionary) -> bool:
	for s in steps:
		if not glyphs.has(s.italic):
			glyphs[s.italic] = await render_glyphs(host, text.to_upper(), s.italic)
		if glyphs[s.italic] == null:
			glyphs.erase(s.italic)
			return false
	return true


## The registration on an image: every old number wiped first, then every new one stamped (the wipe reads the rows and columns
## around the number, so whatever was painted on the image before, such as the livery, carries through). No mipmaps here.
static func stamp_steps(img: Image, steps: Array, glyphs: Dictionary) -> void:
	for s in steps:
		erase(img, s.erase, s.erase_axis)
	for s in steps:
		var g := turned(glyphs[s.italic], int(s.get("rotate", 0)))
		stamp(img, g, fit(s.box, s.align, g.get_size()), s.color)


## White text on transparent, cropped to the glyphs, drawn once with the engine's default font
## (emboldened, sheared). Null when the renderer gives no pixels.
static func render_glyphs(host: Node, text: String, italic: bool) -> Image:
	if not is_instance_valid(host) or not host.is_inside_tree() or host.has_meta(ABORTED):
		return null
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
	# Resumed after the next drawn frame, or at once (ok = false) when the viewport leaves the tree first: the host
	# freed or the game quitting. A chain of awaiting calls (apply -> texture -> here) that never resumes holds
	# itself alive and leaks at exit, so it must always end.
	vp.add_user_signal("drawn", [{"name": "ok", "type": TYPE_BOOL}])
	RenderingServer.frame_post_draw.connect(vp.emit_signal.bind("drawn", true), CONNECT_ONE_SHOT)
	vp.tree_exiting.connect(vp.emit_signal.bind("drawn", false), CONNECT_ONE_SHOT)
	var ok: bool = await Signal(vp, "drawn")
	if not ok:
		if is_instance_valid(host):
			host.set_meta(ABORTED, true)  # no more glyph renders under a host on its way out
		return null
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var used := img.get_used_rect()
	if used.size.x < 4 or used.size.y < 4:
		return null  # blank frame (dummy renderer)
	return img.get_region(used)


## Registration (and livery) of the exterior model: see PaintPipeline.apply, which AircraftModel.build calls.
static func apply(host: Node, glb_root: Node, def: AircraftDef) -> void:
	await PaintPipeline.apply(host, glb_root, def)
