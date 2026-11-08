class_name Livery
extends RefCounted
## Pilot-chosen paint colours: pure logic, no rendering (the GPU pass is livery_paint.gd + livery.gdshader).
## aircraft.json "livery" (made by tools/25_livery_masks.py):
##   atlases  [{id, texture}]  exterior atlases that carry paint (texture relative to the aircraft folder)
##   regions  [{key, label, default [r,g,b] 0..1, masks [{atlas, mask, luma}]}]  a region may be on several
##            atlases; mask = 8-bit grey PNG (0 untouched, 255 recoloured), luma = mean luminance of the
##            atlas under the mask at full strength (>= 242), the shading reference
## The pilot's choice is {region key: "#rrggbb"} in Session.setup.livery; a missing or invalid entry is the
## factory colour. "stickers" on the section are the fixed picture slots (box, optional mirror_box).
## Nothing here knows a specific aircraft. paint_pipeline.gd applies it.
## Recolour (sRGB, Rec.709): lerp(orig, colour * gain, mask). gain = luma(orig) / luma_base, capped at
## GAIN_MAX. The part of that gain above 1 is scaled by luma(colour) / luma_base, so a dark colour does not
## light a lighter grey texel (the pin-stripe tip). recolor_multi splits the luminance where regions meet.

const GAIN_MAX := 1.3  # a region brighter than its mean may be lifted this much, no more
const MAX_SLOTS := 4  # regions per atlas the shader takes in one pass (livery.gdshader)
const KEY_VERSION := 1  # bump when masks or the rule change: old cached textures are then not reused


## The tolerant parse of the "livery" section: {"atlases": {id: texture}, "regions": [{key, label, default: Color,
## masks: [{atlas, mask, luma}]}]}. Anything malformed is dropped; unknown or missing = an empty livery.
static func parse(section: Variant) -> Dictionary:
	var out := {"atlases": {}, "regions": [], "stickers": []}
	if not section is Dictionary:
		return out
	var raw_atlases = section.get("atlases")
	if raw_atlases is Array:
		for a in raw_atlases:
			if a is Dictionary and a.get("id") is String and a.get("texture") is String and a.id != "" and a.texture != "":
				out.atlases[a.id] = a.texture
	var seen := {}
	var raw_regions = section.get("regions")
	if raw_regions is Array:
		for r in raw_regions:
			_region(out, seen, r)
	out.stickers = _slots(section, out.atlases)
	return out


static func _region(out: Dictionary, seen: Dictionary, r: Variant) -> void:
	if not r is Dictionary or not r.get("key") is String or r.key == "" or seen.has(r.key):
		return
	var d = r.get("default")
	if not d is Array or d.size() != 3:
		return
	for v in d:
		if not (v is float or v is int) or v < 0.0 or v > 1.0:
			return
	var masks := []
	var raw_masks = r.get("masks")
	for m in (raw_masks if raw_masks is Array else []):
		if m is Dictionary and m.get("atlas") is String and out.atlases.has(m.atlas) and m.get("mask") is String \
				and m.mask != "" and (m.get("luma") is float or m.get("luma") is int) and m.luma > 0.0:
			masks.append({"atlas": m.atlas, "mask": m.mask, "luma": float(m.luma)})
	if masks.is_empty():
		return
	seen[r.key] = true
	out.regions.append({"key": r.key, "label": str(r.get("label", r.key)), "default": Color(d[0], d[1], d[2]), "masks": masks})


## Fixed picture slots: [{key, label, atlas, box [x,y,w,h], mirror_box?, mirror_turn}]. A bad box or an unknown atlas is dropped.
## mirror_turn (0 or 180, default 0): how the atlas lays the other side out. 0 = the strip is reflected left to right (the
## picture reads upright as it is); 180 = the strip is turned half a round (the picture is turned with it).
static func _slots(section: Dictionary, atlases: Dictionary) -> Array:
	var raw = section.get("stickers")
	if not raw is Array:
		return []
	var out := []
	var seen := {}
	for s in raw:
		if not s is Dictionary or not s.get("key") is String or s.key == "" or seen.has(s.key):
			continue
		if not s.get("atlas") is String or not atlases.has(s.atlas):
			continue
		var box := _box(s.get("box"))
		if box.is_empty():
			continue
		var slot := {"key": s.key, "label": str(s.get("label", s.key)), "atlas": s.atlas, "box": box}
		var mirror := _box(s.get("mirror_box"))
		if not mirror.is_empty():
			slot["mirror_box"] = mirror
			slot["mirror_turn"] = 180 if int(s.get("mirror_turn", 0)) == 180 else 0
		seen[s.key] = true
		out.append(slot)
	return out


static func _box(v: Variant) -> Array:
	if not v is Array or v.size() != 4:
		return []
	var b := []
	for n in v:
		if not (n is float or n is int) or n < 0:
			return []
		b.append(int(n))
	return [] if b[2] < 1 or b[3] < 1 else b


## The parsed livery of an aircraft (empty when it has none).
static func of(def: AircraftDef) -> Dictionary:
	return parse(def.section("livery"))


## {key: Color} factory colours.
static func defaults(lv: Dictionary) -> Dictionary:
	var out := {}
	for r in lv.regions:
		out[r.key] = r.default
	return out


## "#rrggbb" of a colour (alpha dropped, 8-bit rounded).
static func to_hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Colour of "#rrggbb" or "rrggbb" (exactly six hex digits, any case); null for anything else.
static func parse_hex(s: Variant) -> Variant:
	if not s is String:
		return null
	var t: String = s.strip_edges().trim_prefix("#")
	if t.length() != 6 or not t.is_valid_hex_number():
		return null
	return Color.html("#" + t)


## The colours to paint with: the factory colour of every region, overridden by the valid entries of `stored`, which is the
## pilot's {key: "#rrggbb"} (or the setup entry {colors: {key: ...}}). Unknown keys and bad hex are ignored. {key: Color}.
static func colors_of(lv: Dictionary, stored: Variant) -> Dictionary:
	var out := defaults(lv)
	if stored is Dictionary and stored.get("colors") is Dictionary:
		stored = stored.colors
	if not stored is Dictionary:
		return out
	for k in out.keys():
		var c = parse_hex(stored.get(k))
		if c != null:
			out[k] = c
	return out


## The regions of this atlas only, {key: Color} (a region at the factory colour included): what one atlas' paint depends on.
static func colors_on(lv: Dictionary, atlas_id: String, colors: Dictionary) -> Dictionary:
	var out := {}
	for r in regions_on(lv, atlas_id):
		var c = colors.get(r.key, r.default)
		out[r.key] = c if c is Color else r.default
	return out


## ---- Session.setup.livery: {aircraft id: {colors: {region key: "#rrggbb"}, ...}}; a missing entry = factory ----

## The entry of one aircraft ({} = factory livery); anything that is not a dictionary is {}.
static func entry(all: Variant, aircraft_id: String) -> Dictionary:
	if all is Dictionary and all.get(aircraft_id) is Dictionary:
		return all[aircraft_id]
	return {}


## `all` as it may be stored or loaded, made safe: not a dictionary gives {}, an unknown aircraft or one without a livery is dropped,
## unknown regions and bad hex are dropped, colours are written as lowercase "#rrggbb", an entry left with nothing is dropped.
## A stickers dictionary is kept when it still has a usable field after LiveryStickers.sanitize (image names
## lose any directory; a slot with only a scale is kept). Never raises.
static func repair_setup(all: Variant) -> Dictionary:
	var out := {}
	if not all is Dictionary:
		return out
	var ids := AircraftDef.list_ids()
	for id in all:
		if not id is String or not id in ids or not all[id] is Dictionary:
			continue
		var lv := of(AircraftDef.load_def(id))
		var colors := {}
		var raw = all[id].get("colors")
		if raw is Dictionary:
			for r in lv.regions:
				var c = parse_hex(raw.get(r.key))
				if c != null:
					colors[r.key] = to_hex(c)
		var e := {}
		if not colors.is_empty():
			e["colors"] = colors
		var stickers := LiveryStickers.sanitize(all[id].get("stickers"))
		if not stickers.is_empty():
			e["stickers"] = stickers
		if not e.is_empty():
			out[id] = e
	return out


## The command-line value of --livery: "body=#c8101a,accent=#f2f2f2" for `default_id`, or per aircraft "c172:body=#c8101a,a320:fin=#102030"
## (a bare "rrggbb" is fine too). Bad items are skipped. Result in the shape of Session.setup.livery (regions are not checked
## here: repair_setup does that).
static func parse_cli(v: String, default_id: String) -> Dictionary:
	var out := {}
	for item in v.split(",", false):
		var kv := item.split("=", true, 1)
		if kv.size() != 2:
			continue
		var head := kv[0].strip_edges().split(":", true, 1)
		var id := head[0].strip_edges().to_lower() if head.size() == 2 else default_id
		var key := head[head.size() - 1].strip_edges()
		var c = parse_hex(kv[1])
		if id == "" or key == "" or c == null:
			continue
		if not out.has(id):
			out[id] = {"colors": {}}
		out[id].colors[key] = to_hex(c)
	return out


## True when every colour is its factory colour (compared at 8 bits, how it is stored): nothing to paint.
static func is_identity(lv: Dictionary, colors: Dictionary) -> bool:
	for r in lv.regions:
		var c = colors.get(r.key, r.default)
		if not c is Color or to_hex(c) != to_hex(r.default):
			return false
	return true


## A stable text key of (aircraft, colours, stickers) for texture caches. The same colours give the same key
## whatever the order of the dictionary. An empty sticker map leaves the key exactly as it was before stickers
## existed, so a factory paint stays a cache hit. Any real sticker changes the key.
static func cache_key(aircraft_id: String, colors: Dictionary, stickers: Dictionary = {}) -> String:
	var keys := colors.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k in keys:
		var c = colors[k]
		parts.append("%s=%s" % [k, to_hex(c) if c is Color else "?"])
	var base := "livery%d|%s|%s" % [KEY_VERSION, aircraft_id, ";".join(parts)]
	if stickers.is_empty():
		return base
	var sk := stickers.keys()
	sk.sort()
	var bits := PackedStringArray()
	for k in sk:
		var st = stickers[k]
		if st is Dictionary:
			bits.append("%s:%s:%.2f:%.2f:%.2f:%d" % [k, str(st.get("image", "")).get_file(),
				float(st.get("scale", 1.0)), float(st.get("dx", 0.0)), float(st.get("dy", 0.0)),
				1 if st.get("mirror", true) else 0])
	return base + "|" + ";".join(bits)


## The regions with a mask on this atlas, at most MAX_SLOTS: [{key, mask (path relative to the aircraft folder), luma, default}].
static func regions_on(lv: Dictionary, atlas_id: String) -> Array:
	var out := []
	for r in lv.regions:
		for m in r.masks:
			if m.atlas == atlas_id and out.size() < MAX_SLOTS:
				out.append({"key": r.key, "mask": m.mask, "luma": m.luma, "default": r.default})
	return out


## Rec.709 luminance of the stored (sRGB) values.
static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## `recovered` is the texel's luminance, or what remains after the other regions' share. Lift above 1 scales
## with luma(colour) / luma_base, so a dark colour does not light a grey tip.
static func _gain(recovered: float, luma_base: float, colour: Color) -> float:
	var raw := clampf(recovered / maxf(luma_base, 0.0001), 0.0, GAIN_MAX)
	var room := clampf(luma(colour) / maxf(luma_base, 0.0001), 0.0, 1.0)
	return minf(raw, 1.0) + maxf(raw - 1.0, 0.0) * room


## One region on one pixel (the single-region case of recolor_multi); the alpha of `orig` is kept.
static func recolor(orig: Color, mask: float, colour: Color, luma_base: float) -> Color:
	var gain := _gain(luma(orig), luma_base, colour)
	var tint := Color(minf(colour.r * gain, 1.0), minf(colour.g * gain, 1.0), minf(colour.b * gain, 1.0))
	var m := clampf(mask, 0.0, 1.0)
	return Color(lerpf(orig.r, tint.r, m), lerpf(orig.g, tint.g, m), lerpf(orig.b, tint.b, m), orig.a)


## Several regions on one pixel, exactly what livery.gdshader does: `masks`, `colours`, `lumas` are parallel arrays.
## The weights are added up (scaled down when they exceed 1), and each region takes the shading left after the other
## regions' share of the pixel is taken out, so an edge between two paints is not darkened by the other one.
static func recolor_multi(orig: Color, masks: Array, colours: Array, lumas: Array) -> Color:
	var n := masks.size()
	var w := []
	var total := 0.0
	for i in n:
		total += clampf(masks[i], 0.0, 1.0)
	var scale := 1.0 / maxf(total, 1.0)
	var wn := minf(total, 1.0)
	for i in n:
		w.append(clampf(masks[i], 0.0, 1.0) * scale)
	var l := luma(orig)
	var rgb := Vector3(orig.r, orig.g, orig.b) * (1.0 - wn)
	for i in n:
		var others := 0.0
		for j in n:
			if j != i:
				others += w[j] * lumas[j]
		var li := maxf((l * wn - others) / maxf(w[i], 0.001), 0.0)  # w ~ 0: its own term is ~ 0 as well
		var c: Color = colours[i]
		var gain := _gain(li, lumas[i], c)
		rgb += w[i] * Vector3(minf(c.r * gain, 1.0), minf(c.g * gain, 1.0), minf(c.b * gain, 1.0))
	return Color(rgb.x, rgb.y, rgb.z, orig.a)
