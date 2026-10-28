class_name VehicleParts
extends RefCounted
## Shared pieces for the procedural ground vehicles (follow-me car, trucks, bus, tugs): wheels with
## tyre and dish, rounded body slabs, fender flares, glass panes, lamps, beacons, reflective bands.
## All build into a VehicleGeo (vehicle frame: x right, y up, -z forward).

const RUBBER := Color(0.05, 0.05, 0.055)
const STEEL := Color(0.52, 0.54, 0.56)
const BLACK := Color(0.055, 0.055, 0.06)
const GREY := Color(0.30, 0.31, 0.33)
const WHITE := Color(0.93, 0.94, 0.92)
const RED := Color(0.78, 0.04, 0.04)
const AMBER := Color(0.95, 0.5, 0.05)
const TINT := Color(0.03, 0.04, 0.045)  # glass tint (the glass shader reads it)
const TYRE := [Vector2(-0.112, 0.205), Vector2(-0.122, 0.25), Vector2(-0.106, 0.325), Vector2(-0.068, 0.367),
	Vector2(0.068, 0.367), Vector2(0.106, 0.325), Vector2(0.122, 0.25), Vector2(0.112, 0.205)]
const DISH := [Vector2(0.108, 0.206), Vector2(0.088, 0.19), Vector2(0.062, 0.115), Vector2(0.074, 0.07), Vector2(0.074, 0.0)]
const CAP := [Vector2(0.074, 0.066), Vector2(0.092, 0.058), Vector2(0.102, 0.03), Vector2(0.104, 0.0)]


## Wheel centred at c: radius r, tyre width w; side +1 = outer face toward +x, -1 toward -x.
static func wheel(g: VehicleGeo, c: Vector3, r: float, w: float, side: float, segs := 12, rim := STEEL) -> void:
	var kx := w / 0.244
	var kr := r / 0.37
	var b := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
	var scaled := func(src: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in src:
			out.append(Vector2(p.x * kx, p.y * kr))
		return out
	g.lathe_x(scaled.call(TYRE), c, segs, VehicleGeo.mat(RUBBER, VehicleGeo.K.RUBBER), b)
	g.lathe_x(PackedVector2Array([Vector2(0.0, 0.205 * kr), Vector2(0.0, 0.0)]), c, segs, VehicleGeo.mat(Color(0.03, 0.03, 0.035), VehicleGeo.K.PLASTIC), b)
	g.lathe_x(scaled.call(DISH), c, segs, VehicleGeo.mat(rim, VehicleGeo.K.METAL), b)
	g.lathe_x(scaled.call(CAP), c, segs, VehicleGeo.mat(Color(0.75, 0.77, 0.8), VehicleGeo.K.METAL), b)


## A pair of wheels (both sides) at height r on axle z; track = half distance between the tyre centres.
static func axle(g: VehicleGeo, z: float, track: float, r: float, w: float, segs := 12) -> void:
	for s in [-1.0, 1.0]:
		wheel(g, Vector3(s * track, r, z), r, w, s, segs)
	g.box(Vector3(0, r, z), Vector3(track * 2.0 - w * 0.6, 0.07, 0.07), VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.PLASTIC))


## Rounded body block: rows of [z, half-width, y bottom, y top, top radius, bottom radius], capped.
static func slab_rows(g: VehicleGeo, rows: Array, col: Color, nc := 3) -> void:
	var rings := []
	for r in rows:
		rings.append(VehicleGeo.ring(r[1], r[2], r[3], r[4], r[5], r[0], nc))
	g.loft(rings, col)
	g.poly(rings[0], Vector3.FORWARD, col)
	g.poly(rings[-1], Vector3.BACK, col)


## Body block z0..z1 with softly rounded ends (the end rows are pulled in by `taper`).
static func slab(g: VehicleGeo, z0: float, z1: float, hw: float, yb: float, yt: float, rt: float, rb: float,
		col: Color, taper := 0.05) -> void:
	var t := taper
	slab_rows(g, [[z0, hw - t, yb + t, yt - t, rt, rb], [z0 + t * 1.2, hw, yb, yt, rt, rb],
		[z1 - t * 1.2, hw, yb, yt, rt, rb], [z1, hw - t, yb + t, yt - t, rt, rb]], col)


## Dark wheel-arch recess painted on a body side (plane x, sign s) around an axle at (y, z): the tyre
## stands in front of it, so a solid body block reads as having an arch. yb = lower edge of the body.
static func arch_dark(g: VehicleGeo, x: float, y: float, z: float, r: float, yb: float) -> void:
	var s := signf(x)
	var xx := x + s * 0.004
	var pts := [Vector3(xx, minf(yb, y), z - r)]
	for i in 13:
		var a := deg_to_rad(-8.0 + 196.0 * i / 12.0)
		pts.append(Vector3(xx, y + sin(a) * r, z - cos(a) * r))
	pts.append(Vector3(xx, minf(yb, y), z + r))
	g.poly(pts, Vector3(s, 0, 0), VehicleGeo.mat(Color(0.02, 0.02, 0.022), VehicleGeo.K.PLASTIC))


## Black flare around a wheel arch of radius r0 on a body side x (sign s): a half ring about
## the axle at (y, z), width 0.045 out from x.
static func arch_flare(g: VehicleGeo, s: float, x: float, y: float, z: float, r0: float, col: Color) -> void:
	var r1 := r0 + 0.07
	var xo: float = x + s * 0.04
	var xi: float = x - s * 0.005
	var c := func(a: float, r: float, xx: float) -> Vector3: return Vector3(xx, y + sin(a) * r, z - cos(a) * r)
	for i in 14:
		var a0 := deg_to_rad(-8.0 + 196.0 * i / 14.0)
		var a1 := deg_to_rad(-8.0 + 196.0 * (i + 1) / 14.0)
		var mid := Vector3(0.0, sin(a0) + sin(a1), -cos(a0) - cos(a1))
		g.poly([c.call(a0, r0, xo), c.call(a0, r1, xo), c.call(a1, r1, xo), c.call(a1, r0, xo)], Vector3(s, 0, 0), col)
		g.poly([c.call(a0, r1, xi), c.call(a0, r1, xo), c.call(a1, r1, xo), c.call(a1, r1, xi)], mid, col)
		g.poly([c.call(a0, r0, xi), c.call(a0, r0, xo), c.call(a1, r0, xo), c.call(a1, r0, xi)], -mid, col)


const BACKING := Color(0.02, 0.025, 0.03)  # what shows through the glass: a dark interior


## A window pane in the side plane x between z0..z1, y0..y1: dark backing in the body mesh `g`
## (nothing, with null: see-through), glass in `gl`.
static func side_pane(g: VehicleGeo, gl: VehicleGeo, x: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var s := signf(x)
	var q := func(xx: float) -> Array: return [Vector3(xx, y0, z0), Vector3(xx, y0, z1), Vector3(xx, y1, z1), Vector3(xx, y1, z0)]
	if g != null:
		g.poly(q.call(x - s * 0.0015), Vector3(s, 0, 0), VehicleGeo.mat(BACKING, VehicleGeo.K.PLASTIC))
	gl.poly(q.call(x), Vector3(s, 0, 0), TINT)


## A pane on the front (outward -z) or rear (+z) plane, possibly raked: bottom edge at (zb, y0), top at (zt, y1).
static func end_pane(g: VehicleGeo, gl: VehicleGeo, x0: float, x1: float, zb: float, y0: float, zt: float, y1: float, front: bool) -> void:
	var d := -0.003 if front else 0.003  # glass stands 3 mm off the end face, the dark backing between
	var hint := Vector3(0, 0.4, -1.0 if front else 1.0)
	if g != null:
		g.poly([Vector3(x0, y0, zb + d * 0.5), Vector3(x1, y0, zb + d * 0.5), Vector3(x1, y1, zt + d * 0.5), Vector3(x0, y1, zt + d * 0.5)], hint, VehicleGeo.mat(BACKING, VehicleGeo.K.PLASTIC))
	gl.poly([Vector3(x0, y0, zb + d), Vector3(x1, y0, zb + d), Vector3(x1, y1, zt + d), Vector3(x0, y1, zt + d)], hint, TINT)


## Amber beacon dome (side 0 / 1 flashes in turn, see FollowMeLogic.flash).
static func beacon(g: VehicleGeo, p: Vector3, side: int, size := 0.14) -> void:
	var k := VehicleGeo.K.LENS_L if side == 0 else VehicleGeo.K.LENS_R
	g.box(p + Vector3(0, size * 0.1, 0), Vector3(size * 1.5, size * 0.25, size * 1.5), VehicleGeo.mat(GREY * 0.4, VehicleGeo.K.PLASTIC), 0.01)
	g.box(p + Vector3(0, size * 0.55, 0), Vector3(size, size, size), VehicleGeo.mat(AMBER, k), size * 0.3)


## Head and tail lamp boxes: centre p, size s.
static func headlamp(g: VehicleGeo, p: Vector3, s: Vector3) -> void:
	g.box(p, s, VehicleGeo.mat(Color(0.8, 0.82, 0.85), VehicleGeo.K.HEAD), minf(s.y, s.x) * 0.25)


static func taillamp(g: VehicleGeo, p: Vector3, s: Vector3) -> void:
	g.box(p, s, VehicleGeo.mat(Color(0.7, 0.03, 0.03), VehicleGeo.K.TAIL), minf(s.y, s.x) * 0.25)


## Reflective band along a body side (plane x, sign s): z0..z1, y0..y1.
static func side_band(g: VehicleGeo, x: float, z0: float, z1: float, y0: float, y1: float, col: Color) -> void:
	var xx: float = x + signf(x) * 0.003
	g.poly([Vector3(xx, y0, z0), Vector3(xx, y0, z1), Vector3(xx, y1, z1), Vector3(xx, y1, z0)], Vector3(signf(x), 0, 0), VehicleGeo.mat(col, VehicleGeo.K.TAPE))


## Diagonal two-colour conspicuity band on an end face (z, facing +z when back is true).
static func chevrons(g: VehicleGeo, x0: float, x1: float, y0: float, y1: float, z: float, back: bool, n: int, a: Color, b: Color) -> void:
	var w := (x1 - x0) / n
	var sh := (y1 - y0) * 0.6
	var zz := z + (0.003 if back else -0.003)
	for i in n:
		var xa := x0 + w * i
		var xb := minf(xa + w, x1)
		var xs0 := minf(xa + sh, x1)
		var xs1 := minf(xb + sh, x1)
		g.poly([Vector3(xa, y0, zz), Vector3(xb, y0, zz), Vector3(xs1, y1, zz), Vector3(xs0, y1, zz)],
			Vector3(0, 0, 1.0 if back else -1.0), VehicleGeo.mat(a if i % 2 == 0 else b, VehicleGeo.K.TAPE))


## Mirror on a short arm at p (x sign gives the side).
static func mirror(g: VehicleGeo, p: Vector3, size := 1.0) -> void:
	var black := VehicleGeo.mat(BLACK, VehicleGeo.K.PLASTIC)
	g.box(p + Vector3(-signf(p.x) * 0.05, -0.06, 0), Vector3(0.12, 0.04, 0.05) * size, black, 0.01)
	g.box(p, Vector3(0.08, 0.2, 0.15) * size, black, 0.03)
