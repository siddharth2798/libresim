class_name VehBaggage
extends RefCounted
## Baggage tractor (TLD JST / Charlatte style: narrow hood between front mudguards, open driver's deck with a
## seat under a ROPS canopy and a windscreen, ballast and tow hitch at the rear; about 2.9 x 1.45 x 2.0 m)
## and the covered baggage cart it pulls (steel deck on four wheels, turntable and drawbar, corner posts,
## fibreglass roof, one canvas side curtain down and the other rolled up, a mesh front gate, bags;
## 3.0 x 1.5 m deck, 4.1 m with the drawbar). Generic, no brand.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")
const TUG_R := 0.30
const CART_R := 0.2


static func tug(g: VehicleGeo, gl: VehicleGeo) -> void:
	var blue := VehicleGeo.mat(Color(0.10, 0.30, 0.62), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.25, 0.26, 0.28), VehicleGeo.K.METAL)
	var white := VehicleGeo.mat(P.WHITE, VehicleGeo.K.PAINT)
	g.box(Vector3(0, 0.40, 0.0), Vector3(0.7, 0.16, 2.6), metal)  # frame
	P.axle(g, -0.88, 0.56, TUG_R, 0.2, 16, true)
	P.axle(g, 0.88, 0.56, TUG_R, 0.22, 16)
	# hood: narrow, sloping up toward the driver
	P.slab_rows(g, [[-1.45, 0.38, 0.40, 0.76, 0.1, 0.04], [-1.40, 0.44, 0.34, 0.80, 0.12, 0.04], [-0.40, 0.44, 0.34, 0.96, 0.12, 0.04], [-0.34, 0.42, 0.36, 0.95, 0.1, 0.04]], blue)
	T.grille(g, -0.3, 0.3, 0.46, 0.68, -1.452, 4)
	T.plate(g, Vector3(0, 0.38, -1.46), 0.3, 0.1, Vector3.FORWARD)
	# driver's deck over the rear wheels, lower body between them
	g.box(Vector3(0, 0.47, 0.55), Vector3(0.88, 0.3, 1.7), blue, 0.04)
	g.box(Vector3(0, 0.66, 0.53), Vector3(1.44, 0.07, 1.76), blue, 0.025)
	g.box(Vector3(0, 0.70, 0.53), Vector3(1.3, 0.01, 1.6), VehicleGeo.mat(Color(0.08, 0.08, 0.085), VehicleGeo.K.RUBBER))  # floor mat
	for s in [-1.0, 1.0]:
		P.fender(g, Vector3(s * 0.56, TUG_R, -0.88), TUG_R, 0.2, black, 0.06, 15.0, 160.0)
		g.box(Vector3(s * 0.56, 0.42, 1.36), Vector3(0.26, 0.42, 0.015), black)  # mud flap
		T.side_band(g, s * 0.72, -0.25, 1.35, 0.635, 0.66, P.WHITE)
		T.headlamp(g, Vector3(s * 0.36, 0.72, -1.44), Vector3(0.12, 0.1, 0.05))
		T.taillamp(g, Vector3(s * 0.56, 0.56, 1.42), Vector3(0.1, 0.1, 0.04))
		for z in [-0.28, 1.32]:  # canopy posts
			g.strut(Vector3(s * 0.64, 0.7, z), Vector3(s * 0.62, 1.95, z + (0.06 if z < 0.0 else 0.0)), 0.06, 0.06, black, 0.012)
		g.strut(Vector3(s * 0.62, 1.12, 1.32), Vector3(s * 0.62, 1.12, 0.6), 0.04, 0.04, black, 0.01)  # side rail
	P.end_pane(null, gl, -0.58, 0.58, -0.26, 1.06, -0.22, 1.86, true)  # windscreen
	g.box(Vector3(0, 1.04, -0.27), Vector3(1.28, 0.05, 0.05), black, 0.01)
	g.box(Vector3(0, 1.98, 0.53), Vector3(1.44, 0.07, 1.86), white, 0.03)  # roof
	g.box(Vector3(0, 1.93, 0.53), Vector3(1.3, 0.04, 1.7), VehicleGeo.mat(Color(0.2, 0.2, 0.21), VehicleGeo.K.PLASTIC))
	T.beacon(g, Vector3(0, 2.015, 0.2), 1, 0.12)
	# dash, steering, seat
	g.box(Vector3(0, 1.0, -0.36), Vector3(0.84, 0.14, 0.14), black, 0.03)
	g.strut(Vector3(0.0, 0.96, -0.3), Vector3(0.0, 1.2, -0.08), 0.05, 0.05, black)
	var wheel := PackedVector2Array([Vector2(-0.012, 0.15), Vector2(0.0, 0.162), Vector2(0.012, 0.15), Vector2(0.0, 0.138), Vector2(-0.012, 0.15)])
	g.lathe_x(wheel, Vector3(0.0, 1.22, -0.06), 12, black, Basis(Vector3.UP, -PI / 2) * Basis(Vector3.BACK, 0.75))
	g.box(Vector3(0.0, 0.92, 0.45), Vector3(0.5, 0.12, 0.46), black, 0.05)  # seat
	g.box(Vector3(0.0, 1.0, 0.36), Vector3(0.34, 0.26, 0.34), black, 0.03)  # seat base
	g.box(Vector3(0.0, 1.22, 0.70), Vector3(0.5, 0.5, 0.1), black, 0.05)
	g.box(Vector3(0.0, 0.85, 1.12), Vector3(1.2, 0.3, 0.42), blue, 0.04)  # battery box behind the seat
	# rear: ballast, hitch
	g.box(Vector3(0, 0.5, 1.42), Vector3(1.1, 0.3, 0.12), black, 0.04)
	g.box(Vector3(0, 0.5, 1.52), Vector3(0.24, 0.16, 0.12), metal, 0.02)
	g.strut(Vector3(0, 0.38, 1.54), Vector3(0, 0.66, 1.54), 0.04, 0.04, VehicleGeo.mat(Color(0.7, 0.72, 0.74), VehicleGeo.K.METAL))
	T.chevrons(g, -0.5, 0.5, 0.38, 0.6, 1.48, true, 6, P.BLACK, P.YELLOW)
	g.box(Vector3(0, 0.36, -1.5), Vector3(1.0, 0.16, 0.12), black, 0.04)  # front bumper
	T.mirror(g, Vector3(-0.68, 1.62, -0.25), 0.5)


static func cart(g: VehicleGeo, _gl: VehicleGeo) -> void:
	var grey := VehicleGeo.mat(Color(0.55, 0.57, 0.6), VehicleGeo.K.METAL)
	var dark := VehicleGeo.mat(Color(0.1, 0.1, 0.11), VehicleGeo.K.METAL)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var roof := VehicleGeo.mat(Color(0.12, 0.30, 0.55), VehicleGeo.K.PAINT)
	var canvas := VehicleGeo.mat(Color(0.14, 0.27, 0.45), VehicleGeo.K.PLASTIC)
	g.box(Vector3(0, 0.58, 0.0), Vector3(1.5, 0.06, 3.0), grey, 0.015)  # deck
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.35, 0.48, 0.0), Vector3(0.08, 0.14, 2.9), dark)  # channels
		g.box(Vector3(s * 0.745, 0.66, 0.0), Vector3(0.03, 0.12, 3.0), grey, 0.008)  # low side rail
		T.side_band(g, s * 0.76, -1.45, 1.45, 0.61, 0.7, P.WHITE)
		T.taillamp(g, Vector3(s * 0.62, 0.52, 1.5), Vector3(0.1, 0.06, 0.03), false)
		for z in [-1.47, 0.0, 1.47]:  # posts
			g.box(Vector3(s * 0.72, 1.24, z), Vector3(0.05, 1.28, 0.05), grey, 0.01)
	P.axle(g, -1.05, 0.58, CART_R, 0.14, 12, true)
	P.axle(g, 1.05, 0.58, CART_R, 0.14, 12)
	var ring := PackedVector2Array([Vector2(-0.03, 0.3), Vector2(-0.03, 0.36), Vector2(0.03, 0.36), Vector2(0.03, 0.3)])
	g.lathe_x(ring, Vector3(0, 0.5, -1.05), 14, dark, Basis(Vector3.BACK, PI / 2))  # turntable
	for s in [-1.0, 1.0]:  # drawbar
		g.strut(Vector3(s * 0.42, 0.42, -1.2), Vector3(0.0, 0.40, -2.42), 0.06, 0.06, dark, 0.01)
	var eye := PackedVector2Array([Vector2(-0.02, 0.04), Vector2(-0.02, 0.07), Vector2(0.02, 0.07), Vector2(0.02, 0.04)])
	g.lathe_x(eye, Vector3(0, 0.40, -2.48), 10, dark, Basis(Vector3.BACK, PI / 2))
	# roof and curtains
	P.slab_rows(g, [[-1.55, 0.74, 1.88, 1.96, 0.06, 0.02], [-1.5, 0.79, 1.86, 2.0, 0.1, 0.02], [1.5, 0.79, 1.86, 2.0, 0.1, 0.02], [1.55, 0.74, 1.88, 1.96, 0.06, 0.02]], roof)
	for i in 6:  # the left curtain hangs in shallow folds
		var z0 := -1.45 + i * 0.483
		var z1 := z0 + 0.483
		var xo := -0.735 - 0.012 * float(i % 2)
		g.poly([Vector3(xo, 0.75, z0), Vector3(xo, 0.75, z1), Vector3(xo, 1.86, z1), Vector3(xo, 1.86, z0)], Vector3.LEFT, canvas)
	var roll := PackedVector2Array([Vector2(-1.48, 0.0), Vector2(-1.48, 0.08), Vector2(1.48, 0.08), Vector2(1.48, 0.0)])
	g.lathe_x(roll, Vector3(0.76, 1.78, 0.0), 10, canvas, Basis(Vector3.UP, PI / 2))  # right curtain rolled up
	# front gate: frame and bars
	g.box(Vector3(0, 0.75, -1.5), Vector3(1.44, 0.04, 0.04), grey)
	g.box(Vector3(0, 1.6, -1.5), Vector3(1.44, 0.04, 0.04), grey)
	for i in 9:
		g.box(Vector3(-0.64 + i * 0.16, 1.18, -1.5), Vector3(0.02, 0.85, 0.02), grey)
	T.chevrons(g, -0.7, 0.7, 0.52, 0.6, 1.5, true, 8, P.RED, P.WHITE)
	T.plate(g, Vector3(0.45, 1.3, 1.475), 0.3, 0.12, Vector3.BACK)
	_bags(g)


static func _bags(g: VehicleGeo) -> void:
	var cols := [Color(0.12, 0.12, 0.13), Color(0.08, 0.12, 0.22), Color(0.45, 0.06, 0.05), Color(0.26, 0.17, 0.1),
		Color(0.5, 0.52, 0.55), Color(0.1, 0.3, 0.2), Color(0.6, 0.45, 0.12)]
	var spots := [[-0.38, -1.15, 0.62, 0.42, 0.3], [0.32, -1.2, 0.6, 0.36, 0.26], [-0.36, -0.6, 0.55, 0.48, 0.3], [0.36, -0.62, 0.5, 0.42, 0.34],
		[-0.4, 0.0, 0.62, 0.36, 0.28], [0.3, 0.05, 0.66, 0.44, 0.3], [-0.34, 0.6, 0.5, 0.46, 0.25], [0.34, 0.55, 0.6, 0.4, 0.32],
		[0.0, 1.15, 0.9, 0.38, 0.3], [-0.3, -1.1, 0.5, 0.34, 0.22], [0.25, -0.05, 0.48, 0.32, 0.24], [-0.32, 0.62, 0.4, 0.3, 0.22]]
	for i in spots.size():
		var b: Array = spots[i]
		var y: float = 0.61 + b[4] * 0.5 + (0.32 if i >= 9 else 0.0)
		var c := VehicleGeo.mat(cols[i % cols.size()], VehicleGeo.K.PLASTIC)
		g.box(Vector3(b[0], y, b[1]), Vector3(b[2], b[4], b[3]), c, 0.04, Basis(Vector3.UP, 0.08 * float((i * 7) % 5 - 2)))
		g.box(Vector3(b[0], y + b[4] * 0.5 + 0.015, b[1]), Vector3(0.14, 0.03, 0.03), VehicleGeo.mat(Color(0.05, 0.05, 0.05), VehicleGeo.K.PLASTIC))  # handle
