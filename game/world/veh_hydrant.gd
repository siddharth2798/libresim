class_name VehHydrant
extends RefCounted
## Hydrant dispenser (fuels an airliner from the apron hydrant pits): a two-axle cab-over light truck
## (veh_cab.gd) carrying an equipment cabinet (filter / meter, roller shutters), a scissor-lift platform
## with yellow railings stowed over the rear, the intake hoses with their pit couplers racked along the
## sides and two delivery hose reels. About 7.3 x 2.4 x 3.1 m. Generic, no brand.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const R := 0.42
const AXLES := [-2.75, 1.55]


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var white := Color(0.93, 0.93, 0.91)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.06, 0.06, 0.065), VehicleGeo.K.METAL)
	var alu := VehicleGeo.mat(Color(0.68, 0.7, 0.72), VehicleGeo.K.METAL)
	var steel := VehicleGeo.mat(Color(0.75, 0.77, 0.8), VehicleGeo.K.METAL)
	var yellow := VehicleGeo.mat(P.YELLOW, VehicleGeo.K.PAINT)
	var body := VehicleGeo.mat(white, VehicleGeo.K.PAINT)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.4, 0.78, 0.2), Vector3(0.1, 0.22, 6.6), dark)
	P.axle(g, AXLES[0], 0.88, R, 0.26, 16, true, true)
	P.axle(g, AXLES[1], 0.88, R, 0.24, 16, false, true, true)
	VehCab.build(g, gl, -3.65, 1.6, 1.08, 0.98, 2.62, white, Vector3(0.88, R, AXLES[0]), R)
	g.box(Vector3(0, 0.98, 0.78), Vector3(2.36, 0.12, 5.1), dark, 0.01)  # deck
	# equipment cabinet behind the cab
	P.slab(g, -1.95, 0.05, 1.16, 1.04, 2.35, 0.08, 0.02, body, 0.03)
	for s in [-1.0, 1.0]:
		for z in [-1.45, -0.45]:  # roller shutters
			g.box(Vector3(s * 1.165, 1.68, z), Vector3(0.02, 1.1, 0.86), alu, 0.008)
			for k in 9:
				g.box(Vector3(s * 1.178, 1.18 + k * 0.12, z), Vector3(0.006, 0.012, 0.84), dark)
			g.box(Vector3(s * 1.182, 1.16, z), Vector3(0.02, 0.04, 0.3), steel)
	# scissor lift and stowed platform over the rear
	for s in [-1.0, 1.0]:
		g.strut(Vector3(s * 0.8, 1.06, 0.5), Vector3(s * 0.8, 1.66, 3.0), 0.06, 0.08, dark, 0.01)
		g.strut(Vector3(s * 0.8, 1.06, 3.0), Vector3(s * 0.8, 1.66, 0.5), 0.06, 0.08, dark, 0.01)
	g.box(Vector3(0, 1.32, 1.75), Vector3(0.3, 0.12, 0.8), steel, 0.02)  # lift cylinder
	g.box(Vector3(0, 1.72, 1.75), Vector3(2.2, 0.1, 2.8), alu, 0.02)
	for i in 10:
		g.box(Vector3(0, 1.775, 0.5 + i * 0.28), Vector3(2.1, 0.012, 0.03), dark)
	for s in [-1.0, 1.0]:
		for z in [0.4, 1.75, 3.1]:
			g.strut(Vector3(s * 1.06, 1.77, z), Vector3(s * 1.06, 2.75, z), 0.04, 0.04, yellow)
		g.strut(Vector3(s * 1.06, 2.75, 0.4), Vector3(s * 1.06, 2.75, 3.1), 0.045, 0.045, yellow)
		g.strut(Vector3(s * 1.06, 2.25, 0.4), Vector3(s * 1.06, 2.25, 3.1), 0.035, 0.035, yellow)
		g.box(Vector3(s * 1.06, 1.83, 1.75), Vector3(0.03, 0.12, 2.7), yellow)  # toe board
	g.strut(Vector3(-1.06, 2.75, 3.1), Vector3(1.06, 2.75, 3.1), 0.045, 0.045, yellow)
	g.strut(Vector3(-1.06, 2.75, 0.4), Vector3(1.06, 2.75, 0.4), 0.045, 0.045, yellow)
	# hoses: intake hoses racked along the lower sides, two delivery reels at the rear
	var hose := VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.RUBBER)
	for s in [-1.0, 1.0]:
		for k in 2:
			g.strut(Vector3(s * 1.2, 0.8 + k * 0.12, 0.6), Vector3(s * 1.2, 0.8 + k * 0.12, 3.1), 0.1, 0.1, hose, 0.04)
		for z in [0.75, 2.0, 3.0]:
			g.box(Vector3(s * 1.15, 0.86, z), Vector3(0.12, 0.3, 0.04), steel)
		g.box(Vector3(s * 1.2, 0.86, 3.22), Vector3(0.16, 0.16, 0.18), VehicleGeo.mat(P.RED, VehicleGeo.K.PAINT), 0.03)  # pit coupler
		T.side_band(g, s * 1.166, -1.9, 0.0, 1.1, 1.16, P.RED)
		T.marker(g, Vector3(s * 1.19, 0.95, 2.2), s)
		g.box(Vector3(s * 0.88, 0.95, 2.1), Vector3(0.36, 0.04, 1.1), black, 0.01)  # rear mudguard
	T.hose_drum(g, Vector3(0.0, 1.32, 3.1), 0.22, 1.5)
	T.plate(g, Vector3(-1.162, 2.05, -0.95), 0.5, 0.16, Vector3.LEFT)
	T.plate(g, Vector3(1.162, 2.05, -0.95), 0.5, 0.16, Vector3.RIGHT)
	g.box(Vector3(0, 0.66, 3.4), Vector3(2.2, 0.16, 0.1), dark, 0.02)
	T.chevrons(g, -1.1, 1.1, 0.58, 0.74, 3.45, true, 12, P.RED, P.WHITE)
	for s in [-1.0, 1.0]:
		T.taillamp(g, Vector3(s * 0.9, 0.86, 3.4), Vector3(0.26, 0.12, 0.05))
	T.plate(g, Vector3(0.3, 0.86, 3.43), 0.46, 0.13, Vector3.BACK)
