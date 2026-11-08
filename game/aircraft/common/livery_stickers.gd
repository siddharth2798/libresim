class_name LiveryStickers
extends RefCounted
## Picture slots on a livery. The aircraft declares the boxes (Livery.parse); the pilot's entry is
## {slot: {image, scale, dx, dy, mirror}}. The image is a file name in user://liveries/images/, never
## a path. scale 0.25..1 sizes the picture inside the box (it is contained, not cropped); dx and dy
## -1..1 slide it in the slack that leaves. mirror draws the same fit, flipped, in mirror_box.
## Painted after the colour pass and before the registration (paint_pipeline.gd).


## A stickers dictionary safe to store. Not a dictionary gives {}. Image names lose any directory.
## A slot that still has a field (even just a scale) is kept, so an unfinished entry survives a reload.
static func sanitize(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for k in raw:
		if not k is String or k == "" or not raw[k] is Dictionary:
			continue
		var st: Dictionary = raw[k]
		var e := {}
		if st.has("image"):
			var name := str(st.image).get_file()
			if name != "" and not name.contains("..") and name.get_extension().to_lower() == "png":
				e["image"] = name
		for fld in ["scale", "dx", "dy"]:
			if st.get(fld) is float or st.get(fld) is int:
				e[fld] = float(st[fld])
		if st.get("mirror") is bool:
			e["mirror"] = st.mirror
		if not e.is_empty():
			out[k] = e
	return out


## Slots the pilot has a picture for, ready to stamp: the declaration plus image, scale, dx, dy, mirror.
static func placed(lv: Dictionary, stored: Variant) -> Array:
	var raw: Dictionary = sanitize(stored.get("stickers") if stored is Dictionary else null)
	var out := []
	for slot in lv.get("stickers", []):
		var st = raw.get(slot.key, {})
		if not st is Dictionary or str(st.get("image", "")) == "":
			continue
		var copy: Dictionary = slot.duplicate()
		copy["image"] = st.image
		copy["scale"] = clampf(float(st.get("scale", 1.0)), 0.25, 1.0)
		copy["dx"] = clampf(float(st.get("dx", 0.0)), -1.0, 1.0)
		copy["dy"] = clampf(float(st.get("dy", 0.0)), -1.0, 1.0)
		copy["mirror"] = bool(st.get("mirror", true)) and slot.has("mirror_box")
		out.append(copy)
	return out


## Where the picture sits. `rect` is inside box; `mirror` is inside mirror_box (empty when there is none).
## dx -1 is the left of the slack, +1 the right. The other side is put at the same place on the aircraft (see mirror_turn).
static func fit(iw: int, ih: int, slot: Dictionary) -> Dictionary:
	var dx := float(slot.get("dx", 0.0))
	var dy := float(slot.get("dy", 0.0))
	var rect := _contain(iw, ih, _rect(slot.box), float(slot.get("scale", 1.0)), dx, dy)
	var mirror := Rect2()
	if slot.has("mirror_box"):
		var turned := turn_of(slot) == 180
		mirror = _contain(iw, ih, _rect(slot.mirror_box), float(slot.get("scale", 1.0)), dx if turned else -dx, -dy if turned else dy)
	return {"rect": rect, "mirror": mirror}


static func turn_of(slot: Dictionary) -> int:
	return 180 if int(slot.get("mirror_turn", 0)) == 180 else 0


static func _rect(b: Array) -> Rect2:
	return Rect2(float(b[0]), float(b[1]), float(b[2]), float(b[3]))


static func _contain(iw: int, ih: int, box: Rect2, scale: float, dx: float, dy: float) -> Rect2:
	var aspect := float(maxi(iw, 1)) / float(maxi(ih, 1))
	var w := box.size.x
	var h := w / aspect
	if h > box.size.y:
		h = box.size.y
		w = h * aspect
	w = maxf(1.0, w * clampf(scale, 0.25, 1.0))
	h = maxf(1.0, h * clampf(scale, 0.25, 1.0))
	if w > box.size.x:
		h *= box.size.x / w
		w = box.size.x
	if h > box.size.y:
		w *= box.size.y / h
		h = box.size.y
	var x := box.position.x + (box.size.x - w) * (clampf(dx, -1.0, 1.0) + 1.0) * 0.5
	var y := box.position.y + (box.size.y - h) * (clampf(dy, -1.0, 1.0) + 1.0) * 0.5
	return Rect2(x, y, w, h)


## Draws every placed picture onto the atlas (RGBA8). A missing file is skipped.
static func stamp(atlas: Image, slots: Array) -> void:
	if atlas == null or atlas.is_empty():
		return
	if atlas.get_format() != Image.FORMAT_RGBA8:
		atlas.convert(Image.FORMAT_RGBA8)
	for s in slots:
		var img := LiveryStore.load_image(str(s.get("image", "")))
		if img == null:
			continue
		var where: Dictionary = fit(img.get_width(), img.get_height(), s)
		_blit(atlas, img, where.rect, 0)
		if s.get("mirror", false):
			_blit(atlas, img, where.mirror, turn_of(s))


static func _blit(atlas: Image, img: Image, rect: Rect2, turn: int) -> void:
	var dw := maxi(1, int(floor(rect.size.x)))
	var dh := maxi(1, int(floor(rect.size.y)))
	var x := int(floor(rect.position.x))
	var y := int(floor(rect.position.y))
	if x >= atlas.get_width() or y >= atlas.get_height() or x + dw <= 0 or y + dh <= 0:
		return
	var copy := img.duplicate()
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	if turn == 180:
		copy.rotate_180()
	copy.resize(dw, dh, Image.INTERPOLATE_LANCZOS)
	atlas.blend_rect(copy, Rect2i(0, 0, dw, dh), Vector2i(x, y))
