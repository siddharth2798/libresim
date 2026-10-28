class_name VehFireTruck
extends RefCounted
## Airport rescue and fire-fighting truck: red three-axle crash tender with a white cab band, roof turret,
## roller-shutter lockers, ladder rails, beacons and rear chevrons. About 9.8 x 2.6 x 3.3 m. Generic.


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var P := VehicleParts
	var red := VehicleGeo.mat(Color(0.72, 0.04, 0.03), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.5, 0.52, 0.55), VehicleGeo.K.METAL)
	var shutter := VehicleGeo.mat(Color(0.45, 0.46, 0.48), VehicleGeo.K.METAL)
	g.box(Vector3(0, 0.75, 0.0), Vector3(1.2, 0.3, 9.4), VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.PLASTIC))
	for z in [-3.1, 1.5, 3.2]:
		P.axle(g, z, 1.18, 0.62, 0.42, 12)
		for s in [-1.0, 1.0]:
			P.arch_flare(g, s, 1.3, 0.62, z, 0.76, black)
	# cab
	P.slab_rows(g, [[-4.85, 1.2, 0.95, 2.9, 0.22, 0.1], [-4.75, 1.3, 0.85, 3.05, 0.25, 0.1], [-2.5, 1.3, 0.85, 3.05, 0.2, 0.1], [-2.4, 1.25, 0.9, 3.0, 0.2, 0.1]], red)
	P.end_pane(g, gl, -1.1, 1.1, -4.85, 1.7, -4.85, 2.95, true)
	# body
	P.slab_rows(g, [[-2.3, 1.28, 0.9, 2.75, 0.14, 0.08], [-2.2, 1.3, 0.85, 2.8, 0.14, 0.08], [4.7, 1.3, 0.85, 2.8, 0.14, 0.08], [4.8, 1.26, 0.9, 2.75, 0.14, 0.08]], red)
	for s in [-1.0, 1.0]:
		P.side_pane(g, gl, s * 1.303, -4.45, -3.2, 1.75, 2.8)
		P.side_pane(g, gl, s * 1.303, -3.1, -2.6, 1.75, 2.8)
		P.arch_dark(g, s * 1.3, 0.62, -3.1, 0.76, 0.85)
		P.arch_dark(g, s * 1.3, 0.62, 1.5, 0.76, 0.9)
		P.arch_dark(g, s * 1.3, 0.62, 3.2, 0.76, 0.9)
		P.side_band(g, s * 1.3, -4.7, -2.5, 1.35, 1.55, P.WHITE)
		P.side_band(g, s * 1.3, -2.2, 4.7, 2.0, 2.12, Color(0.95, 0.9, 0.2))
		for z in [-1.2, 0.0, 3.9]:  # roller-shutter lockers
			g.box(Vector3(s * 1.31, 1.75, z), Vector3(0.04, 1.2, 0.95), shutter, 0.01)
			for k in 5:
				g.box(Vector3(s * 1.335, 1.3 + k * 0.22, z), Vector3(0.01, 0.025, 0.9), black)
		g.box(Vector3(s * 1.4, 1.5, -3.5), Vector3(0.12, 0.05, 0.4), black, 0.01)  # steps
		P.mirror(g, Vector3(s * 1.5, 2.45, -4.4), 1.7)
		P.headlamp(g, Vector3(s * 0.95, 1.35, -4.84), Vector3(0.4, 0.24, 0.08))
		P.taillamp(g, Vector3(s * 1.1, 1.3, 4.82), Vector3(0.24, 0.5, 0.06))
		g.box(Vector3(s * 0.7, 2.86, 1.2), Vector3(0.05, 0.08, 6.0), metal, 0.01)  # ladder rails
	g.box(Vector3(0, 2.84, 1.2), Vector3(1.4, 0.04, 6.0), metal)
	for i in 12:
		g.box(Vector3(0, 2.88, -1.5 + i * 0.5), Vector3(1.4, 0.03, 0.04), metal)
	g.box(Vector3(0, 1.25, -4.88), Vector3(2.0, 0.55, 0.06), black, 0.015)  # grille
	g.box(Vector3(0, 0.78, -4.95), Vector3(2.6, 0.34, 0.3), black, 0.06)  # bumper
	g.box(Vector3(0, 1.0, -5.05), Vector3(0.3, 0.2, 0.3), metal, 0.04)  # bumper turret
	# roof turret and beacons
	var base := PackedVector2Array([Vector2(0.0, 0.34), Vector2(0.08, 0.34), Vector2(0.2, 0.28), Vector2(0.24, 0.0)])
	g.lathe_x(base, Vector3(0, 3.05, -3.6), 12, VehicleGeo.mat(Color(0.65, 0.04, 0.03), VehicleGeo.K.PAINT), Basis(Vector3.BACK, PI / 2))
	g.box(Vector3(0, 3.38, -3.6), Vector3(0.36, 0.22, 0.4), metal, 0.04)
	g.box(Vector3(0, 3.48, -4.3), Vector3(0.16, 0.16, 1.5), metal, 0.03, Basis(Vector3.RIGHT, 0.12))
	for s in [-1, 1]:
		P.beacon(g, Vector3(s * 0.7, 3.05, -4.4), 0 if s < 0 else 1, 0.2)
	P.chevrons(g, -1.15, 1.15, 0.95, 1.4, 4.8, true, 10, P.RED, Color(0.95, 0.9, 0.2))
	g.box(Vector3(0, 0.82, 4.9), Vector3(2.5, 0.28, 0.22), black, 0.05)
