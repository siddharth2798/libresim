class_name ApronMask
extends RefCounted
## Airside mask of the airport nearest the camera, for the terrain's night ground (terrain_night.gdshaderinc):
## WorldCover marks most airports "built-up", so the city-light speckle (small round orange / white discs of
## street lamps and windows) was drawn on aprons, taxiways and runways. A small greyscale texture over the
## airport (1 = airside: stands, taxiways, runways, soft-edged by the linear filter) is published as the global
## `apron_mask` with its box `apron_mask_box` (pattern frame: world ENU - FloatingOrigin.wrap_base_value(),
## like the shader's v_en); the speckle is left out where it is 1. Box (0, 0, 0, 0) = no mask.

const PX_M := 8.0  # metres per texel
const MAX_PX := 512
const PAD := 120.0


## [Image, Rect2 (ENU)] for one airport: ops = its airport_ops.json entry, runways = its runways.json entries.
static func paint(ops: Dictionary, runways: Array) -> Array:
	var pts := PackedVector2Array()
	for s in ops.get("stands", []):
		pts.append(Vector2(s.x, s.y))
	var nodes: Dictionary = ops.get("taxi", {}).get("nodes", {})
	for k in nodes:
		pts.append(Vector2(nodes[k][0], nodes[k][1]))
	for r in runways:
		for e in r.ends:
			pts.append(Vector2(e.x, e.y))
	if pts.is_empty():
		return []
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var box := Rect2(lo - Vector2(PAD, PAD), hi - lo + Vector2(PAD, PAD) * 2.0)
	var px := maxf(PX_M, maxf(box.size.x, box.size.y) / MAX_PX)
	var w := clampi(ceili(box.size.x / px), 4, MAX_PX)
	var h := clampi(ceili(box.size.y / px), 4, MAX_PX)
	box.size = Vector2(w, h) * px
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0))
	var stamp := func(c: Vector2, r: float) -> void:  # a square of side 2 r (native fill; the filter softens it)
		var q := (c - box.position) / px
		var rp := r / px
		img.fill_rect(Rect2i(floori(q.x - rp), h - ceili(q.y + rp), ceili(rp * 2.0), ceili(rp * 2.0)), Color(1, 1, 1))  # row 0 = north
	var line := func(a: Vector2, b: Vector2, half: float) -> void:
		var n := maxi(ceili(a.distance_to(b) / maxf(half * 0.7, px)), 1)
		for i in n + 1:
			stamp.call(a.lerp(b, float(i) / n), half)
	for s in ops.get("stands", []):
		stamp.call(Vector2(s.x, s.y), 30.0 if ApronLightLayout.is_ga(s) else 70.0)
	for e in ops.get("taxi", {}).get("edges", []):
		if nodes.has(e[0]) and nodes.has(e[1]):
			line.call(Vector2(nodes[e[0]][0], nodes[e[0]][1]), Vector2(nodes[e[1]][0], nodes[e[1]][1]), 35.0)
	for r in runways:
		line.call(Vector2(r.ends[0].x, r.ends[0].y), Vector2(r.ends[1].x, r.ends[1].y), float(r.width) * 0.5 + 30.0)
	return [img, box]


## Publish a painted mask (or none: []).
static func publish(m: Array) -> void:
	if m.is_empty():
		RenderingServer.global_shader_parameter_set("apron_mask_box", Vector4.ZERO)
		return
	RenderingServer.global_shader_parameter_set("apron_mask", ImageTexture.create_from_image(m[0]))
	place(m[1])


## The box in the pattern frame (call again after a floating-origin shift: the wrap base may move).
static func place(box: Rect2) -> void:
	var b := box.position - FloatingOrigin.wrap_base_value()
	RenderingServer.global_shader_parameter_set("apron_mask_box", Vector4(b.x, b.y, box.size.x, box.size.y))


## 0..1 mask value at ENU p (CPU mirror of the shader lookup, for tests).
static func sample(m: Array, p: Vector2) -> float:
	var box: Rect2 = m[1]
	var img: Image = m[0]
	var q := (p - box.position) / box.size
	if q.x < 0.0 or q.y < 0.0 or q.x >= 1.0 or q.y >= 1.0:
		return 0.0
	return img.get_pixel(int(q.x * img.get_width()), int((1.0 - q.y) * img.get_height())).r
