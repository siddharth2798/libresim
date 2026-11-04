extends Node
## Probe (windowed, the GPU draws): the real flight scene with a livery and a call sign, parked and in the air (L1 of docs/LIVERY-PLAN.md).
##   godot --path game --windowed --resolution 960x600 --audio-driver Dummy res://tests/debug_livery_flight.tscn -- --out=<dir> \
##     --livery=body=#c8101a,accent=#f2f2f2,stripe=#26262b,struts=#f2c200 --callsign=VT-LBR [--air] [--shots=front,rear,fuselage,wing] [--factory]
## Every flight option of world/flight.gd is understood (Session reads them); --out and --shots are the probe's own. Waits for the paint pass
## (PaintPipeline.apply, fire-and-forget in AircraftModel.build), then checks the fuselage atlas the model is wearing against the original and
## the masks, saves screenshots from the front, the rear, the fuselage side (the number) and under the wing (the number), and prints
## "LIVERY FLIGHT PASS|FAIL ..." lines; exit code 0 when all pass. --factory: no livery check (the factory look must not be repainted
## when the call sign is the baked one). Run it with --headless as well: no pixels, the model keeps the factory atlas, no hang.

const VIEWS := {  # name -> [eye (forward, right, up) m from the aircraft's node, target (same)]
	"front": [Vector3(4.2, 3.4, 1.3), Vector3(0.0, 0.0, 0.5)],
	"rear": [Vector3(-5.8, -3.2, 1.5), Vector3(-0.6, 0.0, 0.6)],
	"fuselage": [Vector3(-2.2, 3.4, 0.9), Vector3(-2.4, 0.0, 0.7)],
	"wing": [Vector3(0.2, 5.4, 0.1), Vector3(-0.2, 2.6, 1.4)],
}

var _out := "user://"
var _shots := ["front", "rear", "fuselage", "wing"]
var _factory := false
var _fails := 0
var _flight: Node
var _cam: CameraRig
var _model: Node3D
var _aim_view := ""
var _headless := false


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)  # an occluded window is not drawn on macOS
	DisplayServer.window_move_to_foreground()
	_headless = DisplayServer.get_name() == "headless"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): _out = a.substr(6)
		elif a.begins_with("--shots="): _shots = a.substr(8).split(",")
		elif a == "--factory": _factory = true
	DirAccess.make_dir_recursive_absolute(_out)
	_flight = load("res://world/flight.tscn").instantiate()
	add_child(_flight)
	_cam = _flight.get_node("Camera")
	_model = _flight.get_node("Aircraft")
	_cam.set_mode(CameraRig.Mode.FREE)
	_run()


func _check(what: String, ok: bool, detail := "") -> void:
	_fails += 0 if ok else 1
	print("LIVERY FLIGHT %s %s %s" % ["PASS" if ok else "FAIL", what, detail])


func _process(_dt: float) -> void:
	if _aim_view == "" or _model == null:
		return
	var t := _model.global_transform  # forward = -z, right = x, up = y of the body
	var v: Array = VIEWS[_aim_view]
	var eye: Vector3 = t.origin + (-t.basis.z) * v[0].x + t.basis.x * v[0].y + t.basis.y * v[0].z
	var target: Vector3 = t.origin + (-t.basis.z) * v[1].x + t.basis.x * v[1].y + t.basis.y * v[1].z
	var d := target - eye
	_cam._free_enu = FloatingOrigin.to_world(eye)
	_cam._look = Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


func _run() -> void:
	var fuselage := "models/exterior_fuselage.png"
	var waited := 0.0
	var wants := not PaintPipeline.plan(AircraftDef.current(), RegistrationPaint.text_for(AircraftDef.current().section("registration")),
		Livery.entry(Session.setup.get("livery"), AircraftDef.current().id)).is_empty()
	while wants and _override_of(fuselage) == null and waited < 45.0 and not _headless:
		await get_tree().process_frame
		waited += get_process_delta_time()
	var frames := 0
	while _headless and not _exterior_visible() and frames < 600:  # headless: the pass gives up when the renderer returns no pixels
		await get_tree().process_frame
		frames += 1
	for i in 30:
		await get_tree().process_frame
	if _headless:
		print("headless: exterior shown again after %d frames" % frames)
	var tex := _override_of(fuselage)
	var def := AircraftDef.current()
	var lv := Livery.of(def)
	var entry := Livery.entry(Session.setup.get("livery"), def.id)
	var colors := Livery.colors_of(lv, entry)
	var text := RegistrationPaint.text_for(def.section("registration"))
	var expect_paint := not PaintPipeline.plan(def, text, entry).is_empty() and not _headless
	print("setup: livery %s call sign %s air %s, paint plan %d atlases, waited %.1f s" % [entry, text, Session.setup.start, PaintPipeline.plan(def, text, entry).size(), waited])
	_check("exterior visible after the paint pass", _exterior_visible(), "")
	if _headless:
		_check("headless: no pixels, the factory atlas stays (no hang, no half-painted model)", tex == null, "override %s" % [tex])
		return _finish()
	_check("a repainted fuselage atlas is on the model", (tex != null) == expect_paint, "expected %s, got %s" % [expect_paint, tex])
	if tex != null:
		_verify(tex.get_image(), def, lv, colors, text)
	if not _factory:
		for atlas in lv.atlases:
			_check("override on %s" % atlas, _override_of(lv.atlases[atlas]) != null, "")
	for _i in 240:
		await get_tree().process_frame  # terrain and the sky load in
	for view in _shots:
		_aim_view = view
		for _i in 6:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var f := "%s/%s_%s.png" % [_out, "air" if Session.setup.start == "air" else "parked", view]
		img.save_png(f)
		print("SAVED ", f)
	_finish()


func _finish() -> void:
	print("LIVERY FLIGHT %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## The exterior glb (the child of the aircraft node with the many meshes) is shown: PaintPipeline hides it only while it paints.
func _exterior_visible() -> bool:
	var n := 0
	for c in _model.get_children():
		if c is Node3D and c.find_children("*", "MeshInstance3D", true, false).size() > 50:
			n += 1
			if not (c as Node3D).visible:
				return false
	return n > 0


## The texture a surface override gives for the atlas file `rel` (a path in the aircraft folder), else null.
func _override_of(rel: String) -> Texture2D:
	var path := AircraftDef.current().dir + "/" + rel
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in (m.mesh.get_surface_count() if m.mesh != null else 0):
			var base := m.mesh.surface_get_material(i) as BaseMaterial3D
			var o := m.get_surface_override_material(i) as BaseMaterial3D
			if base != null and o != null and base.albedo_texture != null and base.albedo_texture.resource_path == path and o.albedo_texture is ImageTexture:
				return o.albedo_texture
	return null


func _rgba(t: Texture2D) -> Image:
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## The worn fuselage atlas against the original and the masks: outside every mask (and the number boxes) nothing changed, inside a mask
## the chosen hue, and in the number boxes the registration.
func _verify(worn: Image, def: AircraftDef, lv: Dictionary, colors: Dictionary, text: String) -> void:
	worn.convert(Image.FORMAT_RGBA8)
	var orig := _rgba(load(def.dir + "/models/exterior_fuselage.png") as Texture2D)
	var o := orig.get_data()
	var r := worn.get_data()
	var w := orig.get_width()
	var regs := Livery.regions_on(lv, "fuselage")
	var masks := regs.map(func(rg): return LiveryPaint.mask_image(def, rg.mask).get_data())
	var sec := def.section("registration")
	var boxes: Array = []
	for st in RegistrationPaint.plan(sec, text).filter(func(s): return s.texture == "models/exterior_fuselage.png"):
		boxes.append(st.erase)
	var same := 0
	var untouched := 0
	var hue_n := 0
	var hue_bad := 0
	for p in range(0, w * orig.get_height(), 5):
		var x := p % w
		var y := p / w
		if boxes.any(func(b): return b.has_point(Vector2i(x, y))):
			continue
		var any := 0
		for m in masks:
			any = maxi(any, m[p])
		var q := p * 4
		if any == 0:
			untouched += 1
			same += 1 if (o[q] == r[q] and o[q + 1] == r[q + 1] and o[q + 2] == r[q + 2]) else 0
			continue
		for i in regs.size():
			var c: Color = colors[regs[i].key]
			if masks[i][p] == 255 and c.s > 0.4 and c.v > 0.3 and Livery.luma(Color(o[q] / 255.0, o[q + 1] / 255.0, o[q + 2] / 255.0)) > 0.6 * regs[i].luma:
				var got := Color(r[q] / 255.0, r[q + 1] / 255.0, r[q + 2] / 255.0)
				hue_n += 1
				hue_bad += 1 if minf(absf(got.h - c.h), 1.0 - absf(got.h - c.h)) > 0.06 else 0
	_check("outside every mask and number box the atlas is the original", same == untouched and untouched > 1000, "%d of %d samples" % [same, untouched])
	if not _factory and not Livery.is_identity(lv, colors):
		_check("masked paint has the chosen hue", hue_n > 200 and hue_bad * 50 < hue_n, "%d samples, %d off" % [hue_n, hue_bad])
	if text != "" and not RegistrationPaint.is_baked(sec, text):
		var diff := 0
		for b in boxes:
			for y in range(b.position.y, b.end.y, 2):
				for x in range(b.position.x, b.end.x, 2):
					diff += 1 if o[(y * w + x) * 4] != r[(y * w + x) * 4] else 0
		_check("the number %s is painted in the boxes" % text, diff > 400 * boxes.size() / 8, "%d changed samples" % diff)
