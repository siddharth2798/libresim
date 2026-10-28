class_name VehBaggage
extends RefCounted
## Baggage tractor (blue, canopy, beacon) and baggage cart (flat bed, rails, hoops, blue canopy, a few bags).


static func tug(g: VehicleGeo, gl: VehicleGeo) -> void:
	var P := VehicleParts
	var blue := VehicleGeo.mat(Color(0.10, 0.31, 0.66), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.25, 0.26, 0.28), VehicleGeo.K.METAL)
	g.box(Vector3(0, 0.42, 0.0), Vector3(0.9, 0.14, 2.6), black)
	P.axle(g, -0.85, 0.62, 0.32, 0.22, 10)
	P.axle(g, 0.85, 0.62, 0.32, 0.22, 10)
	P.slab_rows(g, [[-1.3, 0.62, 0.38, 0.84, 0.12, 0.05], [-1.2, 0.7, 0.35, 0.95, 0.12, 0.05], [-0.35, 0.7, 0.35, 0.95, 0.1, 0.05],
		[1.3, 0.68, 0.35, 0.95, 0.1, 0.05], [1.36, 0.6, 0.4, 0.9, 0.1, 0.05]], blue)
	for s in [-1.0, 1.0]:
		P.arch_flare(g, s, 0.7, 0.32, -0.85, 0.42, black)
		P.arch_flare(g, s, 0.7, 0.32, 0.85, 0.42, black)
		P.side_band(g, s * 0.7, -0.3, 1.2, 0.62, 0.7, P.WHITE)
		for z in [-0.35, 0.95]:  # canopy posts
			g.box(Vector3(s * 0.62, 1.55, z), Vector3(0.06, 1.15, 0.06), black, 0.01)
		P.headlamp(g, Vector3(s * 0.4, 0.72, -1.31), Vector3(0.2, 0.12, 0.05))
		P.taillamp(g, Vector3(s * 0.5, 0.78, 1.36), Vector3(0.12, 0.14, 0.05))
	g.box(Vector3(0, 1.20, -0.55), Vector3(0.9, 0.38, 0.1), black, 0.03)  # dash
	g.box(Vector3(0.0, 1.45, -0.62), Vector3(0.04, 0.4, 0.04), black)  # steering column
	var wheel := PackedVector2Array([Vector2(-0.012, 0.15), Vector2(0.0, 0.162), Vector2(0.012, 0.15), Vector2(0.0, 0.138), Vector2(-0.012, 0.15)])
	g.lathe_x(wheel, Vector3(0.0, 1.45, -0.5), 10, black, Basis(Vector3.UP, -PI / 2) * Basis(Vector3.BACK, 0.7))
	g.box(Vector3(0.0, 1.05, 0.25), Vector3(0.62, 0.14, 0.5), black, 0.04)  # seat
	g.box(Vector3(0.0, 1.35, 0.52), Vector3(0.62, 0.5, 0.1), black, 0.04)
	g.box(Vector3(0, 2.14, 0.3), Vector3(1.5, 0.07, 1.7), blue, 0.03)  # roof
	P.beacon(g, Vector3(0, 2.18, 0.0), 1, 0.16)
	g.box(Vector3(0, 0.56, 1.5), Vector3(0.3, 0.1, 0.25), metal, 0.02)  # hitch
	g.box(Vector3(0, 0.38, -1.42), Vector3(1.3, 0.2, 0.2), black, 0.05)  # bumper
	g.box(Vector3(0, 0.38, 1.4), Vector3(1.2, 0.18, 0.16), black, 0.04)


static func cart(g: VehicleGeo, _gl: VehicleGeo) -> void:
	var P := VehicleParts
	var grey := VehicleGeo.mat(Color(0.5, 0.52, 0.55), VehicleGeo.K.METAL)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var canvas := VehicleGeo.mat(Color(0.12, 0.28, 0.5), VehicleGeo.K.PLASTIC)
	g.box(Vector3(0, 0.62, 0.0), Vector3(1.6, 0.1, 3.4), grey, 0.02)  # deck
	g.box(Vector3(0, 0.48, 0.0), Vector3(1.0, 0.1, 3.0), black)
	P.axle(g, -1.1, 0.68, 0.24, 0.16, 8)
	P.axle(g, 1.1, 0.68, 0.24, 0.16, 8)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.79, 0.84, 0.0), Vector3(0.04, 0.34, 3.4), grey, 0.01)  # low side rails
		g.strut(Vector3(s * 0.45, 0.55, -1.7), Vector3(0.0, 0.5, -2.45), 0.07, 0.07, black, 0.01)  # drawbar
		P.side_band(g, s * 0.8, -1.6, 1.6, 0.72, 0.9, P.WHITE)
		P.taillamp(g, Vector3(s * 0.6, 0.62, 1.72), Vector3(0.1, 0.06, 0.03))
	for z in [-1.5, -0.5, 0.5, 1.5]:  # hoops
		for s in [-1.0, 1.0]:
			g.strut(Vector3(s * 0.78, 0.68, z), Vector3(s * 0.7, 1.75, z), 0.05, 0.05, grey, 0.008)
		g.box(Vector3(0, 1.88, z), Vector3(1.5, 0.05, 0.05), grey, 0.008)
	P.slab_rows(g, [[-1.6, 0.74, 1.72, 1.96, 0.1, 0.05], [-1.5, 0.78, 1.7, 2.0, 0.12, 0.05], [1.5, 0.78, 1.7, 2.0, 0.12, 0.05], [1.6, 0.74, 1.72, 1.96, 0.1, 0.05]], canvas)
	var bag_cols := [Color(0.2, 0.12, 0.08), Color(0.08, 0.1, 0.15), Color(0.35, 0.05, 0.05), Color(0.1, 0.1, 0.1)]
	for i in 6:
		var z := -1.2 + 0.5 * i
		g.box(Vector3(-0.3 + 0.6 * (i % 2), 0.95, z), Vector3(0.5, 0.3, 0.42), VehicleGeo.mat(bag_cols[i % 4], VehicleGeo.K.PLASTIC), 0.05)
