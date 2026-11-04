class_name VehBus
extends RefCounted
## Apron passenger bus (Cobus 3000 proportions): 13.9 x 3.0 x 2.95 m, very low floor, glazing from the
## belt line almost to the roof between thin black pillars, three glazed double doors on each side, small
## wheels in boxed arches, rounded roof with two air-conditioning pods and a beacon, big windscreen with
## a destination display. Built as a shell, so the interior (floor, poles, perch seats, ceiling lights)
## shows through the windows. Generic, no brand.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const HW := 1.5
const L := 6.95  # half length
const R := 0.42
const AXLES := [-4.7, 4.6]
const DOORS := [[-3.75, -2.35], [-0.7, 0.7], [2.35, 3.75]]
const ARCHES := [[-5.3, -4.1], [4.0, 5.2]]
const BELT := 1.0
const EAVE := 2.62
const ROOF := 2.95
const END := 0.45  # depth of the solid front / rear caps


## [z0, z1] minus the given intervals.
static func _minus(z0: float, z1: float, cuts: Array) -> Array:
	var out := [[z0, z1]]
	for c in cuts:
		var nxt := []
		for seg in out:
			if c[1] <= seg[0] or c[0] >= seg[1]:
				nxt.append(seg)
				continue
			if c[0] > seg[0]:
				nxt.append([seg[0], c[0]])
			if c[1] < seg[1]:
				nxt.append([c[1], seg[1]])
		out = nxt
	return out


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var white := VehicleGeo.mat(Color(0.94, 0.94, 0.92), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.015, 0.015, 0.017), VehicleGeo.K.PLASTIC)
	var zi := L - END
	# roof, end caps, floor
	P.slab_rows(g, [[-L + 0.02, HW - 0.04, EAVE, ROOF - 0.03, 0.3, 0.0], [-L + 0.12, HW, EAVE, ROOF, 0.32, 0.0], [L - 0.12, HW, EAVE, ROOF, 0.32, 0.0], [L - 0.02, HW - 0.04, EAVE, ROOF - 0.03, 0.3, 0.0]], white, 4)
	P.slab_rows(g, [[-L, HW - 0.1, 0.3, EAVE, 0.12, 0.12], [-L + 0.12, HW, 0.25, EAVE, 0.14, 0.12], [-zi, HW, 0.25, EAVE, 0.14, 0.12]], white, 4)
	P.slab_rows(g, [[zi, HW, 0.25, EAVE, 0.14, 0.12], [L - 0.12, HW, 0.25, EAVE, 0.14, 0.12], [L, HW - 0.1, 0.3, EAVE, 0.12, 0.12]], white, 4)
	g.box(Vector3(0, 0.3, 0), Vector3(HW * 2.0 - 0.1, 0.08, zi * 2.0), VehicleGeo.mat(Color(0.25, 0.26, 0.27), VehicleGeo.K.RUBBER))
	g.box(Vector3(0, EAVE - 0.02, 0), Vector3(HW * 2.0 - 0.1, 0.03, zi * 2.0), VehicleGeo.mat(Color(0.75, 0.76, 0.77), VehicleGeo.K.PLASTIC))  # ceiling
	for s in [-1.0, 1.0]:
		_side(g, gl, s, white, black, dark)
	for z in AXLES:
		P.axle(g, z, 1.22, R, 0.26, 16, z < 0.0, true)
	_ends(g, gl, black)
	_interior(g)
	for z in [-2.6, 1.8]:  # air-conditioning pods
		P.slab(g, z - 1.1, z + 1.1, 0.85, ROOF - 0.04, ROOF + 0.2, 0.1, 0.02, VehicleGeo.mat(Color(0.82, 0.83, 0.84), VehicleGeo.K.PAINT), 0.05)
		for k in 2:
			var grill := PackedVector2Array([Vector2(0.0, 0.24), Vector2(0.01, 0.24), Vector2(0.012, 0.0)])
			g.lathe_x(grill, Vector3(0.42 - k * 0.84, ROOF + 0.2, z), 12, dark, Basis(Vector3.BACK, PI / 2))
	T.beacon(g, Vector3(0.0, ROOF - 0.01, -5.6), 0, 0.17)


static func _side(g: VehicleGeo, gl: VehicleGeo, s: float, white: Color, black: Color, dark: Color) -> void:
	var zi := L - END
	var x := s * HW
	var blue := Color(0.08, 0.26, 0.55)
	# skirt below the belt: solid except at the doors and arches; dark wheel wells
	for seg in _minus(-zi, zi, DOORS + ARCHES):
		g.box(Vector3(s * (HW - 0.03), (0.25 + BELT) * 0.5, (seg[0] + seg[1]) * 0.5), Vector3(0.06, BELT - 0.25, seg[1] - seg[0]), white, 0.01)
		T.side_band(g, x, seg[0], seg[1], BELT - 0.16, BELT - 0.04, blue, VehicleGeo.K.PAINT)
	for a in ARCHES:
		g.box(Vector3(s * (HW - 0.03), BELT - 0.06, (a[0] + a[1]) * 0.5), Vector3(0.06, 0.12, a[1] - a[0]), white)
		g.box(Vector3(s * 0.97, 0.62, (a[0] + a[1]) * 0.5), Vector3(0.16, 0.76, a[1] - a[0]), dark)  # wheel well, inboard of the tyre
		g.box(Vector3(s * 1.22, BELT - 0.13, (a[0] + a[1]) * 0.5), Vector3(0.56, 0.02, a[1] - a[0]), dark)
		for z in a:
			g.box(Vector3(s * (HW - 0.01), 0.58, z), Vector3(0.05, 0.66, 0.06), black, 0.01)
		g.box(Vector3(s * (HW + 0.005), BELT - 0.135, (a[0] + a[1]) * 0.5), Vector3(0.05, 0.05, a[1] - a[0] + 0.06), black, 0.01)
	# window band: panes between black pillars; doors: glass leaves in black frames
	for seg in _minus(-zi, zi, DOORS):
		var n := maxi(1, roundi((seg[1] - seg[0]) / 1.35))
		var w: float = (seg[1] - seg[0]) / n
		for i in n + 1:
			var z: float = seg[0] + w * i
			g.box(Vector3(s * (HW - 0.03), (BELT + EAVE) * 0.5, z), Vector3(0.06, EAVE - BELT, 0.08), black)
		P.side_pane(null, gl, x - s * 0.03, seg[0], seg[1], BELT, EAVE, false)
		g.box(Vector3(s * (HW - 0.03), BELT + 0.02, (seg[0] + seg[1]) * 0.5), Vector3(0.07, 0.05, seg[1] - seg[0]), black)
	for d in DOORS:
		var zc: float = (d[0] + d[1]) * 0.5
		for z in [d[0], zc, d[1]]:
			g.box(Vector3(s * (HW - 0.05), 1.46, z), Vector3(0.05, 2.32, 0.07), black)
		g.box(Vector3(s * (HW - 0.05), 0.33, zc), Vector3(0.05, 0.06, d[1] - d[0]), black)
		g.box(Vector3(s * (HW - 0.05), EAVE - 0.03, zc), Vector3(0.05, 0.08, d[1] - d[0]), black)
		g.box(Vector3(s * (HW - 0.05), 1.3, zc), Vector3(0.05, 0.04, d[1] - d[0]), black)  # door rail
		P.side_pane(null, gl, x - s * 0.05, d[0], d[1], 0.36, EAVE - 0.06, false)
		g.box(Vector3(s * (HW - 0.02), 0.27, zc), Vector3(0.12, 0.06, d[1] - d[0] + 0.1), VehicleGeo.mat(P.YELLOW, VehicleGeo.K.TAPE))  # sill edge
	T.side_band(g, s * (HW + 0.001), -L + 0.2, -zi, BELT - 0.16, BELT - 0.04, blue, VehicleGeo.K.PAINT)
	T.side_band(g, s * (HW + 0.001), zi, L - 0.2, BELT - 0.16, BELT - 0.04, blue, VehicleGeo.K.PAINT)
	T.mirror(g, Vector3(s * (HW + 0.25), 2.2, -L + 0.2), 1.3)
	T.plate(g, Vector3(s * (HW + 0.002), 0.62, -zi + 0.25), 0.5, 0.17, Vector3(s, 0, 0))
	for z in [-3.0, 0.0, 3.0]:
		T.marker(g, Vector3(s * (HW + 0.002), 0.4, z + 1.5 * signf(z + 0.01)), s)


static func _ends(g: VehicleGeo, gl: VehicleGeo, black: Color) -> void:
	P.end_pane(g, gl, -1.32, 1.32, -L, 1.02, -L, 2.4, true)
	g.box(Vector3(0, 2.52, -L - 0.01), Vector3(2.0, 0.2, 0.03), VehicleGeo.mat(Color(0.02, 0.02, 0.02), VehicleGeo.K.PLASTIC))  # destination display
	g.box(Vector3(0.3, 2.52, -L - 0.02), Vector3(1.1, 0.1, 0.01), VehicleGeo.mat(P.AMBER, VehicleGeo.K.TAPE))
	T.wipers(g, -1.1, 1.1, 1.04, -L)
	P.end_pane(g, gl, -1.1, 1.1, L, 1.5, L, 2.45, false)
	for s in [-1.0, 1.0]:
		T.headlamp(g, Vector3(s * 1.1, 0.68, -L - 0.01), Vector3(0.42, 0.18, 0.06))
		T.taillamp(g, Vector3(s * 1.2, 0.95, L + 0.01), Vector3(0.2, 0.5, 0.06))
	g.box(Vector3(0, 0.42, -L - 0.06), Vector3(2.9, 0.26, 0.16), black, 0.05)  # bumpers
	g.box(Vector3(0, 0.42, L + 0.06), Vector3(2.9, 0.26, 0.16), black, 0.05)
	T.plate(g, Vector3(0, 0.62, -L - 0.005), 0.52, 0.16, Vector3.FORWARD)
	T.plate(g, Vector3(0, 1.25, L + 0.005), 0.52, 0.16, Vector3.BACK)
	T.grille(g, 0.25, 1.25, 0.6, 1.15, L + 0.004, 6)  # engine bay at the rear
	T.chevrons(g, -1.45, 1.45, 0.56, 0.7, L + 0.14, true, 14, P.RED, P.WHITE)


static func _interior(g: VehicleGeo) -> void:
	var pole := VehicleGeo.mat(P.YELLOW, VehicleGeo.K.PAINT)
	var seat := VehicleGeo.mat(Color(0.12, 0.16, 0.28), VehicleGeo.K.PLASTIC)
	for z in [-5.0, -3.0, -1.5, 0.0, 1.5, 3.0, 4.8]:
		for x in [-0.55, 0.55]:
			g.box(Vector3(x, 1.45, z), Vector3(0.04, 2.3, 0.04), pole)
	for x in [-0.55, 0.55]:
		g.box(Vector3(x, 2.1, 0.0), Vector3(0.035, 0.035, 11.0), pole)  # overhead rails
	for z in [-5.9, -4.7, 4.6, 5.8]:  # perch seats over the wheels and at the ends
		for s in [-1.0, 1.0]:
			g.box(Vector3(s * 1.15, 0.92, z), Vector3(0.45, 0.1, 0.9), seat, 0.03)
			g.box(Vector3(s * 1.35, 1.25, z), Vector3(0.08, 0.55, 0.9), seat, 0.03)
	for x in [-0.9, 0.9]:  # ceiling light strips (they glow faintly at night)
		g.box(Vector3(x, EAVE - 0.04, 0.0), Vector3(0.12, 0.02, 11.0), VehicleGeo.mat(Color(0.95, 0.95, 0.92), VehicleGeo.K.TAPE))
	g.box(Vector3(-0.95, 1.05, -L + 0.75), Vector3(0.6, 0.35, 0.5), VehicleGeo.mat(Color(0.08, 0.08, 0.09), VehicleGeo.K.PLASTIC), 0.05)  # driver's console
	g.box(Vector3(-0.95, 0.85, -L + 1.3), Vector3(0.5, 0.12, 0.5), seat, 0.04)
