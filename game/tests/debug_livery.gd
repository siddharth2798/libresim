extends Node
## Probe (windowed, the GPU draws): the livery compositor on every atlas of an aircraft (aircraft/common/livery_paint.gd).
##   godot --path game --windowed --resolution 800x600 --audio-driver Dummy res://tests/debug_livery.tscn -- --out=<dir> [--aircraft=c172]
## Checks: the factory livery composes to null (unchanged); for three test liveries, per atlas: pixels with every mask 0 are
## bit-identical, the registration boxes are untouched, fully masked pixels have the chosen hue, and the GPU result matches
## Livery.recolor_multi within +-2 levels. Saves before/after crops and atlas thumbnails, and 3/4-front and rear renders of the
## exterior glb in each livery (with the registration number painted on top, as the flight will) and in factory colours.
## Prints "LIVERY PROBE PASS|FAIL ..." lines, exit code 0 when all pass. Frame of the glb as in render_aircraft_previews.gd.

const TESTS := {
	"yellow": {"body": "#fff0a0", "accent": "#c01010", "stripe": "#0d4d26", "struts": "#c01010"},
	"red": {"body": "#c8101a", "accent": "#f2f2f2", "stripe": "#26262b", "struts": "#26262b"},
	"navy": {"body": "#0d1f66", "accent": "#f5f5f5", "stripe": "#d1a61a", "struts": "#d1a61a"},
}
const STRIDE := 3
const TOL := 2.0 / 255.0 + 0.0001

var _fails := 0
var _checks := true  # --no-checks: only the renders
var _only := []  # --liveries=red,navy: only these test liveries (default all)
var _views := ["front", "rear"]  # --views=front
var _out := "user://"
var _aid := "c172"
var _def: AircraftDef
var _lv: Dictionary


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	# an occluded window is not drawn on macOS (frame_post_draw never fires): come to the front and stay there
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="): _aid = a.substr(11)
		elif a.begins_with("--out="): _out = a.substr(6)
		elif a == "--no-checks": _checks = false
		elif a.begins_with("--liveries="): _only = a.substr(11).split(",")
		elif a.begins_with("--views="): _views = a.substr(8).split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_def = AircraftDef.load_def(_aid)
	_lv = Livery.of(_def)
	if _lv.regions.is_empty():
		_check("section", false, "%s has no livery section" % _aid)
		return _finish()
	var factory := Livery.defaults(_lv)
	var composed := {}  # test name -> {atlas id: Image}
	for aid in _lv.atlases:
		var tex := load(_def.dir + "/" + _lv.atlases[aid]) as Texture2D
		_check("identity " + aid, await LiveryPaint.compose(self, _def, aid, tex, factory) == null, "factory colours must return null")
	for name in TESTS:
		if not _only.is_empty() and not _only.has(name):
			continue
		var colors := Livery.colors_of(_lv, TESTS[name])
		composed[name] = {}
		for aid in _lv.atlases:
			var tex := load(_def.dir + "/" + _lv.atlases[aid]) as Texture2D
			var img := await LiveryPaint.compose(self, _def, aid, tex, colors)
			if img == null:
				_check("compose %s %s" % [name, aid], false, "no image (does this renderer draw?)")
				continue
			composed[name][aid] = img
			if _checks:
				_verify(name, aid, tex, img, colors)
			_save_crops(name, aid, tex, img)
	await _render_all(composed)
	_finish()


func _check(what: String, ok: bool, detail := "") -> void:
	if not ok:
		_fails += 1
	print("LIVERY PROBE %s %s %s" % ["PASS" if ok else "FAIL", what, detail])


func _finish() -> void:
	print("LIVERY PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _rgba(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Per-pixel checks of one composed atlas against the original and the masks.
func _verify(name: String, aid: String, tex: Texture2D, out: Image, colors: Dictionary) -> void:
	var o := _rgba(tex).get_data()
	var r := out.get_data()
	var regs := Livery.regions_on(_lv, aid)
	var masks := []
	for rg in regs:
		masks.append(LiveryPaint.mask_image(_def, rg.mask).get_data())
	var cols := regs.map(func(rg): return colors[rg.key])
	var lumas := regs.map(func(rg): return rg.luma)
	var w := out.get_width()
	var untouched_bad := 0
	var untouched_n := 0
	var gpu_max := 0.0
	var gpu_n := 0
	var gpu_bad := 0
	var hue_n := 0
	var hue_bad := 0
	for p in range(0, w * out.get_height(), STRIDE):
		var m := []
		var any := 0.0
		var top := -1
		for i in masks.size():
			var v: float = masks[i][p] / 255.0
			m.append(v)
			any = maxf(any, v)
			if v >= 0.999:
				top = i
		var q := p * 4
		if any == 0.0:
			untouched_n += 1
			if o[q] != r[q] or o[q + 1] != r[q + 1] or o[q + 2] != r[q + 2] or o[q + 3] != r[q + 3]:
				untouched_bad += 1
			continue
		var orig := Color(o[q] / 255.0, o[q + 1] / 255.0, o[q + 2] / 255.0, o[q + 3] / 255.0)
		var want := Livery.recolor_multi(orig, m, cols, lumas)
		var d := maxf(absf(want.r - r[q] / 255.0), maxf(absf(want.g - r[q + 1] / 255.0), absf(want.b - r[q + 2] / 255.0)))
		gpu_max = maxf(gpu_max, d)
		gpu_n += 1
		gpu_bad += 1 if d > TOL else 0
		if top >= 0 and m.count(0.0) == m.size() - 1:  # fully in one region only: its hue
			var c: Color = cols[top]
			var got := Color(r[q] / 255.0, r[q + 1] / 255.0, r[q + 2] / 255.0)
			if c.s > 0.3 and c.v > 0.2 and Livery.luma(orig) > 0.5 * lumas[top] and got.v > 0.1:
				hue_n += 1
				hue_bad += 1 if minf(absf(got.h - c.h), 1.0 - absf(got.h - c.h)) > 0.05 else 0
	_check("%s %s untouched" % [name, aid], untouched_bad == 0 and untouched_n > 0, "%d of %d mask-0 samples differ" % [untouched_bad, untouched_n])
	_check("%s %s gpu == Livery.recolor_multi" % [name, aid], gpu_bad == 0 and gpu_n > 0,
		"%d samples, max error %.2f levels, %d over tolerance" % [gpu_n, gpu_max * 255.0, gpu_bad])
	_check("%s %s hue" % [name, aid], hue_bad == 0, "%d fully masked samples checked, %d off the chosen hue" % [hue_n, hue_bad])
	var sec := _def.section("registration")
	var boxes := 0
	var box_bad := 0
	for t in sec.get("targets", []):
		if str(t.get("texture", sec.get("texture", ""))) != _lv.atlases[aid]:
			continue
		var e: Array = t.erase
		for y in range(int(e[1]), int(e[1]) + int(e[3])):
			for x in range(int(e[0]), int(e[0]) + int(e[2])):
				var q := (y * w + x) * 4
				boxes += 1
				box_bad += 1 if (o[q] != r[q] or o[q + 1] != r[q + 1] or o[q + 2] != r[q + 2]) else 0
	if boxes > 0:
		_check("%s %s registration boxes untouched" % [name, aid], box_bad == 0, "%d of %d pixels differ" % [box_bad, boxes])


func _save_crops(name: String, aid: String, tex: Texture2D, out: Image) -> void:
	var o := _rgba(tex)
	for pair in [["before", o], ["after", out]]:
		if name == TESTS.keys()[0] and pair[0] == "before":
			var b: Image = pair[1].duplicate()
			b.resize(768, 768, Image.INTERPOLATE_BILINEAR)
			b.save_png("%s/atlas_%s_before.png" % [_out, aid])
	var a := out.duplicate() as Image
	a.resize(768, 768, Image.INTERPOLATE_BILINEAR)
	a.save_png("%s/atlas_%s_%s_after.png" % [_out, aid, name])
	if aid == "fuselage":  # left side before / after, 1:1
		var rect := Rect2i(0, 40, 1100, 440)
		var strip := Image.create(rect.size.x, rect.size.y * 2 + 8, false, Image.FORMAT_RGBA8)
		strip.fill(Color(0.5, 0.5, 0.5))
		strip.blit_rect(o, rect, Vector2i.ZERO)
		strip.blit_rect(out, rect, Vector2i(0, rect.size.y + 8))
		strip.save_png("%s/crop_fuselage_%s.png" % [_out, name])


# ---- renders of the glb ----

func _render_all(composed: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	var model := (load(_def.path("exterior")) as PackedScene).instantiate() as Node3D
	model.transform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	root.add_child(model)
	AircraftModel.fix_glass(model, false)
	AircraftModel.lift_tyres(model)
	var box := _bounds(model)
	var centre := box.get_center()
	var radius := box.size.length() * 0.5
	_scene(root, box, radius)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.far = radius * 200.0
	root.add_child(cam)
	cam.current = true
	var sets := {"factory": {}}
	var n := 0
	for name in composed:
		n += 1
		var paths := {}
		for aid in composed[name]:
			var img: Image = composed[name][aid]
			var tex: Texture2D = null
			var sec := _def.section("registration")
			var rel: String = _lv.atlases[aid]
			var base_tex := ImageTexture.create_from_image(img)
			# the flight's order: livery first, then the registration painted over the recoloured copy
			tex = await RegistrationPaint.texture(self, "%s_probe_%s" % [_aid, name], sec, base_tex, "VT-LBR", rel) if not sec.is_empty() else null
			if tex == null:
				img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
			paths[_def.dir + "/" + rel] = tex
		sets[name] = paths
	for name in sets:
		_override(model, sets[name])
		for view in [["front", 38.0, 11.0], ["rear", 215.0, 14.0]].filter(func(v): return _views.has(v[0])):
			var az := deg_to_rad(view[1])
			var el := deg_to_rad(view[2])
			var dir := Vector3(cos(el) * cos(az), sin(el), -cos(el) * sin(az))
			cam.global_position = centre + dir * radius * 1.25
			cam.look_at(centre + Vector3(0, -radius * 0.03, 0))
			for i in 4:
				await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var f := "%s/%s_%s_%s.png" % [_out, _aid, name, view[0]]
			img.save_png(f)
			print("SAVED ", f)
	root.queue_free()


## Swap the albedo of every surface whose original albedo is one of the atlases (null / {} = factory).
func _override(model: Node, by_path: Dictionary) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var base := m.mesh.surface_get_material(i) as BaseMaterial3D
			if base == null or base.albedo_texture == null or not by_path.has(base.albedo_texture.resource_path):
				m.set_surface_override_material(i, null)
				continue
			var d := base.duplicate() as BaseMaterial3D
			d.albedo_texture = by_path[base.albedo_texture.resource_path]
			m.set_surface_override_material(i, d)


func _scene(root: Node3D, box: AABB, radius: float) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 40.0, radius * 40.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.52, 0.53, 0.54)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	root.add_child(ground)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.32, 0.54, 0.86)
	sky.sky_horizon_color = Color(0.74, 0.84, 0.93)
	sky.ground_horizon_color = Color(0.74, 0.84, 0.93)
	sky.ground_bottom_color = Color(0.52, 0.53, 0.54)
	var s := Sky.new()
	s.sky_material = sky
	env.sky = s
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var b := m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
