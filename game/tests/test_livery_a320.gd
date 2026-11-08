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


## The sticker rectangles have to fall on the skin the label names. An earlier pair sat on the
## wings and the crown, so a picture never showed on the fuselage side or the fin.
func test_livery_a320_stickers_land_on_the_side_and_the_fin() -> String:
	var def := AircraftDef.load_def("a320")
	var root := (load(def.path("exterior")) as PackedScene).instantiate()
	var tex := def.dir + "/models/exterior_fuselage.png"
	var side: Array = []
	var fin: Array = []
	for s in Livery.of(def).stickers:
		if s.key == "side":
			side = [s.box, s.mirror_box]
		elif s.key == "fin":
			fin = [s.box, s.mirror_box]
	if side.size() != 2 or fin.size() != 2:
		root.free()
		return "the fuselage side and the fin each need a box and the other side"
	var reg: Array = def.section("registration").targets
	for box in side + fin:
		for t in reg:
			if _rects_overlap(box, t.erase):
				root.free()
				return "a sticker box overlaps the registration: %s" % [box]
	var err := ""
	err = _expect(root, tex, side[0], "side", 1.0) if err == "" else err
	err = _expect(root, tex, side[1], "side", -1.0) if err == "" else err
	err = _expect(root, tex, fin[0], "fin", 1.0) if err == "" else err
	err = _expect(root, tex, fin[1], "fin", -1.0) if err == "" else err
	root.free()
	return err


func _rects_overlap(a: Array, b: Array) -> bool:
	return not (a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1])


func _expect(root: Node, tex: String, box: Array, kind: String, side: float) -> String:
	var pts: Array[Vector3] = []
	for i in 3:
		for j in 3:
			var u := (float(box[0]) + float(box[2]) * (0.2 + 0.3 * i)) / 4096.0
			var v := (float(box[1]) + float(box[3]) * (0.2 + 0.3 * j)) / 4096.0
			var hit: Variant = _box_uv(root, tex, Vector2(u, v))
			if hit is Vector3:
				pts.append(hit as Vector3)
	if pts.size() < 7:
		return "%s box %s only hit the mesh %d/9 times" % [kind, box, pts.size()]
	var lo := pts[0]
	var hi := pts[0]
	var acc := Vector3.ZERO
	for p in pts:
		acc += p
		lo = lo.min(p)
		hi = hi.max(p)
	var mean := acc / pts.size()
	var span := hi - lo
	if kind == "side":
		if absf(mean.z) < 1.5 or signf(mean.z) != side or span.x > 3.0 or span.y > 1.5:
			return "fuselage side %s is not a patch on the tube: mean %s span %s" % [box, mean, span]
	elif mean.x < 13.0 or mean.y < 3.0 or signf(mean.z) != side or span.x > 1.6 or span.y > 1.6:
		return "fin %s is not a patch on one side of the fin: mean %s span %s" % [box, mean, span]
	return ""


func _box_uv(root: Node, tex: String, p: Vector2) -> Variant:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		var xf := (mi as MeshInstance3D).transform
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null or mat.albedo_texture.resource_path != tex:
				continue
			var arr: Array = mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var id: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if uv.is_empty():
				continue
			var tris := id.size() / 3 if id.size() > 0 else vs.size() / 3
			for t in tris:
				var i0 := id[t * 3] if id.size() > 0 else t * 3
				var i1 := id[t * 3 + 1] if id.size() > 0 else t * 3 + 1
				var i2 := id[t * 3 + 2] if id.size() > 0 else t * 3 + 2
				var a := uv[i0]
				var b := uv[i1]
				var c := uv[i2]
				if p.x < minf(a.x, minf(b.x, c.x)) or p.x > maxf(a.x, maxf(b.x, c.x)):
					continue
				if p.y < minf(a.y, minf(b.y, c.y)) or p.y > maxf(a.y, maxf(b.y, c.y)):
					continue
				var w := _bary(a, b, c, p)
				if w.x < -0.02 or w.y < -0.02 or w.z < -0.02:
					continue
				return xf * (vs[i0] * w.x + vs[i1] * w.y + vs[i2] * w.z)
	return null


func _bary(a: Vector2, b: Vector2, c: Vector2, p: Vector2) -> Vector3:
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1e-8:
		return Vector3(-1, -1, -1)
	var wa := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
	var wb := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
	return Vector3(wa, wb, 1.0 - wa - wb)
