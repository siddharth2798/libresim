class_name VehFireTruck
extends RefCounted
## Airport rescue and fire-fighting crash tender, 6x6 (Rosenbauer Panther proportions): 11.9 x 3.0 x 3.6 m,
## the crew cab ahead of the front axle with a strongly raked panoramic windscreen, roof turret on the cab,
## bumper turret, warning light bars, a tall body with roller-shutter lockers between boxed wheel arches,
## tank hatches and rails on top, a rear ladder, white and yellow reflective bands, rear chevrons. Generic.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const HW := 1.5
const R := 0.6
const AXLES := [-3.0, 2.6, 4.15]
const CAB := [-5.95, -3.7]
const NOSE := 1.85  # top of the vertical nose face
const SILL := 0.75


## Height of the raked windscreen plane at z (cab front).
static func _ws_y(z: float) -> float:
	return NOSE + (z - CAB[0]) * (1.23 / 0.9)


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var red := VehicleGeo.mat(Color(0.74, 0.04, 0.03), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.015, 0.015, 0.017), VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.6, 0.62, 0.65), VehicleGeo.K.METAL)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.45, 1.0, 0.0), Vector3(0.12, 0.35, 11.0), VehicleGeo.mat(Color(0.05, 0.05, 0.055), VehicleGeo.K.METAL))
	for i in 3:
		P.axle(g, AXLES[i], 1.2, R, 0.45, 18, i == 0, true)
	_cab(g, gl, red, black)
	# body: upper block over everything, lockers between the arches, dark wheel wells
	P.slab_rows(g, [[CAB[1] - 0.05, HW - 0.02, 1.3, 3.0, 0.14, 0.04], [CAB[1] + 0.05, HW, 1.3, 3.02, 0.16, 0.04], [5.85, HW, 1.3, 3.02, 0.16, 0.04], [5.95, HW - 0.05, 1.35, 2.97, 0.14, 0.04]], red, 4)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * (HW - 0.2), 0.95, -0.17), Vector3(0.4, 0.7, 4.0), red, 0.03)
		g.box(Vector3(s * (HW - 0.2), 0.95, 5.43), Vector3(0.4, 0.7, 1.05), red, 0.03)
		for a in [[-3.7, -2.18], [1.83, 4.9]]:
			g.box(Vector3(s * 0.72, 0.98, (a[0] + a[1]) * 0.5), Vector3(0.18, 0.75, a[1] - a[0]), dark)
			g.box(Vector3(s * (HW + 0.01), 1.32, (a[0] + a[1]) * 0.5), Vector3(0.06, 0.06, a[1] - a[0]), black, 0.015)
		for z in [-1.55, -0.17, 1.2]:  # roller-shutter lockers
			_shutter(g, s, z, 1.27, 0.7, 2.85)
		_shutter(g, s, 3.38, 1.4, 1.42, 2.85)
		_shutter(g, s, 5.43, 0.9, 0.7, 2.85)
		T.side_band(g, s * HW, CAB[1] + 0.05, 5.85, 1.36, 1.5, P.WHITE)
		T.side_band(g, s * HW, CAB[1] + 0.05, 5.85, 2.9, 2.97, Color(0.95, 0.9, 0.2))
		for z in [-1.0, 1.9, 4.5]:
			T.marker(g, Vector3(s * (HW + 0.005), 1.42, z), s)
		g.box(Vector3(s * (HW - 0.15), 3.12, 1.2), Vector3(0.05, 0.05, 8.6), metal, 0.01)  # roof rails
		for i in 6:
			g.box(Vector3(s * (HW - 0.15), 3.07, -2.9 + i * 1.64), Vector3(0.04, 0.12, 0.04), metal)
	for z in [-1.8, 0.6]:  # tank hatches
		var dome := PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.06, 0.3), Vector2(0.1, 0.26), Vector2(0.12, 0.0)])
		g.lathe_x(dome, Vector3(0, 3.02, z), 12, metal, Basis(Vector3.BACK, PI / 2))
	g.box(Vector3(0, 3.04, 3.6), Vector3(1.6, 0.04, 3.6), metal)  # walkway plate
	_rear(g, black, metal)


static func _shutter(g: VehicleGeo, s: float, zc: float, w: float, y0: float, y1: float) -> void:
	var alu := VehicleGeo.mat(Color(0.7, 0.72, 0.74), VehicleGeo.K.METAL)
	var line := VehicleGeo.mat(Color(0.1, 0.1, 0.11), VehicleGeo.K.METAL)
	g.box(Vector3(s * (HW + 0.004), (y0 + y1) * 0.5, zc), Vector3(0.02, y1 - y0, w), alu, 0.006)
	var n := int((y1 - y0) / 0.11)
	for k in n:
		g.box(Vector3(s * (HW + 0.016), y0 + 0.06 + k * 0.11, zc), Vector3(0.006, 0.012, w - 0.04), line)
	g.box(Vector3(s * (HW + 0.02), y0 + 0.08, zc), Vector3(0.025, 0.05, w * 0.6), line, 0.01)  # bar handle


static func _cab(g: VehicleGeo, gl: VehicleGeo, red: Color, black: Color) -> void:
	var z0: float = CAB[0]
	var z1: float = CAB[1]
	P.slab_rows(g, [[z0, HW - 0.08, SILL + 0.05, NOSE, 0.12, 0.06], [z0 + 0.06, HW - 0.02, SILL, _ws_y(z0 + 0.06), 0.18, 0.06],
		[-5.05, HW, SILL, 3.08, 0.25, 0.06], [z1, HW, SILL, 3.1, 0.25, 0.06]], red, 4)
	# raked windscreen (on the sloping front), corner glass, crew windows
	var ya := 2.0
	var yb := 2.93
	var za := z0 + (ya - NOSE) / (1.23 / 0.9) - 0.012
	var zb := z0 + (yb - NOSE) / (1.23 / 0.9) - 0.012
	P.end_pane(g, gl, -1.2, 1.2, za, ya, zb, yb, true)
	T.wipers(g, -1.0, 1.0, ya - 0.06, za - 0.02)
	for s in [-1.0, 1.0]:
		P.side_pane(g, gl, s * HW, -5.3, -4.55, 1.55, 2.85)  # door window (low, the Panther look)
		P.side_pane(g, gl, s * HW, -4.4, -3.85, 1.95, 2.85)
		g.poly([Vector3(s * (HW + 0.002), 0.9, -4.5), Vector3(s * (HW + 0.002), 0.9, -4.49), Vector3(s * (HW + 0.002), 2.9, -4.49), Vector3(s * (HW + 0.002), 2.9, -4.5)], Vector3(s, 0, 0), black)
		T.side_band(g, s * HW, -5.8, -3.75, 1.2, 1.36, P.WHITE)
		T.step(g, Vector3(s * (HW - 0.12), 0.45, -4.9), 0.6, 0.3)
		T.grab_rail(g, Vector3(s * HW, 1.0, -4.42), 1.3)
		T.mirror(g, Vector3(s * (HW + 0.3), 2.45, -5.25), 1.3)
		T.headlamp(g, Vector3(s * 1.05, 1.05, z0 - 0.02), Vector3(0.36, 0.2, 0.06))
		T.light_bar(g, Vector3(s * 0.82, 3.1, -4.85), 0.8)
	T.grille(g, -0.75, 0.75, 1.2, 1.7, z0, 4)
	T.plate(g, Vector3(0, 0.98, z0 - 0.22), 0.52, 0.15, Vector3.FORWARD)
	g.box(Vector3(0, 0.8, z0 - 0.1), Vector3(2.9, 0.34, 0.26), black, 0.06)  # bumper
	g.box(Vector3(0, 0.98, z0 - 0.24), Vector3(0.32, 0.22, 0.28), VehicleGeo.mat(Color(0.6, 0.62, 0.65), VehicleGeo.K.METAL), 0.04)  # bumper turret
	g.box(Vector3(0, 1.0, z0 - 0.52), Vector3(0.12, 0.12, 0.5), VehicleGeo.mat(Color(0.6, 0.62, 0.65), VehicleGeo.K.METAL), 0.03)
	# roof turret on the cab
	var base := PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.07, 0.3), Vector2(0.16, 0.25), Vector2(0.2, 0.0)])
	g.lathe_x(base, Vector3(0, 3.08, -4.3), 14, red, Basis(Vector3.BACK, PI / 2))
	g.box(Vector3(0, 3.38, -4.3), Vector3(0.34, 0.2, 0.4), VehicleGeo.mat(Color(0.6, 0.62, 0.65), VehicleGeo.K.METAL), 0.04)
	g.box(Vector3(0, 3.46, -4.95), Vector3(0.14, 0.14, 1.3), VehicleGeo.mat(Color(0.6, 0.62, 0.65), VehicleGeo.K.METAL), 0.03, Basis(Vector3.RIGHT, 0.1))
	g.box(Vector3(0, 3.55, -5.62), Vector3(0.24, 0.24, 0.1), black, 0.03)  # nozzle


static func _rear(g: VehicleGeo, black: Color, metal: Color) -> void:
	var z := 5.95
	T.chevrons(g, -1.45, 1.45, 0.62, 1.28, z + 0.01, true, 14, P.RED, Color(0.95, 0.9, 0.2))
	for s in [-1.0, 1.0]:
		T.taillamp(g, Vector3(s * 1.2, 1.6, z + 0.02), Vector3(0.24, 0.5, 0.06))
		g.strut(Vector3(0.55 + s * 0.2, 0.7, z + 0.06), Vector3(0.55 + s * 0.2, 3.1, z + 0.06), 0.04, 0.04, metal)  # ladder
	for i in 9:
		g.box(Vector3(0.55, 0.85 + i * 0.27, z + 0.06), Vector3(0.4, 0.03, 0.04), metal)
	g.box(Vector3(0, 0.7, z + 0.08), Vector3(2.9, 0.26, 0.2), black, 0.05)
	T.plate(g, Vector3(-0.6, 2.2, z + 0.004), 0.52, 0.15, Vector3.BACK)
	T.beacon(g, Vector3(-1.0, 3.02, 5.5), 1, 0.16)
