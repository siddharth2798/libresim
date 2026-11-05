extends Node
## The one-pass paint pipeline (aircraft/common/paint_pipeline.gd): what is painted, the cache key, the fixed order livery ->
## registration -> mipmaps, the fallback when the renderer draws nothing. A headless renderer draws nothing, so the GPU compose and
## the glyph render are replaced by plain functions (PaintPipeline.test_compose / test_glyphs); the real pass is checked by the
## windowed probe tests/debug_livery_flight.tscn. Everything here completes without waiting for a frame.

const RED := Color(1.0, 0.0, 0.0)
const REG_COLOR := Color(0.64, 0.647, 0.625)  # the C172's fuselage number colour (aircraft.json)

var _def: AircraftDef
var _roots: Array[Node] = []
var _calls := {"compose": [], "glyphs": 0}
var _saved := false
var _saved_livery: Variant
var _saved_callsign: Variant


func _ready() -> void:
	_def = AircraftDef.load_def("c172")


func _begin(livery: Dictionary, callsign: String) -> void:
	if not _saved:
		_saved = true
		_saved_livery = Session.setup.get("livery")
		_saved_callsign = Session.setup.get("callsign", "")
	Session.setup.livery = livery
	Session.setup.callsign = callsign
	PaintPipeline.clear_cache()
	_calls = {"compose": [], "glyphs": 0}
	PaintPipeline.test_compose = _compose_red
	PaintPipeline.test_glyphs = _glyphs_white


func teardown() -> void:
	PaintPipeline.test_compose = Callable()
	PaintPipeline.test_glyphs = Callable()
	PaintPipeline.clear_cache()
	if _saved:
		Session.setup.livery = _saved_livery
		Session.setup.callsign = _saved_callsign
		_saved = false
	for r in _roots:
		if is_instance_valid(r):
			for mi in r.find_children("*", "MeshInstance3D", true, false):  # the dummy renderer complains about freed overrides
				for i in (mi as MeshInstance3D).get_surface_override_material_count():
					(mi as MeshInstance3D).set_surface_override_material(i, null)
			r.free()
	_roots.clear()


## The stand-in for the GPU pass: a whole atlas in flat red (so anything not painted afterwards is plainly red).
func _compose_red(atlas_id: String, atlas: Texture2D, _colors: Dictionary) -> Image:
	_calls.compose.append(atlas_id)
	var img := Image.create(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8)
	img.fill(RED)
	return img


func _glyphs_white(_text: String, _italic: bool) -> Image:
	_calls.glyphs += 1
	var g := Image.create(100, 40, false, Image.FORMAT_RGBA8)
	g.fill(Color.WHITE)
	return g


func _model() -> Node3D:
	var root := (load(_def.path("exterior")) as PackedScene).instantiate() as Node3D
	add_child(root)
	_roots.append(root)
	return root


## The texture of the first surface override whose base material uses `atlas_rel`, else null.
func _override_of(root: Node, atlas_rel: String) -> Texture2D:
	var path: String = _def.dir + "/" + atlas_rel
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var base := m.mesh.surface_get_material(i) as BaseMaterial3D
			var o := m.get_surface_override_material(i) as BaseMaterial3D
			if base != null and o != null and base.albedo_texture != null and base.albedo_texture.resource_path == path:
				return o.albedo_texture
	return null


func _overrides(root: Node) -> int:
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var o := m.get_surface_override_material(i) as BaseMaterial3D
			var base := m.mesh.surface_get_material(i) as BaseMaterial3D
			if o != null and base != null and o.albedo_texture != base.albedo_texture:
				n += 1
	return n


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _rels(p: Array) -> Array:
	return p.map(func(a): return a.rel.get_file().get_basename().trim_prefix("exterior_"))


# ---- what is painted ----

func test_pipeline_plan_nothing_to_do_for_the_factory_look() -> String:
	if not PaintPipeline.plan(_def, "4X-CHV", {}).is_empty():
		return "factory colours and the number the atlas carries must plan nothing: %s" % [_rels(PaintPipeline.plan(_def, "4X-CHV", {}))]
	var default_hex := Livery.to_hex(Livery.defaults(Livery.of(_def)).body).to_upper()
	if not PaintPipeline.plan(_def, "4x-chv", {"colors": {"body": default_hex}}).is_empty():
		return "a stored default colour is the factory look"
	if not PaintPipeline.plan(AircraftDef.load_def("a320"), "", {}).is_empty():
		return "factory colours and no number to stamp must plan nothing"
	return ""


func test_pipeline_plan_registration_only_and_livery_only() -> String:
	var reg := _rels(PaintPipeline.plan(_def, "VT-ABC", {}))
	if reg != ["fuselage", "wing"]:
		return "a new number repaints the fuselage and wing atlases only: %s" % [reg]
	var struts := _rels(PaintPipeline.plan(_def, "4X-CHV", {"colors": {"struts": "#aa0000"}}))
	if struts != ["fuselage"]:
		return "struts are on the fuselage atlas only, the baked number stays: %s" % [struts]
	var body := _rels(PaintPipeline.plan(_def, "4X-CHV", {"colors": {"body": "#aa0000"}}))
	if body != ["fuselage", "wing", "tail"]:
		return "body paint is on all three atlases: %s" % [body]
	var p := PaintPipeline.plan(_def, "VT-ABC", {"colors": {"struts": "#aa0000"}})
	if p.size() != 2 or p[0].steps.size() != 2 or not p[0].livery or p[1].livery or p[1].steps.size() != 2:
		return "fuselage: livery + 2 number steps, wing: 2 number steps only: %s" % [p.map(func(a): return [a.rel, a.livery, a.steps.size()])]
	return ""


# ---- the cache key ----

func test_pipeline_cache_key_changes_with_colour_call_sign_aircraft_and_atlas() -> String:
	var base := PaintPipeline.plan(_def, "VT-ABC", {"colors": {"body": "#aa0000"}})
	var again := PaintPipeline.plan(_def, " vt-abc ", {"body": "#AA0000"})  # other spelling of the same setup
	if base.map(func(a): return a.key) != again.map(func(a): return a.key):
		return "the same setup must give the same keys: %s vs %s" % [base.map(func(a): return a.key), again.map(func(a): return a.key)]
	var keys := {}
	for a in base:
		keys[a.key] = true
	if keys.size() != 3:
		return "one key per atlas: %s" % [keys.keys()]
	var other_colour := PaintPipeline.plan(_def, "VT-ABC", {"colors": {"body": "#aa0001"}})
	var other_sign := PaintPipeline.plan(_def, "VT-ABD", {"colors": {"body": "#aa0000"}})
	for i in 3:
		if other_colour[i].key == base[i].key:
			return "a changed colour must repaint %s" % base[i].rel
	if other_sign[0].key == base[0].key or other_sign[1].key == base[1].key:
		return "a changed call sign must repaint the atlases that carry it"
	if other_sign[2].key != base[2].key:
		return "the tail atlas has no number: a call sign must not repaint it"
	var other_ac := PaintPipeline.cache_key("c208", "VT-ABC", base[0].rel, Livery.cache_key("c208", base[0].colors))
	if other_ac == base[0].key:
		return "another aircraft must change the key"
	var struts_only := PaintPipeline.plan(_def, "VT-ABC", {"colors": {"body": "#aa0000", "struts": "#00aa00"}})
	if struts_only[1].key != base[1].key or struts_only[2].key != base[2].key or struts_only[0].key == base[0].key:
		return "a colour that is not on an atlas must not repaint it"
	return ""


# ---- the pass, with plain functions in place of the GPU ----

func test_pipeline_order_livery_then_registration_then_mipmaps() -> String:
	_begin({"c172": {"colors": {"body": "#c8101a"}}}, "VT-ABC")
	var root := _model()
	PaintPipeline.apply(self, root, _def)
	var tex := _override_of(root, "models/exterior_fuselage.png")
	if tex == null:
		return "the fuselage atlas got no override (compose calls %s, glyph renders %d)" % [_calls.compose, _calls.glyphs]
	var img := tex.get_image()
	if not img.has_mipmaps():
		return "mipmaps are generated after the number is stamped"
	img.convert(Image.FORMAT_RGBA8)
	if img.get_pixel(100, 100) != RED:
		return "outside the registration the livery shows: %s" % [img.get_pixel(100, 100)]
	var e: Array = _def.section("registration").targets[0].erase
	var corner := img.get_pixel(int(e[0]) + 1, int(e[1]) + 1)  # inside the wiped rectangle, outside the number: the wipe of red is red
	if not _near(corner, RED):
		return "the wipe reads the recoloured rows around the number: %s" % [corner]
	var mid := img.get_pixel(int(e[0]) + int(e[2]) / 2, int(e[1]) + int(e[3]) / 2)
	if not _near(mid, REG_COLOR):
		return "the number is stamped over the livery (registration after livery): %s" % [mid]
	var wing := _override_of(root, "models/exterior_wing.png")
	if wing == null or _override_of(root, "models/exterior_tail.png") == null:
		return "wing and tail atlases are painted too"
	var we: Array = _def.section("registration").targets[2].erase
	var wimg := wing.get_image()
	wimg.convert(Image.FORMAT_RGBA8)
	var wmid := wimg.get_pixel(int(we[0]) + int(we[2]) / 2, int(we[1]) + int(we[3]) / 2)
	if wimg.get_pixel(20, 20) != RED or _near(wmid, RED):
		return "the wing underside number is stamped on the recoloured wing atlas: %s / %s" % [wimg.get_pixel(20, 20), wmid]
	if not root.visible:
		return "the exterior must be shown again once painted"
	return ""


func test_pipeline_cached_setups_do_not_repaint() -> String:
	_begin({"c172": {"colors": {"body": "#c8101a"}}}, "VT-ABC")
	PaintPipeline.apply(self, _model(), _def)
	var first: Array = _calls.compose.duplicate()
	var glyphs: int = _calls.glyphs
	if first.size() != 3 or glyphs < 1:
		return "first pass: %d compose calls %s, %d glyph renders" % [first.size(), first, glyphs]
	var again := _model()
	PaintPipeline.apply(self, again, _def)  # a new model, the same setup: all from the cache
	if _calls.compose.size() != 3 or _calls.glyphs != glyphs:
		return "an unchanged setup must hit the cache: %d compose calls, %d glyph renders" % [_calls.compose.size(), _calls.glyphs]
	if _override_of(again, "models/exterior_fuselage.png") == null:
		return "cached textures must still land on the new model"
	Session.setup.livery = {"c172": {"colors": {"body": "#c8101b"}}}
	PaintPipeline.apply(self, _model(), _def)
	if _calls.compose.size() != 6:
		return "a changed colour repaints every atlas it is on: %d compose calls" % _calls.compose.size()
	Session.setup.callsign = "VT-XYZ"
	PaintPipeline.apply(self, _model(), _def)
	if _calls.compose.size() != 8 or _calls.glyphs <= glyphs:
		return "a changed call sign repaints the fuselage and wing only: %d compose calls %s" % [_calls.compose.size(), _calls.compose]
	return ""


func test_pipeline_factory_setup_paints_nothing() -> String:
	_begin({}, "4X-CHV")
	var root := _model()
	PaintPipeline.apply(self, root, _def)
	if _overrides(root) != 0 or not _calls.compose.is_empty() or _calls.glyphs != 0:
		return "the factory look must not be repainted: %d overrides, %d compose calls, %d glyph renders" % [_overrides(root), _calls.compose.size(), _calls.glyphs]
	return ""


func test_pipeline_renderer_without_pixels_keeps_the_factory_look() -> String:
	_begin({"c172": {"colors": {"body": "#c8101a"}}}, "VT-ABC")
	PaintPipeline.test_compose = func(_id, _atlas, _colors): return null
	PaintPipeline.test_glyphs = func(_text, _italic): return null
	var root := _model()
	PaintPipeline.apply(self, root, _def)
	if _overrides(root) != 0:
		return "no pixels from the renderer: no atlas may be replaced, %d were" % _overrides(root)
	if not root.visible:
		return "the exterior must not stay hidden"
	if not PaintPipeline._cache.is_empty():
		return "a failed pass must not be cached"
	return ""


func test_pipeline_half_results_degrade_one_step_at_a_time() -> String:
	# compose gives nothing, glyphs work: the number is still painted, on the factory atlas
	_begin({"c172": {"colors": {"body": "#c8101a"}}}, "VT-ABC")
	PaintPipeline.test_compose = func(_id, _atlas, _colors): return null
	var root := _model()
	PaintPipeline.apply(self, root, _def)
	var tex := _override_of(root, "models/exterior_fuselage.png")
	if tex == null or _override_of(root, "models/exterior_tail.png") != null:
		return "number without livery: the fuselage is repainted, the tail (no number, no colour) is left"
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var orig := (load(_def.dir + "/models/exterior_fuselage.png") as Texture2D).get_image()
	orig.convert(Image.FORMAT_RGBA8)
	if img.get_pixel(100, 100) != orig.get_pixel(100, 100):
		return "without the livery the paint is the factory paint"
	# glyphs give nothing, compose works: the colours are applied, the old number stays
	_begin({"c172": {"colors": {"body": "#c8101a"}}}, "VT-ABC")
	PaintPipeline.test_glyphs = func(_text, _italic): return null
	var root2 := _model()
	PaintPipeline.apply(self, root2, _def)
	var t2 := _override_of(root2, "models/exterior_fuselage.png")
	if t2 == null:
		return "colours without the number: the fuselage is still repainted"
	var e: Array = _def.section("registration").targets[0].erase
	var i2 := t2.get_image()
	i2.convert(Image.FORMAT_RGBA8)
	return "" if i2.get_pixel(int(e[0]) + int(e[2]) / 2, int(e[1]) + int(e[3]) / 2) == RED else "no number stamped when no glyphs were drawn"


func test_pipeline_cache_is_bounded() -> String:
	PaintPipeline.clear_cache()
	var t := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	for i in PaintPipeline.MAX_CACHE + 5:
		PaintPipeline._remember("k%d" % i, t)
	var n := PaintPipeline._cache.size()
	var oldest := PaintPipeline._cache.has("k0")
	PaintPipeline.clear_cache()
	return "" if n == PaintPipeline.MAX_CACHE and not oldest else "cache size %d, oldest kept %s" % [n, oldest]
