class_name VehGpu
extends RefCounted
## Ground power unit: a towable 90 kVA diesel set (Guinault / ITW AXA layout): rounded yellow enclosure with
## three hinged doors a side (seams, louvres, latches), the control panel at the rear behind a window,
## the output cable coiled on a hanger, exhaust and lifting eye on the roof, four wheels on a steel
## frame (the front pair on a turntable) and an A-frame towbar resting on the ground. About
## 1.4 x 3.8 x 1.6 m with the towbar.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const R := 0.27
const HW := 0.68
const TOP := 1.55
const BOT := 0.56


static func build(g: VehicleGeo, _gl: VehicleGeo) -> void:
	var yellow := VehicleGeo.mat(P.YELLOW, VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.12, 0.12, 0.13), VehicleGeo.K.METAL)
	var steel := VehicleGeo.mat(Color(0.7, 0.72, 0.74), VehicleGeo.K.METAL)
	var seam := VehicleGeo.mat(Color(0.03, 0.03, 0.03), VehicleGeo.K.PLASTIC)
	g.box(Vector3(0, BOT - 0.07, 0.0), Vector3(1.1, 0.14, 2.5), dark)  # frame
	P.axle(g, -0.78, 0.55, R, 0.18, 14, true)
	P.axle(g, 0.85, 0.55, R, 0.18, 14)
	P.slab(g, -1.25, 1.25, HW, BOT, TOP, 0.13, 0.03, yellow, 0.05)
	g.box(Vector3(0, TOP + 0.01, 0.0), Vector3(1.0, 0.03, 2.1), VehicleGeo.mat(P.YELLOW * 0.92, VehicleGeo.K.PAINT), 0.01)  # roof panel
	for s in [-1.0, 1.0]:
		var x: float = s * (HW + 0.002)
		for z in [-1.2, -0.42, 0.42, 1.2]:  # door seams
			g.poly([Vector3(x, BOT + 0.06, z - 0.006), Vector3(x, BOT + 0.06, z + 0.006), Vector3(x, TOP - 0.1, z + 0.006), Vector3(x, TOP - 0.1, z - 0.006)], Vector3(s, 0, 0), seam)
		g.poly([Vector3(x, TOP - 0.1, -1.2), Vector3(x, TOP - 0.1, 1.2), Vector3(x, TOP - 0.112, 1.2), Vector3(x, TOP - 0.112, -1.2)], Vector3(s, 0, 0), seam)
		for d in [-0.81, 0.0, 0.81]:  # louvres and a latch on each door
			for i in 6:
				g.box(Vector3(s * (HW + 0.008), 0.98 + i * 0.07, d), Vector3(0.016, 0.028, 0.6), black, 0.004)
			g.box(Vector3(s * (HW + 0.01), 0.82, d + 0.3), Vector3(0.02, 0.05, 0.1), steel, 0.008)
		T.side_band(g, s * HW, -1.15, 1.15, BOT + 0.05, BOT + 0.12, P.RED)
		T.side_band(g, s * HW, -1.15, -0.85, BOT + 0.05, BOT + 0.12, P.WHITE)
		T.side_band(g, s * HW, 0.85, 1.15, BOT + 0.05, BOT + 0.12, P.WHITE)
		P.fender(g, Vector3(s * 0.55, R, 0.85), R, 0.18, black, 0.05, 40.0, 150.0, 6)
	T.plate(g, Vector3(-HW - 0.003, 1.3, -0.81), 0.34, 0.12, Vector3.LEFT)
	T.plate(g, Vector3(HW + 0.003, 1.3, 0.81), 0.34, 0.12, Vector3.RIGHT)
	# rear: control panel window, status lamps, cable outlet and coil
	g.box(Vector3(0, 1.12, 1.255), Vector3(0.9, 0.62, 0.012), seam)
	g.box(Vector3(0, 1.12, 1.262), Vector3(0.86, 0.58, 0.01), VehicleGeo.mat(Color(0.75, 0.62, 0.05), VehicleGeo.K.PAINT))
	g.box(Vector3(-0.15, 1.2, 1.27), Vector3(0.36, 0.26, 0.01), VehicleGeo.mat(Color(0.02, 0.03, 0.035), VehicleGeo.K.PLASTIC))  # panel window
	g.box(Vector3(-0.15, 1.22, 1.274), Vector3(0.14, 0.08, 0.005), VehicleGeo.mat(Color(0.1, 0.5, 0.3), VehicleGeo.K.TAPE))  # display
	for i in 3:
		g.box(Vector3(0.18 + i * 0.07, 1.25, 1.27), Vector3(0.035, 0.035, 0.02), VehicleGeo.mat([Color(0.1, 0.8, 0.2), P.AMBER, P.RED][i], VehicleGeo.K.TAPE), 0.008)
	g.box(Vector3(0.3, 0.75, 1.27), Vector3(0.22, 0.16, 0.06), dark, 0.02)  # outlet
	var coil := PackedVector2Array()
	for i in 13:  # a torus: the cable (5 cm) coiled at 0.24 m on a hanger, on the right side
		var a := TAU * i / 12.0
		coil.append(Vector2(0.05 * cos(a), 0.24 - 0.06 * sin(a)))
	g.lathe_x(coil, Vector3(HW + 0.09, 1.0, 0.38), 14, VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.RUBBER))
	g.box(Vector3(HW + 0.05, 1.24, 0.38), Vector3(0.1, 0.04, 0.12), dark, 0.01)  # hanger
	g.strut(Vector3(0.3, 0.75, 1.3), Vector3(HW + 0.09, 0.78, 0.6), 0.05, 0.05, VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.RUBBER))
	T.taillamp(g, Vector3(-0.52, 0.72, 1.26), Vector3(0.14, 0.1, 0.03))
	T.taillamp(g, Vector3(0.52, 0.72, 1.26), Vector3(0.14, 0.1, 0.03))
	T.chevrons(g, -0.6, -0.36, 0.6, 0.9, 1.253, true, 2, P.RED, P.WHITE)
	# roof: exhaust, lifting eye, filler cap
	T.exhaust(g, Vector3(0.36, TOP, 0.85), 0.22, 0.045)
	var eye := PackedVector2Array([Vector2(-0.015, 0.05), Vector2(-0.015, 0.08), Vector2(0.015, 0.08), Vector2(0.015, 0.05)])
	g.lathe_x(eye, Vector3(0, TOP + 0.09, 0.0), 10, steel)
	g.box(Vector3(0, TOP + 0.03, 0.0), Vector3(0.1, 0.04, 0.1), steel, 0.01)
	g.box(Vector3(-HW - 0.01, 0.78, 1.0), Vector3(0.03, 0.09, 0.09), black, 0.01)
	# towbar to the ground
	for s in [-1.0, 1.0]:
		g.strut(Vector3(s * 0.42, BOT - 0.08, -1.2), Vector3(0.0, 0.32, -2.3), 0.06, 0.06, dark, 0.01)
	var ring := PackedVector2Array([Vector2(-0.02, 0.05), Vector2(-0.02, 0.08), Vector2(0.02, 0.08), Vector2(0.02, 0.05)])
	g.lathe_x(ring, Vector3(0, 0.3, -2.38), 10, dark, Basis(Vector3.BACK, PI / 2))
	g.box(Vector3(0, 0.12, -2.25), Vector3(0.06, 0.24, 0.06), dark)  # stand
	g.box(Vector3(0, 0.02, -2.25), Vector3(0.16, 0.04, 0.16), dark)
	g.box(Vector3(0, BOT - 0.02, -1.29), Vector3(1.2, 0.12, 0.08), black, 0.03)  # front buffer
