class_name VehicleParts
extends RefCounted
## Shared pieces for the procedural ground vehicles (trucks, bus, tugs, carts; the follow-me car uses some):
## wheels with tyre, dish and wheel nuts (they carry their hub as a pivot so the shader can roll and steer
## them), rounded body slabs, wheel-arch recesses and flares, glass panes. Trim (lamps, beacons, tape,
## plates, grilles, steps, rails): vehicle_trim.gd. All build into a VehicleGeo (x right, y up, -z forward).

const RUBBER := Color(0.05, 0.05, 0.055)
const STEEL := Color(0.52, 0.54, 0.56)
const BLACK := Color(0.055, 0.055, 0.06)
const GREY := Color(0.30, 0.31, 0.33)
const WHITE := Color(0.93, 0.94, 0.92)
const RED := Color(0.78, 0.04, 0.04)
const AMBER := Color(0.95, 0.5, 0.05)
const YELLOW := Color(0.98, 0.74, 0.05)
const TINT := Color(0.03, 0.04, 0.045)  # glass tint (the glass shader reads it)
const BACKING := Color(0.02, 0.025, 0.03)  # what shows through the glass: a dark interior
## Profiles in units of a 0.37 m radius, 0.244 m wide tyre: (x across, r)
const TYRE := [Vector2(-0.112, 0.205), Vector2(-0.121, 0.232), Vector2(-0.122, 0.27), Vector2(-0.114, 0.318),
	Vector2(-0.094, 0.352), Vector2(-0.062, 0.367), Vector2(0.062, 0.367), Vector2(0.094, 0.352),
	Vector2(0.114, 0.318), Vector2(0.122, 0.27), Vector2(0.121, 0.232), Vector2(0.112, 0.205)]
const DISH := [Vector2(0.108, 0.206), Vector2(0.094, 0.198), Vector2(0.080, 0.17), Vector2(0.060, 0.115),
	Vector2(0.066, 0.085), Vector2(0.070, 0.0)]
const CAP := [Vector2(0.070, 0.06), Vector2(0.088, 0.052), Vector2(0.096, 0.03), Vector2(0.098, 0.0)]


## Wheel centred at c: radius r, tyre width w; side +1 = outer face toward +x, -1 toward -x. steers: the
## shader turns it with the vehicle's steer angle. truck: deep dish with eight nuts (else five, a car hub).
static func wheel(g: VehicleGeo, c: Vector3, r: float, w: float, side: float, segs := 16, rim := STEEL,
		steers := false, truck := false) -> void:
	var kx := w / 0.244
	var kr := r / 0.37
	var b := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
	var scaled := func(src: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in src:
			out.append(Vector2(p.x * kx, p.y * kr))
		return out
	g.pivot = Vector4(c.x, c.y, c.z, r + (VehicleGeo.STEERS if steers else 0.0))
	g.wheels.append([c, r, w, steers])
	g.lathe_x(scaled.call(TYRE), c, segs, VehicleGeo.mat(RUBBER, VehicleGeo.K.RUBBER), b)
	g.lathe_x(PackedVector2Array([Vector2(-0.10 * kx, 0.205 * kr), Vector2(-0.10 * kx, 0.0)]), c, segs, VehicleGeo.mat(Color(0.03, 0.03, 0.035), VehicleGeo.K.PLASTIC), b)
	var dish: PackedVector2Array = scaled.call(DISH)
	if truck:  # deeper dish
		dish[3].x -= 0.03 * kx
		dish[4].x -= 0.03 * kx
		dish[5].x -= 0.03 * kx
	g.lathe_x(dish, c, segs, VehicleGeo.mat(rim, VehicleGeo.K.METAL), b)
	var cap: PackedVector2Array = scaled.call(CAP)
	if truck:
		for i in cap.size():
			cap[i].x -= 0.03 * kx
	g.lathe_x(cap, c, maxi(segs / 2, 8), VehicleGeo.mat(Color(0.62, 0.64, 0.66), VehicleGeo.K.METAL), b)
	var nuts := 8 if truck else 5
	var nut := VehicleGeo.mat(Color(0.7, 0.72, 0.74), VehicleGeo.K.METAL)
	var nx := (0.068 - (0.03 if truck else 0.0)) * kx + 0.006
	for i in nuts:
		var a := TAU * (i + 0.5) / nuts
		var o := b * Vector3(nx, 0.125 * kr * cos(a), 0.125 * kr * sin(a))
		g.box(c + o, Vector3(0.016, 0.022, 0.022) * maxf(kr, 0.8), nut)
	g.pivot = Vector4.ZERO


## A pair of wheels (both sides) at height r on axle z; track = half distance between the tyre centres.
## dual: twin rear tyres (trucks); the axle beam and a differential housing between them.
static func axle(g: VehicleGeo, z: float, track: float, r: float, w: float, segs := 16, steers := false,
		truck := false, dual := false) -> void:
	for s in [-1.0, 1.0]:
		wheel(g, Vector3(s * track, r, z), r, w, s, segs, STEEL, steers, truck)
		if dual:
			wheel(g, Vector3(s * (track - w * 1.04), r, z), r, w, -s, segs, STEEL, false, truck)
	var dark := VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.METAL)
	g.box(Vector3(0, r, z), Vector3(track * 2.0 - w * (2.6 if dual else 0.6), 0.09, 0.09), dark)
	if truck:
		g.box(Vector3(0, r, z), Vector3(0.36, 0.3, 0.3), dark, 0.08)


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
	g.poly(pts, Vector3(s, 0, 0), VehicleGeo.mat(Color(0.015, 0.015, 0.017), VehicleGeo.K.PLASTIC))


## Black flare around a wheel arch of radius r0 on a body side x (sign s): a half ring about
## the axle at (y, z), width 0.07 out from x.
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


## Both arches of an axle: recess and flare on each side.
static func arches(g: VehicleGeo, x: float, y: float, z: float, r: float, yb: float, flare := true) -> void:
	for s in [-1.0, 1.0]:
		arch_dark(g, s * x, y, z, r, yb)
		if flare:
			arch_flare(g, s, x, y, z, r, VehicleGeo.mat(BLACK, VehicleGeo.K.PLASTIC))


## A window pane in the side plane x between z0..z1, y0..y1: dark backing in the body mesh `g`
## (nothing, with null: see-through), glass in `gl`, a black rubber surround 3 cm wide.
static func side_pane(g: VehicleGeo, gl: VehicleGeo, x: float, z0: float, z1: float, y0: float, y1: float, seal := true) -> void:
	var s := signf(x)
	var q := func(xx: float, e: float) -> Array: return [Vector3(xx, y0 - e, z0 - e), Vector3(xx, y0 - e, z1 + e), Vector3(xx, y1 + e, z1 + e), Vector3(xx, y1 + e, z0 - e)]
	if g != null:
		if seal:
			g.poly(q.call(x - s * 0.0005, 0.03), Vector3(s, 0, 0), VehicleGeo.mat(BLACK, VehicleGeo.K.PLASTIC))
		g.poly(q.call(x + s * 0.0015, 0.0), Vector3(s, 0, 0), VehicleGeo.mat(BACKING, VehicleGeo.K.PLASTIC))
	gl.poly(q.call(x + s * 0.004, 0.0), Vector3(s, 0, 0), TINT)


## A pane on the front (outward -z) or rear (+z) plane, possibly raked: bottom edge at (zb, y0), top at (zt, y1).
static func end_pane(g: VehicleGeo, gl: VehicleGeo, x0: float, x1: float, zb: float, y0: float, zt: float, y1: float, front: bool) -> void:
	var d := -0.004 if front else 0.004  # glass stands 4 mm off the end face, the dark backing between
	var hint := Vector3(0, 0.4, -1.0 if front else 1.0)
	var e := 0.03
	if g != null:
		g.poly([Vector3(x0 - e, y0 - e, zb + d * 0.2), Vector3(x1 + e, y0 - e, zb + d * 0.2), Vector3(x1 + e, y1 + e, zt + d * 0.2), Vector3(x0 - e, y1 + e, zt + d * 0.2)], hint, VehicleGeo.mat(BLACK, VehicleGeo.K.PLASTIC))
		g.poly([Vector3(x0, y0, zb + d * 0.5), Vector3(x1, y0, zb + d * 0.5), Vector3(x1, y1, zt + d * 0.5), Vector3(x0, y1, zt + d * 0.5)], hint, VehicleGeo.mat(BACKING, VehicleGeo.K.PLASTIC))
	gl.poly([Vector3(x0, y0, zb + d), Vector3(x1, y0, zb + d), Vector3(x1, y1, zt + d), Vector3(x0, y1, zt + d)], hint, TINT)


## Curved mudguard over a wheel at c (radius r, tyre width w): a band of radius r + gap from a0 to a1
## degrees (0 = front, 90 = top, 180 = rear), 2 cm thick.
static func fender(g: VehicleGeo, c: Vector3, r: float, w: float, col: Color, gap := 0.06, a0 := 10.0, a1 := 170.0, n := 10) -> void:
	var ro := r + gap
	for i in n:
		var t0 := deg_to_rad(lerpf(a0, a1, float(i) / n))
		var t1 := deg_to_rad(lerpf(a0, a1, float(i + 1) / n))
		var p0 := c + Vector3(0, sin(t0) * ro, -cos(t0) * ro)
		var p1 := c + Vector3(0, sin(t1) * ro, -cos(t1) * ro)
		g.strut(p0, p1, w + 0.04, 0.02, col)
