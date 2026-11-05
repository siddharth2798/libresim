extends RefCounted
## The A320 masks (tools/25_a320_livery_masks.py) follow the same rules as the C172's: atlas size,
## coverage, file size, luma, no overlap past a soft edge, and the registration boxes stay clear.
## Wings are not a region. Both registration rectangles stay empty, including the side that is
## not wired up in aircraft.json yet.

const PENDING := [2640, 1250, 220, 80]


func _atlas_bytes(def: AircraftDef, rel: String) -> Image:
	var img := (load(def.dir + "/" + rel) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func test_livery_a320_masks_match_the_atlases() -> String:
	var def := AircraftDef.load_def("a320")
	var lv := Livery.of(def)
	if lv.regions.size() != 4 or lv.stickers.size() != 2:
		return "expected fuselage, fin, cheat line, engines and two sticker slots: %d / %d" % [lv.regions.size(), lv.stickers.size()]
	var per := {}
	for r in lv.regions:
		for m in r.masks:
			per[m.atlas] = int(per.get(m.atlas, 0)) + 1
			if per[m.atlas] > Livery.MAX_SLOTS:
				return "%s has more than %d regions" % [m.atlas, Livery.MAX_SLOTS]
			var path: String = def.dir + "/" + m.mask
			if not ResourceLoader.exists(path):
				return "%s missing (godot --headless --path game --import after tools/25_a320_livery_masks.py)" % m.mask
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
			if FileAccess.get_file_as_bytes(path).size() / 1024 > 300:
				return "%s is too large" % m.mask
	if not per.has("fuselage") or per.fuselage != 3 or per.get("engine", 0) != 1:
		return "regions per atlas: %s" % [per]
	return ""


func test_livery_a320_luma_and_no_overlap_and_registration_clear() -> String:
	var def := AircraftDef.load_def("a320")
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
				return "%s: luma %.3f measured %.3f" % [m.mask, m.luma, sum / maxf(n, 1)]
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
				if float(both) / n > 0.001:
					return "%s/%s overlap on %s" % [regs[i].key, regs[j].key, atlas]
	var sec := def.section("registration")
	var boxes := []
	for t in sec.targets:
		boxes.append(t.erase)
	boxes.append(PENDING)
	for r in lv.regions:
		for m in r.masks:
			if lv.atlases[m.atlas] != sec.texture:
				continue
			var d := LiveryPaint.mask_image(def, m.mask)
			var bytes := d.get_data()
			var w := d.get_width()
			for e in boxes:
				for y in range(int(e[1]), int(e[1]) + int(e[3]), 2):
					for x in range(int(e[0]), int(e[0]) + int(e[2]), 2):
						if bytes[y * w + x] != 0:
							return "%s paints inside %s" % [m.mask, e]
	return ""
