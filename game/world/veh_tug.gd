class_name VehTug
extends RefCounted
## Aircraft pushback tug, towbarless (TLD TPX / Goldhofer AST layout): a low U-shaped yellow chassis, the
## operator's glazed cab offset to the left front, engine deck on the right, four wheels at the corners
## (front ones steer), the nose-wheel cradle (scoop, clamp pads, cylinders) inside the open fork at the rear
## (toward the aircraft). About 4.4 x 1.75 x 1.45 m at size 1 (a light tug); airliners scale it by
## GroundVehicles.make(kind, size) (ground.tug_scale 1.8: about 7.9 x 3.2 x 2.6 m). The cradle sits at
## z +2.4..3.1 m x size, behind the origin. Generic, no brand.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const DECK := 0.66  # top of the chassis
const BOT := 0.22  # underside
const HW := 0.875  # half width
const R := 0.30  # wheel radius
const TRACK := 0.71
const AXLES := [-0.55, 2.35]
const CAB := [-0.875, -0.14, -1.0, 0.32]  # x0, x1, z0, z1
const ROOF := 1.40


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var yellow := VehicleGeo.mat(P.YELLOW, VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.12, 0.12, 0.13), VehicleGeo.K.METAL)
	_chassis(g, yellow, black, dark)
	_cab(g, gl, yellow, black)
	_cradle(g, black, dark)
	P.axle(g, AXLES[0], TRACK, R, 0.26, 16, true, true)
	P.axle(g, AXLES[1], TRACK, R, 0.26, 16, false, true)
	# lamps, tape, numbers
	for s in [-1.0, 1.0]:
		T.headlamp(g, Vector3(s * 0.66, 0.50, -1.16), Vector3(0.22, 0.12, 0.05))
		T.taillamp(g, Vector3(s * 0.66, 0.50, 3.26), Vector3(0.14, 0.12, 0.04))
		T.chevrons(g, s * 0.875 - 0.21, s * 0.875 + 0.21, 0.28, 0.6, 3.25, true, 3, P.BLACK, P.YELLOW)
		T.side_band(g, s * HW, -0.95, -0.82, 0.32, 0.58, P.WHITE)
		T.side_band(g, s * HW, 2.85, 3.15, 0.30, 0.38, P.WHITE)
	T.chevrons(g, -0.5, 0.5, 0.26, 0.42, -1.2, false, 8, P.BLACK, P.YELLOW)
	T.plate(g, Vector3(0.0, 0.53, -1.205), 0.36, 0.12, Vector3.FORWARD)
	T.plate(g, Vector3(-HW - 0.002, 0.48, 1.25), 0.4, 0.13, Vector3.LEFT)


static func _chassis(g: VehicleGeo, yellow: Color, black: Color, dark: Color) -> void:
	# core between the wheels, the front block, fork arms to the rear
	P.slab_rows(g, [[-1.15, 0.84, BOT + 0.05, DECK - 0.04, 0.05, 0.03], [-1.10, HW, BOT, DECK, 0.06, 0.04], [-0.95, HW, BOT, DECK, 0.06, 0.04], [-0.90, 0.56, BOT, DECK, 0.06, 0.04],
		[0.95, 0.56, BOT, DECK, 0.06, 0.04]], yellow)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.49, (BOT + DECK) * 0.5, 2.1), Vector3(0.14, DECK - BOT, 2.3), yellow, 0.03)  # fork beam
		g.box(Vector3(s * 0.715, (BOT + DECK) * 0.5, -0.16 + 1.05), Vector3(0.32, DECK - BOT - 0.04, 1.62), yellow, 0.04)  # side tank pod
		g.box(Vector3(s * 0.665, (BOT + DECK) * 0.5, 3.0), Vector3(0.42, DECK - BOT, 0.5), yellow, 0.04)  # arm end
		g.box(Vector3(s * 0.665, 0.42, 3.27), Vector3(0.36, 0.2, 0.05), black, 0.015)  # rubber buffer
		for z in AXLES:  # fenders over the wheels
			g.box(Vector3(s * 0.73, DECK + 0.015, z), Vector3(0.3, 0.03, 0.76), black, 0.01)
			g.box(Vector3(s * 0.73, DECK - 0.06, z - 0.38), Vector3(0.3, 0.14, 0.025), black)
			g.box(Vector3(s * 0.73, DECK - 0.06, z + 0.38), Vector3(0.3, 0.14, 0.025), black)
		for i in 4:  # louvres on the pods
			g.box(Vector3(s * 0.877, 0.36 + 0.06 * i, 0.9), Vector3(0.01, 0.025, 0.7), black)
	g.box(Vector3(0.0, 0.34, -1.2), Vector3(1.5, 0.22, 0.12), black, 0.04)  # front bumper
	g.box(Vector3(0.0, 0.42, 1.02), Vector3(0.84, 0.3, 0.1), black, 0.03)  # pusher pad at the front of the fork
	# engine deck (right front): raised cover with a grille, exhaust
	g.box(Vector3(0.36, DECK + 0.13, -0.35), Vector3(0.9, 0.26, 1.3), yellow, 0.05)
	g.box(Vector3(0.36, DECK + 0.265, -0.15), Vector3(0.6, 0.01, 0.6), VehicleGeo.mat(Color(0.03, 0.03, 0.035), VehicleGeo.K.PLASTIC))
	for i in 7:
		g.box(Vector3(0.36, DECK + 0.272, -0.42 + i * 0.09), Vector3(0.58, 0.012, 0.03), black)
	T.exhaust(g, Vector3(0.74, DECK + 0.2, 0.18), 0.35, 0.035)
	g.box(Vector3(0.0, BOT - 0.03, 0.0), Vector3(0.9, 0.06, 1.6), dark)  # belly pan


static func _cab(g: VehicleGeo, gl: VehicleGeo, yellow: Color, black: Color) -> void:
	var x0: float = CAB[0]
	var x1: float = CAB[1]
	var z0: float = CAB[2]
	var z1: float = CAB[3]
	var sill := DECK + 0.26
	var xc := (x0 + x1) * 0.5
	g.box(Vector3(xc, (DECK + sill) * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, sill - DECK, z1 - z0), yellow, 0.04)  # cab tub
	var pil := 0.05
	for px in [x0 + pil * 0.5, x1 - pil * 0.5]:
		for pz in [z0 + pil * 0.5, z1 - pil * 0.5]:
			var lean := -0.06 if pz < 0.0 else 0.0  # front pillars lean back a little
			g.strut(Vector3(px, sill, pz), Vector3(px, ROOF, pz - lean), pil, pil, black, 0.01)
	g.box(Vector3(xc, ROOF + 0.03, (z0 + z1) * 0.5 - 0.02), Vector3(x1 - x0 + 0.04, 0.07, z1 - z0 + 0.1), yellow, 0.03)  # roof
	# glass all round (see-through: the interior shows), the door on the left side
	P.end_pane(null, gl, x0 + pil, x1 - pil, z0 + 0.02, sill + 0.02, z0 + 0.08, ROOF - 0.03, true)
	P.end_pane(null, gl, x0 + pil, x1 - pil, z1, sill + 0.02, z1, ROOF - 0.03, false)
	P.side_pane(null, gl, x0, z0 + pil, z1 - pil, sill + 0.02, ROOF - 0.03, false)
	P.side_pane(null, gl, x1, z0 + pil, z1 - pil, sill + 0.02, ROOF - 0.03, false)
	g.box(Vector3(x0 - 0.01, (sill + ROOF) * 0.5, (z0 + z1) * 0.5 + 0.1), Vector3(0.02, 0.025, 0.12), VehicleGeo.mat(Color(0.7, 0.72, 0.74), VehicleGeo.K.METAL))  # door handle
	# interior: seat, console, steering wheel
	g.box(Vector3(xc, sill + 0.05, z1 - 0.32), Vector3(0.42, 0.1, 0.42), black, 0.04)
	g.box(Vector3(xc, sill + 0.3, z1 - 0.12), Vector3(0.42, 0.45, 0.1), black, 0.04)
	g.box(Vector3(xc, sill + 0.12, z0 + 0.15), Vector3(x1 - x0 - 0.1, 0.24, 0.22), VehicleGeo.mat(Color(0.08, 0.08, 0.09), VehicleGeo.K.PLASTIC), 0.03)
	var wheel := PackedVector2Array([Vector2(-0.012, 0.13), Vector2(0.0, 0.142), Vector2(0.012, 0.13), Vector2(0.0, 0.118), Vector2(-0.012, 0.13)])
	g.lathe_x(wheel, Vector3(xc, sill + 0.3, z0 + 0.36), 12, black, Basis(Vector3.UP, -PI / 2) * Basis(Vector3.BACK, 0.9))
	T.wipers(g, x0 + 0.08, x1 - 0.08, sill, z0 + 0.02)
	T.mirror(g, Vector3(x0 - 0.12, ROOF - 0.25, z0 + 0.05), 0.7)
	T.step(g, Vector3(x0 - 0.06, DECK - 0.18, -0.35), 0.4, 0.14)
	T.beacon(g, Vector3(xc, ROOF + 0.07, (z0 + z1) * 0.5), 0, 0.12)
	for s in [-1.0, 1.0]:  # work lamps on the roof front
		T.headlamp(g, Vector3(xc + s * 0.22, ROOF + 0.1, z0 + 0.04), Vector3(0.1, 0.07, 0.06), false)


static func _cradle(g: VehicleGeo, black: Color, dark: Color) -> void:
	g.box(Vector3(0, 0.12, 2.68), Vector3(0.82, 0.08, 0.86), dark, 0.02)  # scoop plate
	g.box(Vector3(0, 0.2, 3.08), Vector3(0.82, 0.12, 0.06), dark, 0.02)  # rear lip
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.40, 0.40, 2.7), Vector3(0.04, 0.32, 0.5), black, 0.02)  # clamp pad
		g.strut(Vector3(s * 0.40, DECK - 0.04, 1.6), Vector3(s * 0.38, 0.2, 2.35), 0.07, 0.07, VehicleGeo.mat(Color(0.75, 0.77, 0.8), VehicleGeo.K.METAL), 0.02)  # lift cylinder
		g.strut(Vector3(s * 0.40, DECK - 0.04, 1.45), Vector3(s * 0.40, DECK - 0.1, 1.75), 0.1, 0.1, dark, 0.02)
