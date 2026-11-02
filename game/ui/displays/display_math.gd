class_name DispMath
extends RefCounted
## Pure geometry and scale helpers for the glass displays (ui/displays/*): tape positions, polygon
## and line clipping, rotation, non-linear scales, map projection. No drawing, no Props, so they are
## unit-tested in tests/test_displays.gd. Screen space: x right, y down (px).


## Screen y of `value` on a vertical tape whose centre line (centre_y) shows `centre_value`.
static func tape_y(value: float, centre_value: float, px_per_unit: float, centre_y: float) -> float:
	return centre_y - (value - centre_value) * px_per_unit


## The multiples of `step` that are visible on a tape of half height `half_h` around `centre_value`.
static func tape_marks(centre_value: float, px_per_unit: float, half_h: float, step: float) -> Array:
	var span := half_h / px_per_unit
	var out := []
	for i in range(int(ceilf((centre_value - span) / step)), int(floorf((centre_value + span) / step)) + 1):
		out.append(i * step)
	return out


## Shortest signed difference a - b of two bearings (deg), in -180..180.
static func wrap180(d: float) -> float:
	return fposmod(d + 180.0, 360.0) - 180.0


## Screen x of heading `h` on a horizontal tape that shows `centre_h` at centre_x.
static func hdg_x(h: float, centre_h: float, px_per_deg: float, centre_x: float) -> float:
	return centre_x + wrap180(h - centre_h) * px_per_deg


## Point on a compass arc: 0 = up, clockwise positive (rad), radius r around c.
static func polar(c: Vector2, r: float, a: float) -> Vector2:
	return c + Vector2(sin(a), -cos(a)) * r


## Vertical speed scale: fraction (-1..1) of the half height for a rate in ft/min. Linear to 1000
## (0.4), slower to 2000 (0.7), slowest to 6000 (1.0), like an airliner VS scale.
static func vs_frac(fpm: float) -> float:
	var a := absf(fpm)
	var f := 0.0
	if a <= 1000.0:
		f = a / 1000.0 * 0.4
	elif a <= 2000.0:
		f = 0.4 + (a - 1000.0) / 1000.0 * 0.3
	else:
		f = minf(0.7 + (a - 2000.0) / 4000.0 * 0.3, 1.0)
	return f * signf(fpm)


## Map projection for the navigation display: a point `rel` (east, north metres from the aircraft)
## to screen, heading `hdg_rad` up, `range_m` mapped to `radius_px` around `centre`.
static func nd_project(rel: Vector2, hdg_rad: float, range_m: float, centre: Vector2, radius_px: float) -> Vector2:
	var x := rel.x * cos(hdg_rad) - rel.y * sin(hdg_rad)
	var fwd := rel.x * sin(hdg_rad) + rel.y * cos(hdg_rad)
	return centre + Vector2(x, -fwd) * (radius_px / range_m)


## Point of the attitude sphere: `local` is drawn as if the aircraft were level (horizon through
## c + (0, pitch_px)); the whole sphere is then rolled about c by the bank (right wing down = positive).
static func sphere_point(local: Vector2, c: Vector2, roll_rad: float) -> Vector2:
	return (local - c).rotated(-roll_rad) + c


## Liang-Barsky: the part of segment a-b inside rect r, empty if none.
static func clip_line(a: Vector2, b: Vector2, r: Rect2) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for k in 4:
		var p := 0.0
		var q := 0.0
		match k:
			0:
				p = -d.x
				q = a.x - r.position.x
			1:
				p = d.x
				q = r.end.x - a.x
			2:
				p = -d.y
				q = a.y - r.position.y
			_:
				p = d.y
				q = r.end.y - a.y
		if is_zero_approx(p):
			if q < 0.0:
				return PackedVector2Array()
			continue
		var t := q / p
		if p < 0.0:
			if t > t1:
				return PackedVector2Array()
			t0 = maxf(t0, t)
		else:
			if t < t0:
				return PackedVector2Array()
			t1 = minf(t1, t)
	return PackedVector2Array([a + d * t0, a + d * t1])


## Sutherland-Hodgman: polygon clipped to rect r (convex clip region).
static func clip_poly(pts: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var out := pts
	for edge in 4:
		var src := out
		out = PackedVector2Array()
		if src.is_empty():
			break
		var prev := src[src.size() - 1]
		for cur in src:
			var cin := _inside(cur, r, edge)
			if cin != _inside(prev, r, edge):
				out.append(_cross(prev, cur, r, edge))
			if cin:
				out.append(cur)
			prev = cur
	return out


static func _inside(p: Vector2, r: Rect2, edge: int) -> bool:
	match edge:
		0: return p.x >= r.position.x
		1: return p.x <= r.end.x
		2: return p.y >= r.position.y
	return p.y <= r.end.y


static func _cross(a: Vector2, b: Vector2, r: Rect2, edge: int) -> Vector2:
	if edge < 2:
		var x := r.position.x if edge == 0 else r.end.x
		return Vector2(x, a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x))
	var y := r.position.y if edge == 2 else r.end.y
	return Vector2(a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y), y)


## Flap lever (0..4: 0, 1, 2, 3, FULL) and the surface angle -> the configuration name; lever 1 with
## the flaps out (> 5 deg) is 1+F (take-off configuration).
static func conf_text(lever: int, flap_deg: float) -> String:
	if lever == 1 and flap_deg > 5.0:
		return "1+F"
	return ["0", "1", "2", "3", "FULL"][clampi(lever, 0, 4)]


## "35000" style rounding of an altitude to the 20 ft the tape reads in.
static func round_alt(ft: float) -> int:
	return int(roundf(ft / 20.0)) * 20
