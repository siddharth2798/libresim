extends RefCounted
## Livery logic (aircraft/common/livery.gd) and the C172's derived region masks (tools/25_livery_masks.py).
## The GPU pass itself has no headless test: tests/debug_livery.tscn (windowed) checks it pixel by pixel.

const SECTION := {
	"atlases": [{"id": "a", "texture": "models/a.png"}, {"id": "b", "texture": "models/b.png"}],
	"regions": [
		{"key": "body", "label": "Body", "default": [0.9, 0.9, 0.9], "masks": [{"atlas": "a", "mask": "livery/a_body.png", "luma": 0.9}, {"atlas": "b", "mask": "livery/b_body.png", "luma": 0.8}]},
		{"key": "trim", "label": "Trim", "default": [0.0, 0.1, 0.4], "masks": [{"atlas": "a", "mask": "livery/a_trim.png", "luma": 0.1}]}]}


func _lv() -> Dictionary:
	return Livery.parse(SECTION)


func test_livery_parse_c172_section() -> String:
	var lv := Livery.of(AircraftDef.load_def("c172"))
	if lv.atlases.size() != 3 or lv.regions.size() < 3:
		return "c172: %d atlases, %d regions" % [lv.atlases.size(), lv.regions.size()]
	for r in lv.regions:
		for m in r.masks:
			if not lv.atlases.has(m.atlas) or m.luma <= 0.0:
				return "bad mask entry %s" % [m]
	if Livery.defaults(lv).size() != lv.regions.size():
		return "defaults"
	return ""


func test_livery_parse_tolerates_malformed_input() -> String:
	for bad in [null, 5, "x", [], {}, {"atlases": 5, "regions": "x"}, {"atlases": [1, "x", {"id": 3}], "regions": [1, null, {}]}]:
		var lv := Livery.parse(bad)
		if not lv.regions.is_empty():
			return "garbage gave regions: %s" % [bad]
	var s := SECTION.duplicate(true)
	s.regions.append({"key": "body", "default": [0, 0, 0], "masks": [{"atlas": "a", "mask": "x.png", "luma": 0.5}]})  # duplicate key
	s.regions.append({"key": "nodef", "masks": [{"atlas": "a", "mask": "x.png", "luma": 0.5}]})
	s.regions.append({"key": "hi", "default": [2.0, 0, 0], "masks": [{"atlas": "a", "mask": "x.png", "luma": 0.5}]})
	s.regions.append({"key": "nomask", "default": [0, 0, 0], "masks": []})
	s.regions.append({"key": "badatlas", "default": [0, 0, 0], "masks": [{"atlas": "zzz", "mask": "x.png", "luma": 0.5}]})
	s.regions.append({"key": "noluma", "default": [0, 0, 0], "masks": [{"atlas": "a", "mask": "x.png"}]})
	s.regions.append({"key": "", "default": [0, 0, 0], "masks": [{"atlas": "a", "mask": "x.png", "luma": 0.5}]})
	var lv := Livery.parse(s)
	if lv.regions.size() != 2 or lv.regions[0].key != "body" or lv.regions[0].masks.size() != 2:
		return "only the two valid regions should remain: %s" % [lv.regions.map(func(r): return r.key)]
	return ""


func test_livery_colors_of_merges_over_defaults() -> String:
	var lv := _lv()
	var c := Livery.colors_of(lv, {"body": "#ff0000", "trim": "00ff00", "ghost": "#ffffff"})
	if c.size() != 2 or c.body.to_html(false) != "ff0000" or c.trim.to_html(false) != "00ff00":
		return "valid entries: %s" % [c]
	c = Livery.colors_of(lv, {"body": "red", "trim": "#12345"})
	if not c.body.is_equal_approx(Color(0.9, 0.9, 0.9)) or not c.trim.is_equal_approx(Color(0.0, 0.1, 0.4)):
		return "bad hex must keep the default: %s" % [c]
	for junk in [null, 7, "x", [], {"body": 5, "trim": null}, {"body": "#ggggggg"}]:
		if not Livery.is_identity(lv, Livery.colors_of(lv, junk)):
			return "junk %s should leave the factory livery" % [junk]
	c = Livery.colors_of(lv, {"colors": {"body": "#0000FF"}})  # the Session.setup entry shape
	return "" if c.body.to_html(false) == "0000ff" else "setup entry shape: %s" % [c]


func test_livery_hex_round_trip() -> String:
	for h in ["#000000", "#ffffff", "#1a2b3c", "#fe0001"]:
		if Livery.to_hex(Livery.parse_hex(h)) != h:
			return "round trip %s" % h
	if Livery.parse_hex("#abc") != null or Livery.parse_hex("#12345g") != null or Livery.parse_hex(3) != null or Livery.parse_hex("") != null:
		return "invalid hex must give null"
	return ""


func test_livery_identity_detection() -> String:
	var lv := _lv()
	if not Livery.is_identity(lv, Livery.defaults(lv)) or not Livery.is_identity(lv, {}):
		return "defaults are the identity"
	var c := Livery.defaults(lv)
	c.trim = Livery.parse_hex(Livery.to_hex(c.trim))  # the stored form of the default: still the identity
	if not Livery.is_identity(lv, c):
		return "8-bit stored default"
	c.body = Color(0.9, 0.9, 0.95)
	if Livery.is_identity(lv, c):
		return "a changed colour is not the identity"
	return ""


func test_livery_cache_key_stable_and_sensitive() -> String:
	var a := {"body": Color.RED, "trim": Color.BLUE}
	var b := {"trim": Color.BLUE, "body": Color.RED}  # other insertion order
	var k := Livery.cache_key("c172", a)
	if k != Livery.cache_key("c172", b) or k != Livery.cache_key("c172", a.duplicate()):
		return "same colours, same key"
	if k == Livery.cache_key("c172", {"body": Color.RED, "trim": Color(0, 0, 0.99)}):
		return "a changed colour must change the key"
	if k == Livery.cache_key("a320", a):
		return "another aircraft must change the key"
	if k == Livery.cache_key("c172", {"body": Color.RED}):
		return "a missing region must change the key"
	if Livery.cache_key("c172", {"body": Color(1, 0, 0, 0.5)}) != Livery.cache_key("c172", {"body": Color.RED}):
		return "alpha is not part of the key"
	if k != Livery.cache_key("c172", a, {}):
		return "an empty sticker map must leave the key unchanged"
	var with_sticker := Livery.cache_key("c172", a, {"side": {"image": "abc.png", "scale": 1.0, "dx": 0.0, "dy": 0.0, "mirror": true}})
	if with_sticker == k or not with_sticker.contains("abc.png"):
		return "a sticker must change the key: " + with_sticker
	return ""


func test_livery_recolor_rule_on_pixels() -> String:
	var col := Color(0.8, 0.1, 0.1)
	var px := Color(0.9, 0.9, 0.9, 0.7)
	if not Livery.recolor(px, 0.0, col, 0.9).is_equal_approx(px):
		return "mask 0 must leave the pixel"
	var full := Livery.recolor(px, 1.0, col, 0.9)  # luma(px) == luma_base: gain 1
	if not Color(full.r, full.g, full.b).is_equal_approx(Color(0.8, 0.1, 0.1)):
		return "mask 1, same shading gives the colour: %s" % [full]
	if absf(full.a - 0.7) > 0.0001:
		return "alpha kept: %s" % full.a
	var dark := Livery.recolor(Color(0.45, 0.45, 0.45), 1.0, col, 0.9)  # half as bright: half the colour
	if not Color(dark.r, dark.g, dark.b).is_equal_approx(Color(0.4, 0.05, 0.05)):
		return "shading kept: %s" % [dark]
	if Livery.luma(dark) >= Livery.luma(full):
		return "a darker pixel must stay darker"
	var half := Livery.recolor(px, 0.5, col, 0.9)
	if not Color(half.r, half.g, half.b).is_equal_approx(Color(0.85, 0.5, 0.5)):
		return "mask 0.5 is the middle: %s" % [half]
	var bright := Livery.recolor(Color(1, 1, 1), 1.0, Color(1, 0.4, 0.4), 0.5)  # as bright as the reference: gain 1.3, channels at 1
	if not Color(bright.r, bright.g, bright.b).is_equal_approx(Color(1.0, 0.52, 0.52)):
		return "gain cap: %s" % [bright]
	var tip := Livery.recolor(Color(0.62, 0.62, 0.60), 1.0, Color(0.05, 0.05, 0.06), 0.513)  # grey tip above the stripe reference
	if Livery.luma(tip) > Livery.luma(Color(0.05, 0.05, 0.06)) * 1.05:
		return "a dark colour lit the grey tip: %s" % [tip]
	if Livery.recolor(Color.BLACK, 1.0, col, 0.9).r != 0.0:
		return "black stays black"
	return ""


func test_livery_recolor_multi_matches_single_and_unmixes_edges() -> String:
	var orig := Color(0.7, 0.8, 0.75, 0.9)
	var single := Livery.recolor(orig, 0.6, Color(0.2, 0.5, 0.9), 0.8)
	var multi := Livery.recolor_multi(orig, [0.6, 0.0], [Color(0.2, 0.5, 0.9), Color.RED], [0.8, 0.3])
	if not single.is_equal_approx(multi):
		return "one active region = recolor: %s vs %s" % [single, multi]
	# an edge pixel: half white paint (luma 0.9), half blue paint (luma 0.12); the shading of both is 1
	var white := Color(0.9, 0.9, 0.9)
	var blue := Color(0.0, 0.12, 0.3)
	var edge := white.lerp(blue, 0.5)
	var out := Livery.recolor_multi(edge, [0.5, 0.5], [Color(1, 0.9, 0.2), Color(0.8, 0.0, 0.0)], [Livery.luma(white), Livery.luma(blue)])
	var want := Color(1, 0.9, 0.2).lerp(Color(0.8, 0.0, 0.0), 0.5)
	if absf(out.r - want.r) > 0.02 or absf(out.g - want.g) > 0.02 or absf(out.b - want.b) > 0.02:
		return "edge pixel should be the mix of the two new colours, got %s want %s" % [out, want]
	if absf(out.a - 1.0) > 0.0001:
		return "alpha"
	return ""


func test_livery_regions_on_atlas_capped() -> String:
	var lv := _lv()
	var r := Livery.regions_on(lv, "a")
	if r.size() != 2 or r[0].key != "body" or r[1].key != "trim" or Livery.regions_on(lv, "b").size() != 1 or not Livery.regions_on(lv, "zz").is_empty():
		return "regions_on: %s" % [r]
	var big := {"atlases": [{"id": "a", "texture": "t"}], "regions": []}
	for i in 7:
		big.regions.append({"key": "r%d" % i, "default": [0, 0, 0], "masks": [{"atlas": "a", "mask": "m%d" % i, "luma": 0.5}]})
	return "" if Livery.regions_on(Livery.parse(big), "a").size() == Livery.MAX_SLOTS else "slot cap"


# ---- the C172's masks ----

func _atlas_bytes(def: AircraftDef, rel: String) -> Image:
	var img := (load(def.dir + "/" + rel) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_livery_c172_mask_files_match_atlases() -> String:
	var def := AircraftDef.load_def("c172")
	var lv := Livery.of(def)
	for r in lv.regions:
		for m in r.masks:
			var path: String = def.dir + "/" + m.mask
			if not ResourceLoader.exists(path):
				return "%s missing (run godot --headless --path game --import after tools/25_livery_masks.py)" % m.mask
			var atlas := _atlas_bytes(def, lv.atlases[m.atlas])
			var mask := LiveryPaint.mask_image(def, m.mask)
			if mask == null or mask.get_size() != atlas.get_size():
				return "%s is not the size of its atlas" % m.mask
			var d := mask.get_data()
			var n := 0
			var lo := 0
			var hi := 0
			for i in range(0, d.size(), 7):
				n += 1
				lo += 1 if d[i] == 0 else 0
				hi += 1 if d[i] >= 250 else 0
			var cover := float(hi) / n
			if cover < 0.001 or cover > 0.95 or lo == 0:
				return "%s coverage %.4f, zero pixels %d" % [m.mask, cover, lo]
			var kb := FileAccess.get_file_as_bytes(path).size() / 1024
			if kb > 300:
				return "%s is %d KB (keep masks small)" % [m.mask, kb]
	return ""


func test_livery_c172_masks_keep_registration_boxes_clear() -> String:
	var def := AircraftDef.load_def("c172")
	var lv := Livery.of(def)
	var sec := def.section("registration")
	var checked := 0
	for r in lv.regions:
		for m in r.masks:
			var d := LiveryPaint.mask_image(def, m.mask)
			var w := d.get_width()
			var bytes := d.get_data()
			for t in sec.targets:
				if str(t.get("texture", sec.texture)) != lv.atlases[m.atlas]:
					continue
				checked += 1
				var e: Array = t.erase
				for y in range(int(e[1]), int(e[1]) + int(e[3])):
					for x in range(int(e[0]), int(e[0]) + int(e[2])):
						if bytes[y * w + x] != 0:
							return "%s paints inside the registration box %s at %d,%d" % [m.mask, e, x, y]
	return "" if checked >= 6 else "only %d box/mask pairs were checked" % checked


func test_livery_c172_masks_do_not_overlap_beyond_soft_edges() -> String:
	var def := AircraftDef.load_def("c172")
	var lv := Livery.of(def)
	for atlas in lv.atlases:
		var regs := Livery.regions_on(lv, atlas)
		var data := []
		for r in regs:
			data.append(LiveryPaint.mask_image(def, r.mask).get_data())
		for i in regs.size():
			for j in range(i + 1, regs.size()):
				var both := 0
				var n := 0
				for p in range(0, data[i].size(), 3):
					n += 1
					if data[i][p] > 64 and data[j][p] > 64:
						both += 1
				if float(both) / n > 0.001:  # the soft edge band of a stripe, nothing more
					return "%s/%s overlap on %s: %d of %d samples" % [regs[i].key, regs[j].key, atlas, both, n]
	return ""


func test_livery_c172_luma_matches_the_atlas_under_the_mask() -> String:
	var def := AircraftDef.load_def("c172")
	var lv := Livery.of(def)
	for r in lv.regions:
		for m in r.masks:
			var a := _atlas_bytes(def, lv.atlases[m.atlas]).get_data()
			var d := LiveryPaint.mask_image(def, m.mask).get_data()
			var sum := 0.0
			var n := 0
			for p in range(0, d.size(), 9):
				if d[p] >= 242:
					sum += (0.2126 * a[p * 4] + 0.7152 * a[p * 4 + 1] + 0.0722 * a[p * 4 + 2]) / 255.0
					n += 1
			if n < 100 or absf(sum / n - m.luma) > 0.015:
				return "%s: luma in aircraft.json %.3f, measured %.3f (%d samples)" % [m.mask, m.luma, sum / maxf(n, 1), n]
	return ""
