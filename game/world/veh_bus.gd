class_name VehBus
extends RefCounted
## Apron passenger bus: white low-floor body with a blue belt line, three doors and a window band on
## each side, roof air-conditioning units, amber beacon. About 12.2 x 2.6 x 3.1 m. Generic, no brand.

const WINDOWS := [[-3.85, -2.65], [-2.55, -1.35], [0.55, 1.75], [1.85, 3.05]]
const DOORS := [[-5.5, -4.0], [-1.1, 0.4], [3.3, 4.8]]


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var P := VehicleParts
	var white := VehicleGeo.mat(Color(0.94, 0.94, 0.92), VehicleGeo.K.PAINT)
	var blue := VehicleGeo.mat(Color(0.08, 0.25, 0.55), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var grey := VehicleGeo.mat(Color(0.7, 0.72, 0.74), VehicleGeo.K.PAINT)
	g.box(Vector3(0, 0.45, 0.0), Vector3(1.4, 0.15, 11.0), black)
	P.slab_rows(g, [[-6.1, 1.22, 0.42, 2.85, 0.35, 0.1], [-6.0, 1.3, 0.35, 3.0, 0.3, 0.1], [6.0, 1.3, 0.35, 3.0, 0.2, 0.1], [6.1, 1.22, 0.42, 2.9, 0.2, 0.1]], white)
	for z in [-4.1, 3.9]:
		P.axle(g, z, 1.24, 0.5, 0.3, 12)
		for s in [-1.0, 1.0]:
			P.arch_dark(g, s * 1.3, 0.5, z, 0.66, 0.35)
			P.arch_flare(g, s, 1.3, 0.5, z, 0.66, black)
	for s in [-1.0, 1.0]:
		for w in WINDOWS:
			P.side_pane(g, gl, s * 1.303, w[0], w[1], 1.35, 2.55)
		for d in DOORS:
			P.side_pane(g, gl, s * 1.303, d[0], d[1], 0.6, 2.6)
			g.box(Vector3(s * 1.31, 1.6, (d[0] + d[1]) * 0.5), Vector3(0.03, 2.05, 0.03), black)  # door split
		P.side_band(g, s * 1.3, -6.0, 6.0, 0.95, 1.2, Color(0.08, 0.25, 0.55))
		P.side_band(g, s * 1.3, -6.0, 6.0, 0.83, 0.9, Color(0.95, 0.5, 0.05))
		P.mirror(g, Vector3(s * 1.5, 2.15, -5.7), 1.6)
		P.headlamp(g, Vector3(s * 0.95, 0.78, -6.11), Vector3(0.4, 0.22, 0.08))
		P.taillamp(g, Vector3(s * 1.05, 1.0, 6.11), Vector3(0.22, 0.5, 0.06))
	P.end_pane(g, gl, -1.15, 1.15, -6.1, 1.2, -6.1, 2.75, true)
	P.end_pane(g, gl, -0.9, 0.9, 6.1, 1.9, 6.1, 2.6, false)
	g.box(Vector3(0, 0.6, -6.18), Vector3(2.5, 0.28, 0.2), black, 0.05)  # bumpers
	g.box(Vector3(0, 0.6, 6.18), Vector3(2.5, 0.28, 0.2), black, 0.05)
	g.box(Vector3(0, 3.02, -5.0), Vector3(1.4, 0.2, 0.4), VehicleGeo.mat(Color(0.05, 0.05, 0.06), VehicleGeo.K.PLASTIC), 0.03)  # destination board
	for z in [-1.2, 2.2]:
		g.box(Vector3(0, 3.12, z), Vector3(1.7, 0.22, 2.2), grey, 0.08)  # air-conditioning units
	P.beacon(g, Vector3(0.6, 3.02, -3.3), 0, 0.2)
	P.chevrons(g, -1.0, 1.0, 0.56, 0.72, 6.28, true, 10, P.RED, P.WHITE)
