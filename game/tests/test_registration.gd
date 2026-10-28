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


func test_registration_source_callsign_follows_session_and_options() -> String:
	var old_s = Session.setup.get("callsign", "")
	var old_o = UserOptions.get_v("callsign")
	var sec := {"source": "callsign"}
	Session.setup.callsign = "vt-abc"
	var a := RegistrationPaint.text_for(sec)
	Session.setup.callsign = ""
	UserOptions.set_v("callsign", "N172SP")
	var b := RegistrationPaint.text_for(sec)
	UserOptions.set_v("callsign", "not a callsign !!")
	var c := RegistrationPaint.text_for(sec)
	Session.setup.callsign = old_s
	UserOptions.set_v("callsign", old_o)
	return "" if a == "VT-ABC" and b == "N172SP" and c == "VT-FSM" else "%s %s %s" % [a, b, c]


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
	var s := AircraftDef.load_def("c172").section("registration")
	var p := RegistrationPaint.plan(s, "VT-FSM")
	if s.get("source") != "callsign" or p.size() != 2:
		return "c172 registration section: %s" % [s]
	var tex := load(AircraftDef.load_def("c172").dir + "/" + str(s.texture)) as Texture2D
	var img := tex.get_image()
	for t in p:
		if not Rect2i(Vector2i.ZERO, img.get_size()).encloses(t.erase) or not t.erase.encloses(t.box):
			return "rectangles outside the atlas / the box outside the wiped area: %s" % [t]
	return ""
