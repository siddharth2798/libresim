class_name VehFuelTruck
extends RefCounted
## Aviation refuelling truck: white cab, silver-white tank with a red band, walkway and dome hatches,
## rear hose-reel cabinet, beacon on the cab. About 8.2 x 2.5 x 3.1 m, three axles. Generic, no brand.


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var P := VehicleParts
	var white := VehicleGeo.mat(Color(0.93, 0.93, 0.91), VehicleGeo.K.PAINT)
	var silver := VehicleGeo.mat(Color(0.86, 0.87, 0.88), VehicleGeo.K.PAINT)
	var red := VehicleGeo.mat(Color(0.72, 0.05, 0.04), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.25, 0.26, 0.28), VehicleGeo.K.METAL)
	var dark := VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.PLASTIC)
	# chassis, axles
	g.box(Vector3(0, 0.88, 0.0), Vector3(1.1, 0.30, 8.0), dark)
	P.axle(g, -2.95, 1.0, 0.5, 0.32, 10)
	P.axle(g, 2.0, 1.0, 0.5, 0.40, 10)
	P.axle(g, 3.3, 1.0, 0.5, 0.40, 10)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 1.02, 1.17, 2.65), Vector3(0.46, 0.07, 2.6), black, 0.02)  # rear fender
		g.box(Vector3(s * 1.02, 0.80, -2.95), Vector3(0.46, 0.07, 1.25), black, 0.02)
		P.arch_flare(g, s, 1.2, 0.5, -2.95, 0.62, black)
	# cab
	P.slab_rows(g, [[-4.02, 1.12, 1.15, 2.85, 0.20, 0.10], [-3.92, 1.20, 1.05, 3.0, 0.22, 0.10],
		[-2.1, 1.2, 1.05, 3.0, 0.22, 0.10], [-2.0, 1.15, 1.1, 2.95, 0.2, 0.1]], white)
	P.end_pane(g, gl, -1.0, 1.0, -4.02, 1.95, -4.02, 2.78, true)
	for s in [-1.0, 1.0]:
		P.side_pane(g, gl, s * 1.203, -3.55, -2.5, 1.95, 2.72)
		P.mirror(g, Vector3(s * 1.42, 2.25, -3.75), 1.5)
		g.box(Vector3(s * 1.24, 0.88, -3.1), Vector3(0.22, 0.06, 0.6), black, 0.01)  # step
		P.side_band(g, s * 1.21, -3.9, -2.1, 1.3, 1.5, P.RED)
		P.taillamp(g, Vector3(s * 1.06, 1.05, 4.13), Vector3(0.28, 0.18, 0.06))
	g.box(Vector3(0, 1.62, -4.04), Vector3(1.5, 0.7, 0.05), black, 0.015)  # grille
	for y in [1.45, 1.6, 1.75]:
		g.box(Vector3(0, y, -4.07), Vector3(1.4, 0.03, 0.02), VehicleGeo.mat(Color(0.8, 0.82, 0.85), VehicleGeo.K.METAL))
	for s in [-1.0, 1.0]:
		P.headlamp(g, Vector3(s * 0.98, 1.55, -4.0), Vector3(0.40, 0.24, 0.1))
	g.box(Vector3(0, 1.0, -4.1), Vector3(2.4, 0.3, 0.28), black, 0.05)  # bumper
	g.box(Vector3(0, 3.02, -3.0), Vector3(1.3, 0.08, 1.2), white, 0.03)  # roof fairing
	P.beacon(g, Vector3(0, 3.06, -3.0), 0, 0.2)
	# tank
	var rows := [[-1.75, 1.03, 1.45, 2.95, 0.8, 0.8], [-1.62, 1.12, 1.36, 3.04, 0.8, 0.8], [-1.4, 1.13, 1.35, 3.05, 0.8, 0.8],
		[3.7, 1.13, 1.35, 3.05, 0.8, 0.8], [3.9, 1.08, 1.4, 3.0, 0.8, 0.8], [3.97, 0.95, 1.52, 2.88, 0.8, 0.8]]
	P.slab_rows(g, rows, silver, 5)
	P.slab_rows(g, [[0.6, 1.135, 1.345, 3.055, 0.8, 0.8], [1.15, 1.135, 1.345, 3.055, 0.8, 0.8]], red, 5)
	P.slab_rows(g, [[-1.5, 1.135, 1.345, 3.055, 0.8, 0.8], [-1.35, 1.135, 1.345, 3.055, 0.8, 0.8]], red, 5)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.34, 3.09, 1.0), Vector3(0.05, 0.05, 5.0), metal, 0.01)  # walkway rails
	g.box(Vector3(0, 3.06, 1.0), Vector3(0.66, 0.025, 5.0), metal)
	var dome := PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.05, 0.3), Vector2(0.11, 0.25), Vector2(0.13, 0.0)])
	for z in [-0.6, 1.0, 2.6]:
		g.lathe_x(dome, Vector3(0, 3.04, z), 10, metal, Basis(Vector3.BACK, PI / 2))
	# rear cabinet with the hose reel
	g.box(Vector3(0, 1.75, 4.1), Vector3(1.9, 1.05, 0.28), VehicleGeo.mat(Color(0.5, 0.52, 0.55), VehicleGeo.K.METAL), 0.02)
	var reel := PackedVector2Array([Vector2(-0.12, 0.0), Vector2(-0.12, 0.4), Vector2(0.12, 0.4), Vector2(0.12, 0.0)])
	g.lathe_x(reel, Vector3(0, 1.75, 4.32), 14, red, Basis(Vector3.UP, PI / 2))
	P.chevrons(g, -0.9, 0.9, 1.26, 1.44, 4.24, true, 10, P.RED, P.WHITE)
	g.box(Vector3(0, 0.95, 4.1), Vector3(2.0, 0.22, 0.25), black, 0.04)  # rear bumper
