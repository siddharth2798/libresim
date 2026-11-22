class_name RunwayGlyphs
extends RefCounted
## Runway designator glyphs (digits 0-9, L, C, R) as one texture atlas for world/runway_v2.gdshader, drawn once at
## runtime from rectangles, ring sectors and slanted bars in a 3 x 9 m box (Annex 14 figure 5-3 proportions, the
## blocky stroke style of painted runway numbers). No font, nothing to license.
## Atlas: COUNT cells side by side, each CELL metres (the 3 x 9 m box plus a MARGIN all round) at PPM pixels per metre,
## coverage in an L8 image with mipmaps. Glyph y is up = away from the threshold (the shader reads it that way).
## Index: 0-9 digits, 10 L, 11 C, 12 R (RunwayMarkings.glyph).

const COUNT := 13
const CELL := Vector2(4.0, 10.0)
const MARGIN := 0.5
const PPM := 32
const SUPER := 2  # drawn at 2x and filtered down: anti-aliased edges
const W := 3.0
const H := 9.0
const T := 0.75  # stroke width
const R_OUT := 1.5
const R_IN := 0.75

static var _tex: ImageTexture


## The atlas texture (built on first use, then shared by every runway material).
static func texture() -> ImageTexture:
	if _tex == null:
		_tex = ImageTexture.create_from_image(atlas())
	return _tex


static func atlas() -> Image:
	var ppm := PPM * SUPER
	var cw := int(CELL.x * ppm)
	var ch := int(CELL.y * ppm)
	var img := Image.create_empty(cw * COUNT, ch, false, Image.FORMAT_L8)
	for g in COUNT:
		for poly in polys(g):
			_fill(img, poly, g * cw, ch, ppm)
	img.resize(cw * COUNT / SUPER, ch / SUPER, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return img


## Convex polygons (glyph metres, origin bottom-left of the 3 x 9 box, y up) making up glyph g.
static func polys(g: int) -> Array:
	var p := []
	match g:
		0:
			p = _arc(1.5, 7.5, 0, 180) + _arc(1.5, 1.5, 180, 360) + [_rect(0, 1.5, T, 7.5), _rect(W - T, 1.5, W, 7.5)]
		1:
			p = [_rect(1.125, 0, 1.875, H), PackedVector2Array([Vector2(0.35, 7.5), Vector2(1.2, 8.15), Vector2(1.2, 9.0), Vector2(0.35, 8.35)])]
		2:
			p = _arc(1.5, 7.5, 0, 180) + [_rect(0, 6.6, T, 7.5), _rect(W - T, 5.6, W, 7.5), _slant(0.375, T, 2.625, 5.6, 0.375), _rect(0, 0, W, T)]
		3:
			p = [_rect(0, H - T, W, H), _slant(1.05, 5.25, 2.55, H - T, 0.42),
				PackedVector2Array([Vector2(0.6, 5.25), Vector2(1.5, 5.25), Vector2(1.5, 6.0), Vector2(1.0, 6.0)])] \
				+ _arc(1.5, 4.5, 0, 90) + [_rect(W - T, 1.5, W, 4.5)] + _arc(1.5, 1.5, 180, 360) + [_rect(0, 1.5, T, 2.4)]
		4:
			p = [_rect(1.95, 0, 2.7, H), _slant(0.42, 2.4, 2.25, H, 0.42),
				PackedVector2Array([Vector2(0, 2.4), Vector2(W, 2.4), Vector2(W, 3.15), Vector2(0.21, 3.15)])]  # crossbar meets the slant
		5:
			p = [_rect(0, H - T, W, H), _rect(0, 5.25, T, H), _rect(0, 5.25, 1.5, 6.0)] + _arc(1.5, 4.5, 0, 90) \
				+ [_rect(W - T, 1.5, W, 4.5)] + _arc(1.5, 1.5, 180, 360) + [_rect(0, 1.5, T, 2.4)]
		6:
			p = _six()
		7:
			p = [_rect(0, H - T, W, H), _slant(0.95, 0, 2.58, H - T, 0.42)]
		8:
			p = _arc(1.5, 7.5, 0, 180) + [_rect(0, 5.625, T, 7.5), _rect(W - T, 5.625, W, 7.5)] + _arc(1.5, 5.625, 180, 360) \
				+ _arc(1.5, 1.5, 180, 360) + [_rect(0, 1.5, T, 3.375), _rect(W - T, 1.5, W, 3.375)] + _arc(1.5, 3.375, 0, 180)
		9:
			for q in _six():  # a 6 turned half round
				var r := PackedVector2Array()
				for v in q:
					r.append(Vector2(W - v.x, H - v.y))
				p.append(r)
		10:
			p = [_rect(0, 0, T, H), _rect(0, 0, W, T)]
		11:
			p = _arc(1.5, 7.5, 25, 180) + [_rect(0, 1.5, T, 7.5)] + _arc(1.5, 1.5, 180, 335)
		12:
			p = [_rect(0, 0, T, H), _rect(0, H - T, 1.5, H)] + _arc(1.5, 7.5, 0, 90) + [_rect(W - T, 6.0, W, 7.5)] \
				+ _arc(1.5, 6.0, 270, 360) + [_rect(0, 4.5, 1.5, 5.25), _slant(2.58, 0, 1.3, 4.9, 0.42)]
	return p


static func _six() -> Array:
	return [_rect(0, 1.5, T, 7.5)] + _arc(1.5, 7.5, 30, 180) + _arc(1.5, 1.5, 180, 360) + [_rect(W - T, 1.5, W, 3.75)] \
		+ _arc(1.5, 3.75, 0, 180)


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## Bar from (xb, yb) to (xt, yt) with horizontal ends, hw the horizontal half-width.
static func _slant(xb: float, yb: float, xt: float, yt: float, hw: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(xb - hw, yb), Vector2(xb + hw, yb), Vector2(xt + hw, yt), Vector2(xt - hw, yt)])


## Ring sector (stroke T around radius R_OUT) from angle a0 to a1 (degrees, 0 = +x, 90 = up), as 10-degree quads.
static func _arc(cx: float, cy: float, a0: float, a1: float) -> Array:
	var out := []
	var n := maxi(int(ceil((a1 - a0) / 10.0)), 1)
	for i in n:
		var u := deg_to_rad(lerpf(a0, a1, float(i) / n))
		var v := deg_to_rad(lerpf(a0, a1, float(i + 1) / n))
		var c := Vector2(cx, cy)
		out.append(PackedVector2Array([c + Vector2(cos(u), sin(u)) * R_IN, c + Vector2(cos(u), sin(u)) * R_OUT,
			c + Vector2(cos(v), sin(v)) * R_OUT, c + Vector2(cos(v), sin(v)) * R_IN]))
	return out


## Fills a convex polygon row by row (spans from its edge crossings at each row centre).
static func _fill(img: Image, poly: PackedVector2Array, x0: int, ch: int, ppm: int) -> void:
	var ylo := INF
	var yhi := -INF
	for v in poly:
		ylo = minf(ylo, v.y)
		yhi = maxf(yhi, v.y)
	var top := CELL.y - MARGIN  # glyph y of row 0's top edge
	var r0 := clampi(int(floor((top - yhi) * ppm)), 0, ch - 1)
	var r1 := clampi(int(ceil((top - ylo) * ppm)), 0, ch - 1)
	var n := poly.size()
	for row in range(r0, r1 + 1):
		var gy := top - (row + 0.5) / ppm
		var xl := INF
		var xr := -INF
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y - gy) * (b.y - gy) > 0.0 or a.y == b.y:
				continue
			var xc := a.x + (gy - a.y) / (b.y - a.y) * (b.x - a.x)
			xl = minf(xl, xc)
			xr = maxf(xr, xc)
		if xl >= xr:
			continue
		var px0 := x0 + int(round((xl + MARGIN) * ppm))
		var px1 := x0 + int(round((xr + MARGIN) * ppm))
		if px1 > px0:
			img.fill_rect(Rect2i(px0, row, px1 - px0, 1), Color.WHITE)
