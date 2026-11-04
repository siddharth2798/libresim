extends RefCounted
## The C172's optional "struts" livery region (wing struts and main gear legs, tools/25_livery_masks.py): where it is, what it leaves alone.


func _atlas_bytes(def: AircraftDef, rel: String) -> Image:
	var img := (load(def.dir + "/" + rel) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


# ---- the optional struts region (wing struts and main gear legs) ----

func test_livery_c172_struts_region_is_on_the_fuselage_atlas_only() -> String:
	var def := AircraftDef.load_def("c172")
	var lv := Livery.of(def)
	var keys: Array = lv.regions.map(func(r): return r.key)
	if keys != ["body", "accent", "stripe", "struts"]:
		return "regions: %s" % [keys]
	var st: Dictionary = lv.regions[3]
	if st.masks.size() != 1 or st.masks[0].atlas != "fuselage":
		return "struts: one mask, on the fuselage atlas: %s" % [st.masks]
	for atlas in lv.atlases:
		if Livery.regions_on(lv, atlas).size() > Livery.MAX_SLOTS:
			return "%s has more regions than the shader's slots" % atlas
	if Livery.regions_on(lv, "fuselage").size() != Livery.MAX_SLOTS:
		return "the fuselage atlas fills all four slots"
	var img := LiveryPaint.mask_image(def, st.masks[0].mask)
	var n := 0
	for v in img.get_data():
		n += 1 if v >= 128 else 0
	var cover := float(n) / (img.get_width() * img.get_height())
	return "" if cover > 0.005 and cover < 0.06 else "struts coverage %.4f" % cover


func _mask_at(def: AircraftDef, key: String, atlas: String) -> Image:
	var lv := Livery.of(def)
	for r in lv.regions:
		if r.key == key:
			for m in r.masks:
				if m.atlas == atlas:
					return LiveryPaint.mask_image(def, m.mask)
	return null


func test_livery_c172_struts_mask_covers_the_struts_and_legs_and_nothing_else() -> String:
	var def := AircraftDef.load_def("c172")
	var struts := _mask_at(def, "struts", "fuselage")
	var body := _mask_at(def, "body", "fuselage")
	# on the two wing strut strips and in the gear-leg capsule: struts at full strength, not half body paint
	for p in [Vector2i(1190, 1850), Vector2i(1510, 1850), Vector2i(330, 1850), Vector2i(380, 1800)]:
		if struts.get_pixelv(p).r < 0.97 or body.get_pixelv(p).r > 0.03:
			return "%s: struts %.2f body %.2f" % [p, struts.get_pixelv(p).r, body.get_pixelv(p).r]
	# tyres, propeller (both blades), hub, spinner disc, the nose leg's bare steel tile, antennas: not in any mask
	# (the blades lie on white atlas background that is inside a body island rectangle: only their dark pixels count)
	var dark_only := ["propeller", "propeller side"]
	var clear := {"tyre box": Rect2i(1620, 1600, 330, 440), "propeller": Rect2i(20, 470, 1740, 180), "propeller side": Rect2i(1930, 440, 95, 1030),
		"hub": Rect2i(1385, 955, 340, 325), "disc": Rect2i(1770, 85, 120, 120), "nose leg tile": Rect2i(1304, 1711, 112, 318),
		"antenna strip": Rect2i(860, 72, 440, 50)}
	var masks: Array = [struts, body, _mask_at(def, "accent", "fuselage"), _mask_at(def, "stripe", "fuselage")]
	var atlas := _atlas_bytes(def, "models/exterior_fuselage.png").get_data()
	for name in clear:
		var r: Rect2i = clear[name]
		for m in masks:
			var d: PackedByteArray = m.get_data()
			var w: int = m.get_width()
			for y in range(r.position.y, r.end.y, 3):
				for x in range(r.position.x, r.end.x, 3):
					if name in dark_only and atlas[(y * w + x) * 4] > 70:
						continue
					if d[y * w + x] > 8:
						return "a mask paints inside %s at %d,%d (%d)" % [name, x, y, d[y * w + x]]
	return ""


func test_livery_c172_struts_at_factory_colour_keep_the_look() -> String:
	var lv := Livery.of(AircraftDef.load_def("c172"))
	var d: Color = lv.regions[3].default
	if d.r < 0.8 or absf(d.r - d.g) > 0.05 or absf(d.r - d.b) > 0.05:
		return "the struts are white metal today, the factory colour is %s" % [d]
	var c := Livery.colors_of(lv, {"colors": {"body": "#102030"}})
	return "" if Livery.to_hex(c.struts) == Livery.to_hex(d) else "changing the body must leave the struts at their factory colour"
