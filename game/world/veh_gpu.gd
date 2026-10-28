class_name VehGpu
extends RefCounted
## Ground power unit: a yellow generator cart on four small wheels with louvres, control panel, exhaust,
## a cable drum and a towbar to the front. About 1.3 x 3.4 x 1.7 m.


static func build(g: VehicleGeo, _gl: VehicleGeo) -> void:
	var P := VehicleParts
	var yellow := VehicleGeo.mat(Color(0.97, 0.74, 0.06), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.25, 0.26, 0.28), VehicleGeo.K.METAL)
	g.box(Vector3(0, 0.40, 0.0), Vector3(0.9, 0.12, 2.1), black)  # frame
	P.axle(g, -0.7, 0.57, 0.26, 0.18, 10)
	P.axle(g, 0.7, 0.57, 0.26, 0.18, 10)
	P.slab(g, -1.0, 1.0, 0.64, 0.42, 1.5, 0.12, 0.05, yellow, 0.06)
	for s in [-1.0, 1.0]:
		P.arch_flare(g, s, 0.64, 0.26, -0.7, 0.34, black)
		P.arch_flare(g, s, 0.64, 0.26, 0.7, 0.34, black)
		for i in 5:  # louvres
			g.box(Vector3(s * 0.645, 0.88 + i * 0.1, 0.35), Vector3(0.025, 0.045, 0.9), black, 0.008)
		g.box(Vector3(s * 0.65, 1.15, -0.55), Vector3(0.03, 0.42, 0.5), VehicleGeo.mat(Color(0.12, 0.12, 0.13), VehicleGeo.K.PLASTIC), 0.01)  # panel
		P.side_band(g, s * 0.64, -0.9, 0.9, 0.55, 0.62, P.BLACK)
	g.box(Vector3(0, 1.56, 0.3), Vector3(0.9, 0.06, 1.1), black, 0.015)  # top cover
	g.box(Vector3(0.3, 1.75, 0.75), Vector3(0.12, 0.35, 0.12), metal, 0.02)  # exhaust
	g.box(Vector3(-0.3, 1.58, -0.4), Vector3(0.16, 0.12, 0.16), metal, 0.02)  # lifting eye
	var reel := PackedVector2Array([Vector2(-0.2, 0.0), Vector2(-0.2, 0.34), Vector2(0.2, 0.34), Vector2(0.2, 0.0)])
	g.lathe_x(reel, Vector3(0, 0.95, 1.18), 12, black, Basis(Vector3.UP, PI / 2))  # cable drum, rear
	P.chevrons(g, -0.55, 0.55, 0.5, 0.66, 1.07, true, 8, P.BLACK, P.AMBER)
	for s in [-1.0, 1.0]:  # towbar to the hitch
		g.strut(Vector3(s * 0.4, 0.45, -0.95), Vector3(0.0, 0.5, -2.1), 0.06, 0.06, black, 0.01)
	g.box(Vector3(0, 0.5, -2.2), Vector3(0.14, 0.07, 0.2), metal, 0.01)
	P.taillamp(g, Vector3(-0.5, 0.95, 1.02), Vector3(0.16, 0.12, 0.04))
	P.taillamp(g, Vector3(0.5, 0.95, 1.02), Vector3(0.16, 0.12, 0.04))
