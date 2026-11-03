class_name VehFuelTruck
extends RefCounted
## Aviation refueller (a 20 kL bowser on a three-axle cab-over chassis, as at Indian airports): white cab
## (veh_cab.gd), elliptical white tank with a red band and domed ends, walkway with fold-down handrails
## and manlids on top, side lockers and an underrun rail between the axles, rear pump cabinet with the
## hose reel, meters and nozzle, rear ladder, tandem rear axle on twin tyres. About 9.3 x 2.5 x 3.4 m.
## Generic, no brand.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const R := 0.5
const AXLES := [-3.55, 1.9, 3.25]
const TANK := [-2.55, 3.75]


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var white := Color(0.93, 0.93, 0.91)
	var tank := VehicleGeo.mat(Color(0.9, 0.9, 0.89), VehicleGeo.K.PAINT)
	var red := VehicleGeo.mat(Color(0.72, 0.05, 0.04), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.06, 0.06, 0.065), VehicleGeo.K.METAL)
	var alu := VehicleGeo.mat(Color(0.66, 0.68, 0.7), VehicleGeo.K.METAL)
	var steel := VehicleGeo.mat(Color(0.75, 0.77, 0.8), VehicleGeo.K.METAL)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.42, 0.95, 0.0), Vector3(0.1, 0.28, 8.8), dark)  # frame rails
	P.axle(g, AXLES[0], 1.0, R, 0.3, 18, true, true)
	P.axle(g, AXLES[1], 1.0, R, 0.28, 18, false, true, true)
	P.axle(g, AXLES[2], 1.0, R, 0.28, 18, false, true, true)
	VehCab.build(g, gl, -4.6, 1.85, 1.17, 1.12, 2.92, white, Vector3(1.0, R, AXLES[0]), R)
	# tank
	var rows := [[TANK[0], 1.0, 1.4, 2.82, 0.8, 0.8], [TANK[0] + 0.12, 1.16, 1.3, 2.93, 0.85, 0.85], [TANK[0] + 0.3, 1.2, 1.27, 2.96, 0.85, 0.85],
		[TANK[1] - 0.3, 1.2, 1.27, 2.96, 0.85, 0.85], [TANK[1] - 0.12, 1.16, 1.3, 2.93, 0.85, 0.85], [TANK[1], 1.0, 1.4, 2.82, 0.8, 0.8]]
	P.slab_rows(g, rows, tank, 6)
	P.slab_rows(g, [[0.35, 1.205, 1.265, 2.965, 0.85, 0.85], [0.95, 1.205, 1.265, 2.965, 0.85, 0.85]], red, 6)
	g.box(Vector3(0, 1.2, 0.6), Vector3(1.0, 0.12, 6.2), dark)  # subframe under the tank
	# walkway, rails, manlids, vents
	g.box(Vector3(0, 3.0, 0.6), Vector3(0.7, 0.04, 5.6), alu)
	for i in 14:
		g.box(Vector3(0, 3.025, -2.0 + i * 0.4), Vector3(0.66, 0.01, 0.03), dark)
	for s in [-1.0, 1.0]:
		for i in 5:
			g.strut(Vector3(s * 0.36, 3.0, -2.1 + i * 1.35), Vector3(s * 0.36, 3.42, -2.1 + i * 1.35), 0.035, 0.035, VehicleGeo.mat(P.YELLOW, VehicleGeo.K.PAINT))
		g.strut(Vector3(s * 0.36, 3.42, -2.1), Vector3(s * 0.36, 3.42, 3.3), 0.035, 0.035, VehicleGeo.mat(P.YELLOW, VehicleGeo.K.PAINT))
	var dome := PackedVector2Array([Vector2(0.0, 0.26), Vector2(0.07, 0.26), Vector2(0.1, 0.22), Vector2(0.12, 0.0)])
	for z in [-1.3, 0.6, 2.5]:
		g.lathe_x(dome, Vector3(0, 3.02, z), 12, alu, Basis(Vector3.BACK, PI / 2))
		g.box(Vector3(0.15, 3.18, z), Vector3(0.06, 0.06, 0.12), steel, 0.01)
	T.exhaust(g, Vector3(-0.25, 3.0, 3.3), 0.3, 0.03)
	# lockers and underrun between the axles, extinguisher box, rear mudguards
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 1.0, 1.02, -1.2), Vector3(0.36, 0.42, 2.4), alu, 0.02)
		for z in [-2.0, -0.4]:
			g.box(Vector3(s * 1.185, 1.02, z), Vector3(0.01, 0.34, 0.02), dark)
		g.box(Vector3(s * 1.19, 1.12, -1.2), Vector3(0.02, 0.04, 0.16), steel)
		g.box(Vector3(s * 1.02, 1.0, 0.75), Vector3(0.3, 0.4, 0.5), red, 0.03)  # extinguisher box
		g.box(Vector3(s * 1.18, 0.66, -0.3), Vector3(0.05, 0.08, 3.6), steel, 0.015)  # underrun rail
		g.box(Vector3(s * 1.0, 1.08, 2.58), Vector3(0.52, 0.04, 2.25), black, 0.01)  # tandem mudguard
		g.box(Vector3(s * 1.0, 0.65, 3.85), Vector3(0.5, 0.6, 0.02), black)  # mud flap
		T.side_band(g, s * 1.205, -2.2, 3.6, 1.42, 1.5, P.RED)
		T.side_band(g, s * 1.205, -2.2, 3.6, 1.5, 1.56, P.WHITE)
		for z in [-2.0, 0.0, 2.6]:
			T.marker(g, Vector3(s * 1.21, 0.98, z), s)
	T.plate(g, Vector3(-1.21, 2.3, -1.5), 0.6, 0.2, Vector3.LEFT)
	T.plate(g, Vector3(1.21, 2.3, -1.5), 0.6, 0.2, Vector3.RIGHT)
	_rear(g, red, black, dark, alu, steel)


static func _rear(g: VehicleGeo, red: Color, black: Color, dark: Color, alu: Color, steel: Color) -> void:
	# open pump cabinet: back wall, side walls, roof; hose reel, meters, pipework, nozzle
	g.box(Vector3(0, 1.85, 3.82), Vector3(2.36, 1.5, 0.06), alu, 0.02)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 1.16, 1.85, 4.12), Vector3(0.05, 1.5, 0.62), alu, 0.015)
	g.box(Vector3(0, 2.62, 4.12), Vector3(2.36, 0.05, 0.66), alu, 0.015)
	g.box(Vector3(0, 1.08, 4.12), Vector3(2.36, 0.06, 0.66), dark)
	T.hose_drum(g, Vector3(0.25, 1.75, 4.15), 0.38, 1.2)
	g.box(Vector3(-0.78, 2.05, 3.88), Vector3(0.5, 0.42, 0.08), VehicleGeo.mat(Color(0.12, 0.12, 0.13), VehicleGeo.K.PLASTIC), 0.02)  # meter panel
	for i in 2:
		var face := PackedVector2Array([Vector2(0.0, 0.08), Vector2(0.01, 0.08), Vector2(0.012, 0.0)])
		g.lathe_x(face, Vector3(-0.9 + i * 0.24, 2.08, 3.93), 12, VehicleGeo.mat(Color(0.85, 0.86, 0.84), VehicleGeo.K.PLASTIC), Basis(Vector3.UP, -PI / 2))
	g.strut(Vector3(-0.9, 1.25, 3.9), Vector3(-0.9, 1.8, 3.9), 0.1, 0.1, red, 0.03)  # pipework
	g.strut(Vector3(-0.9, 1.25, 3.9), Vector3(0.25, 1.25, 3.9), 0.1, 0.1, red, 0.03)
	g.box(Vector3(-0.55, 1.45, 4.3), Vector3(0.12, 0.25, 0.1), black, 0.02)  # nozzle in its holder
	# ladder up the rear right corner to the walkway
	for s in [-1.0, 1.0]:
		g.strut(Vector3(0.75 + s * 0.2, 1.1, 4.46), Vector3(0.75 + s * 0.2, 3.42, 3.75), 0.04, 0.04, steel)
	for i in 7:
		var t := (i + 0.5) / 7.0
		g.box(Vector3(0.75, lerpf(1.1, 3.42, t), lerpf(4.46, 3.75, t)), Vector3(0.4, 0.03, 0.04), steel)
	# bumper, lamps, chevrons, plate
	g.box(Vector3(0, 0.72, 4.42), Vector3(2.3, 0.18, 0.12), dark, 0.02)
	T.chevrons(g, -1.12, 1.12, 0.64, 0.8, 4.48, true, 12, P.RED, P.WHITE)
	for s in [-1.0, 1.0]:
		T.taillamp(g, Vector3(s * 0.95, 0.93, 4.46), Vector3(0.28, 0.14, 0.05))
	T.plate(g, Vector3(-0.35, 0.93, 4.47), 0.5, 0.14, Vector3.BACK)
