class_name PaintPipeline
extends RefCounted
## One pass over every atlas of the player's aircraft at flight start: the pilot's livery colours AND the tail number.
## Per atlas, in this fixed order: base atlas -> livery recolour (LiveryPaint.compose, an async GPU one-shot; the factory livery
## or a renderer without pixels gives null = the original) -> registration (wipe the old number, stamp the new one; both read
## the recoloured pixels) -> generate_mipmaps -> a cached ImageTexture, set as a surface override on every surface of the glb
## whose albedo texture is that atlas.
## Why one pass: a surface that has an override no longer shows its atlas path, so a second painter would find nothing.
## Why this order: the registration boxes are outside every livery mask and the wipe interpolates the (recoloured) rows around
## the number, so the number sits on the new paint; mipmaps last so no level shows the old paint.
## Cache key: aircraft | TEXT | atlas | livery key of the regions on THAT atlas (Livery.cache_key; "factory" when they are all at
## their factory colour), so a new colour or call sign repaints, a setup seen before does not, and a colour that is not on an atlas
## never repaints it. Nothing to do (livery at factory colours AND no registration, or the number the atlas already carries, see
## RegistrationPaint.is_baked) = nothing painted, no override, the model keeps the file's own texture.
## While atlases are being painted (a frame or two the first time) the exterior is hidden, so the flight never starts with a
## half-painted aircraft; a headless run does not paint at all, a renderer that returns no pixels or a timeout shows the factory look.

const MAX_CACHE := 9  # textures kept: 3 atlases x 3 looks (about 22 MB each with mipmaps)
const WATCHDOG_S := 12.0  # the exterior is shown again after this long whatever happens

static var _cache := {}  # cache_key -> ImageTexture, oldest first
## Tests only (a headless renderer draws nothing): replace the GPU compose and the glyph render by plain functions.
## compose: (atlas_id: String, atlas: Texture2D, colors: Dictionary) -> Image | null; glyphs: (text: String, italic: bool) -> Image | null.
static var test_compose := Callable()
static var test_glyphs := Callable()


static func cache_key(aircraft_id: String, text: String, atlas_rel: String, livery_key: String) -> String:
	return "%s|%s|%s|%s" % [aircraft_id, text.strip_edges().to_upper(), atlas_rel, livery_key]


static func clear_cache() -> void:
	_cache.clear()


## What to paint: [{rel, path, atlas (livery atlas id or ""), steps (registration steps), colors ({key: Color} of this atlas),
## livery (bool: some region differs from the factory), key}], one entry per atlas that has something to do. Pure: `text` is the
## registration to show ("" = none) and `stored` the pilot's {key: "#rrggbb"} (or the setup entry); nothing is rendered.
static func plan(def: AircraftDef, text: String, stored: Variant) -> Array:
	var out := []
	var lv := Livery.of(def)
	var section := def.section("registration")
	var colors := Livery.colors_of(lv, stored)
	var steps_all := [] if RegistrationPaint.is_baked(section, text) else RegistrationPaint.plan(section, text)
	var rels := []  # atlases in a stable order: the livery's, then any only the registration paints on
	var ids := {}  # rel -> livery atlas id
	for id in lv.atlases:
		rels.append(lv.atlases[id])
		ids[lv.atlases[id]] = id
	for st in steps_all:
		if st.texture != "" and not rels.has(st.texture):
			rels.append(st.texture)
	for rel in rels:
		var id: String = ids.get(rel, "")
		var on := Livery.colors_on(lv, id, colors) if id != "" else {}
		var changed := id != "" and not Livery.is_identity(lv, on)
		var steps := steps_all.filter(func(s): return s.texture == rel)
		if not changed and steps.is_empty():
			continue
		out.append({"rel": rel, "path": def.dir + "/" + rel, "atlas": id, "steps": steps, "colors": on, "livery": changed,
			"key": cache_key(def.id, text if not steps.is_empty() else "", rel, Livery.cache_key(def.id, on) if changed else "factory")})
	return out


## Called from AircraftModel.build() once the exterior glb is in the tree. Cached atlases are swapped in at once (this returns
## without waiting); otherwise it awaits the GPU frames, with the exterior hidden meanwhile.
static func apply(host: Node, glb_root: Node, def: AircraftDef) -> void:
	var text := RegistrationPaint.text_for(def.section("registration"))
	var todo := []
	for a in plan(def, text, Livery.entry(Session.setup.get("livery"), def.id)):
		if _cache.has(a.key):
			override(glb_root, a.path, _cache[a.key])
		else:
			todo.append(a)
	if todo.is_empty() or not is_instance_valid(glb_root):
		return
	if DisplayServer.get_name() == "headless" and not test_compose.is_valid():
		return  # no renderer: no frame is ever drawn to wait for, the model keeps the factory look (and is never hidden)
	var root := glb_root as Node3D
	if root != null:
		root.visible = false
		if host.is_inside_tree():
			host.get_tree().create_timer(WATCHDOG_S).timeout.connect(_show.bind(root))
	if not test_compose.is_valid() and host.is_inside_tree():
		await host.get_tree().process_frame  # the first viewport is added after the scene finished building (flight._ready calls build)
	var glyphs := {}  # italic -> glyph image, shared by the atlases
	for a in todo:
		var tex: Texture2D = await build(host, def, a, text, glyphs)
		if tex == null:
			continue  # nothing could be drawn: that atlas keeps the factory look
		_remember(a.key, tex)
		if is_instance_valid(glb_root):
			override(glb_root, a.path, tex)
	_show(root)


static func _show(root: Variant) -> void:
	if is_instance_valid(root):
		root.visible = true


static func _remember(key: String, tex: Texture2D) -> void:
	_cache.erase(key)
	_cache[key] = tex
	while _cache.size() > MAX_CACHE:
		_cache.erase(_cache.keys()[0])


## One atlas through the pipeline (an entry of plan): the finished texture, or null when nothing could be drawn (no pixels from the
## renderer, no glyphs and no livery). `glyphs` is the caller's {italic: Image} (filled on demand).
static func build(host: Node, def: AircraftDef, a: Dictionary, text: String, glyphs: Dictionary) -> Texture2D:
	var atlas := load(a.path) as Texture2D if ResourceLoader.exists(a.path) else null
	if atlas == null:
		return null
	var img: Image = null
	if a.livery:
		if test_compose.is_valid():
			img = await test_compose.call(a.atlas, atlas, a.colors)
		else:
			img = await LiveryPaint.compose(host, def, a.atlas, atlas, a.colors)
	var drawn := false
	if not a.steps.is_empty():
		drawn = await _glyphs(host, text, a.steps, glyphs)
	if img == null and not drawn:
		return null
	if img == null:
		img = atlas.get_image()
		if img == null or img.is_empty():
			return null
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	if drawn:
		RegistrationPaint.stamp_steps(img, a.steps, glyphs)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _glyphs(host: Node, text: String, steps: Array, glyphs: Dictionary) -> bool:
	if not test_glyphs.is_valid():
		return await RegistrationPaint.glyph_set(host, text, steps, glyphs)
	for s in steps:
		if not glyphs.has(s.italic):
			glyphs[s.italic] = await test_glyphs.call(text.to_upper(), s.italic)
		if glyphs[s.italic] == null:
			glyphs.erase(s.italic)
			return false
	return true


## Every surface of the glb whose albedo texture file is `tex_path` gets a copy of its material with `tex`.
static func override(glb_root: Node, tex_path: String, tex: Texture2D) -> void:
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
