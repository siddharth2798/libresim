extends RefCounted
## Tail number (aircraft/common/registration_paint.gd): draw plan, wiping the old number, call sign source.

const SECTION := {"source": "callsign", "texture": "models/exterior_fuselage.png", "targets": [
	{"erase": [10, 10, 40, 20], "text": [12, 12, 36, 16], "align": "right", "color": [0.5, 0.5, 0.5], "italic": true},
	{"erase": [10, 50, 40, 20], "text": [12, 52, 36, 16], "align": "left"}]}


func test_registration_plan_upper_case_dash_kept() -> String:
	var p := RegistrationPaint.plan(SECTION, " vt-fsm ")
	if p.size() != 2 or p[0].text != "VT-FSM" or p[1].text != "VT-FSM":
		return "plan: %s" % [p]
	if p[0].box != Rect2i(12, 12, 36, 16) or p[0].erase != Rect2i(10, 10, 40, 20) or p[0].align != "right":
		return "rects: %s" % [p[0]]
	if p[1].italic != true or p[1].color.is_equal_approx(Color(0.5, 0.5, 0.5)):
		return "defaults for a missing colour / italic: %s" % [p[1]]
	return ""


func test_registration_fit_keeps_aspect_and_aligns() -> String:
	var box := Rect2i(100, 200, 240, 60)
	var wide := RegistrationPaint.fit(box, "left", Vector2i(480, 60))  # width limited: scale 0.5
	if wide != Rect2i(100, 215, 240, 30):
		return "wide: %s" % [wide]
	var tall := RegistrationPaint.fit(box, "right", Vector2i(100, 100))  # height limited: 60 x 60
	if tall != Rect2i(280, 200, 60, 60):
		return "tall right: %s" % [tall]
	var mid := RegistrationPaint.fit(box, "center", Vector2i(100, 100))
	if mid != Rect2i(190, 200, 60, 60):
		return "centre: %s" % [mid]
	if RegistrationPaint.fit(box, "left", Vector2i.ZERO).size != Vector2i.ZERO:
		return "empty source"
	return ""


func test_registration_erase_removes_text_on_gradient() -> String:
	var img := Image.create(120, 80, false, Image.FORMAT_RGBA8)
	for y in 80:
		for x in 120:
			var v := 0.85 + 0.10 * x / 120.0 + 0.05 * y / 80.0
			img.set_pixel(x, y, Color(v, v, v))
	var orig := img.duplicate() as Image
	var r := Rect2i(20, 25, 70, 30)
	for y in range(30, 50):  # dark "text" inside the rectangle
		for x in range(30, 80):
			img.set_pixel(x, y, Color(0.3, 0.3, 0.3))
	RegistrationPaint.erase(img, r)
	var worst := 0.0
	for y in 80:
		for x in 120:
			worst = maxf(worst, absf(img.get_pixel(x, y).r - orig.get_pixel(x, y).r))
	if worst > 0.02:
		return "wiped area differs from the clean background by %.3f" % worst
	var edge := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	edge.fill(Color.RED)
	RegistrationPaint.erase(edge, Rect2i(0, 0, 10, 10))  # no clean row above: a no-op, no error
	return "" if edge.get_pixel(5, 5) == Color.RED else "erase at the image edge must do nothing"


func test_registration_stamp_blends_colour() -> String:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var g := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	g.fill(Color(1, 1, 1, 1))
	RegistrationPaint.stamp(img, g, Rect2i(4, 4, 8, 8), Color(0.2, 0.4, 0.6))
	var c := img.get_pixel(6, 6)
	if not c.is_equal_approx(Color(0.2, 0.4, 0.6)) or img.get_pixel(1, 1) != Color.WHITE:
		return "stamp: %s outside %s" % [c, img.get_pixel(1, 1)]
	return ""


func test_registration_absent_or_unknown_section_is_noop() -> String:
	if not RegistrationPaint.plan({}, "VT-FSM").is_empty() or not RegistrationPaint.plan(SECTION, "").is_empty():
		return "no section / no text must plan nothing"
	if RegistrationPaint.text_for({}) != "" or RegistrationPaint.text_for({"source": "weird"}) != "":
		return "unknown source gives no text"
	if RegistrationPaint.text_for({"source": "fixed", "text": "d-aixa"}) != "D-AIXA":
		return "fixed text upper-cased"
	return ""


func test_registration_source_callsign_follows_session_then_section_default() -> String:
	var old_s = Session.setup.get("callsign", "")
	var sec := {"source": "callsign"}
	Session.setup.callsign = "vt-abc"
	var a := RegistrationPaint.text_for(sec)
	Session.setup.callsign = ""
	var b := RegistrationPaint.text_for({"source": "callsign", "text": "vt-lbr"})  # untouched: the section's own registration
	Session.setup.callsign = "not a callsign !!"
	var c := RegistrationPaint.text_for(sec)  # invalid and no default in the section: the last resort
	Session.setup.callsign = old_s
	return "" if a == "VT-ABC" and b == "VT-LBR" and c == "VT-FSM" else "%s %s %s" % [a, b, c]


func test_registration_cache_is_per_aircraft_and_text() -> String:
	RegistrationPaint._cache.clear()
	var t := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	RegistrationPaint._cache["c172|VT-ABC"] = t
	var got := RegistrationPaint.cached("c172", "vt-abc")  # any case / padding of the text
	var other := RegistrationPaint.cached("c172", "VT-XYZ")
	var other_ac := RegistrationPaint.cached("c208", "VT-ABC")
	RegistrationPaint._cache.clear()
	return "" if got == t and other == null and other_ac == null else "cache: %s / %s / %s" % [got, other, other_ac]


func test_registration_c172_data() -> String:
	var def := AircraftDef.load_def("c172")
	var s := def.section("registration")
	var p := RegistrationPaint.plan(s, "VT-FSM")
	if s.get("source") != "callsign" or p.size() != 4:
		return "c172 registration section: fuselage sides and both wing undersides expected: %s" % [s]
	for t in p:
		var path: String = def.dir + "/" + t.texture
		if not ResourceLoader.exists(path):
			return "atlas %s does not exist" % path
		var img := (load(path) as Texture2D).get_image()
		if not Rect2i(Vector2i.ZERO, img.get_size()).encloses(t.erase) or not t.erase.encloses(t.box):
			return "rectangles outside the atlas / the box outside the wiped area: %s" % [t]
		var strip: Rect2i = t.erase if t.erase_axis == "x" else Rect2i()
		if t.erase_axis == "x" and (strip.position.x < 1 or strip.end.x >= img.get_width()):
			return "an x-axis wipe needs a clean column on both sides: %s" % [t]
	return ""


func test_registration_target_atlas_rotation_and_axis_in_the_plan() -> String:
	var sec := {"texture": "a.png", "targets": [
		{"erase": [0, 0, 10, 10], "text": [1, 1, 8, 8]},
		{"erase": [0, 0, 10, 10], "text": [1, 1, 8, 8], "texture": "b.png", "rotate": 90, "erase_axis": "x"}]}
	var p := RegistrationPaint.plan(sec, "ab")
	if p[0].texture != "a.png" or p[0].erase_axis != "y" or p[0].rotate != 0:
		return "defaults: the section's atlas, wipe along y, no rotation: %s" % [p[0]]
	if p[1].texture != "b.png" or p[1].erase_axis != "x" or p[1].rotate != 90:
		return "own atlas, x wipe, 90 degrees: %s" % [p[1]]
	if RegistrationPaint.cache_key("c172", "vt-a") != "c172|VT-A" or RegistrationPaint.cache_key("c172", "vt-a", "b.png") != "c172|VT-A|b.png":
		return "cache key: %s %s" % [RegistrationPaint.cache_key("c172", "vt-a"), RegistrationPaint.cache_key("c172", "vt-a", "b.png")]
	return ""


func test_registration_erase_along_x_interpolates_between_the_side_columns() -> String:
	var img := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for y in 4:
		img.set_pixel(0, y, Color(0.0, 0.0, 0.0))  # left of the wiped rectangle
		img.set_pixel(11, y, Color(1.0, 1.0, 1.0))
		for x in range(2, 10):
			img.set_pixel(x, y, Color(1, 0, 0))  # the old number
	RegistrationPaint.erase(img, Rect2i(1, 0, 10, 4), "x")
	for x in range(1, 11):
		var want := float(x) / 11.0
		var got := img.get_pixel(x, 2)
		if absf(got.r - want) > 0.02 or absf(got.g - want) > 0.02:
			return "column %d: %s, want grey %.2f" % [x, got, want]
	var edge := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	edge.fill(Color(0.3, 0.3, 0.3))
	var before := edge.get_pixel(1, 1)  # 8 bit: not exactly 0.3
	RegistrationPaint.erase(edge, Rect2i(0, 0, 3, 3), "x")  # no clean column to the left: a no-op
	if edge.get_pixel(1, 1) != before:
		return "an x wipe at the image edge changed pixels"
	return ""


func test_registration_turned_glyphs() -> String:
	var g := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	g.set_pixel(0, 0, Color.RED)  # top-left
	var cw := RegistrationPaint.turned(g, 90)
	if cw.get_size() != Vector2i(2, 4) or cw.get_pixel(1, 0) != Color.RED:
		return "90 clockwise: top-left goes to top-right, size %s" % [cw.get_size()]
	var ccw := RegistrationPaint.turned(g, 270)
	if ccw.get_size() != Vector2i(2, 4) or ccw.get_pixel(0, 3) != Color.RED:
		return "270: top-left goes to bottom-left"
	var half := RegistrationPaint.turned(g, 180)
	if half.get_size() != Vector2i(4, 2) or half.get_pixel(3, 1) != Color.RED:
		return "180: top-left goes to bottom-right"
	if RegistrationPaint.turned(g, 0).get_pixel(0, 0) != Color.RED or g.get_size() != Vector2i(4, 2):
		return "0 degrees / the source image must stay as it was"
	return ""


## Every atlas a registration target paints on is used by a surface of the exterior model, so the override lands.
func test_registration_every_target_atlas_is_on_the_exterior_model() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var plan := RegistrationPaint.plan(def.section("registration"), "VT-FSM")
		if plan.is_empty() or not ResourceLoader.exists(def.path("exterior")):
			continue
		var root := (load(def.path("exterior")) as PackedScene).instantiate()
		var used := {}
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in (m.mesh.get_surface_count() if m.mesh != null else 0):
				var mat := m.get_active_material(i) as BaseMaterial3D
				if mat != null and mat.albedo_texture != null:
					used[mat.albedo_texture.resource_path] = true
		root.free()
		for st in plan:
			var path: String = def.dir + "/" + st.texture
			if not used.has(path):
				return "%s: no surface of the exterior model uses %s (registration would not show)" % [id, path]
	return ""


func test_registration_baked_number_is_not_repainted() -> String:
	var sec := AircraftDef.load_def("c172").section("registration")
	if not RegistrationPaint.is_baked(sec, " 4x-chv ") or RegistrationPaint.is_baked(sec, "VT-FSM") or RegistrationPaint.is_baked(sec, ""):
		return "c172: the baked number is 4X-CHV (any case), nothing else"
	return "" if not RegistrationPaint.is_baked({"source": "fixed", "text": "A"}, "A") else "no \"baked\" key: never baked"


## stamp_steps works on whatever is on the image: the paint around the number carries into the wiped area, the old number goes.
func test_registration_stamp_steps_wipes_then_stamps_on_a_painted_image() -> String:
	var img := Image.create(80, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.1, 0.1))  # a recoloured atlas
	for y in range(15, 25):
		for x in range(20, 60):
			img.set_pixel(x, y, Color(0.1, 0.1, 0.1))  # the old number
	var sec := {"texture": "a.png", "targets": [{"erase": [10, 10, 60, 20], "text": [20, 12, 40, 16], "align": "center", "color": [0.0, 0.0, 1.0]}]}
	var g := Image.create(20, 10, false, Image.FORMAT_RGBA8)
	g.fill(Color.WHITE)
	RegistrationPaint.stamp_steps(img, RegistrationPaint.plan(sec, "ab"), {true: g})
	var corner := img.get_pixel(11, 11)  # wiped, outside the new number
	var mid := img.get_pixel(40, 20)
	var outside := img.get_pixel(2, 2)
	if absf(corner.r - 0.8) > 0.01 or absf(corner.b - 0.1) > 0.01:
		return "the old number is wiped to the paint around it: %s" % [corner]
	if mid.b < 0.95 or mid.r > 0.05:
		return "the new number is stamped on top: %s" % [mid]
	return "" if absf(outside.r - 0.8) < 0.01 else "outside the wipe nothing changes: %s" % [outside]
