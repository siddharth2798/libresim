class_name VehCab
extends RefCounted
## Cab-over truck cab (Tata / Ashok Leyland airside chassis layout) for the refueller and the hydrant
## dispenser: rounded shell, windscreen with wipers and a sun visor, grille band, steel bumper with the
## headlamps and the fleet plate, doors with windows, seams and handles, two steps and a grab rail under
## each door, mirrors on arms, an amber beacon on the roof, a black mudguard over each front wheel.
## The cab spans z0 (front) to z0 + depth, from yb (floor) to yt (roof), half width hw.

const P := preload("res://world/vehicle_parts.gd")
const T := preload("res://world/vehicle_trim.gd")


static func build(g: VehicleGeo, gl: VehicleGeo, z0: float, depth: float, hw: float, yb: float, yt: float, col: Color,
		front_wheel: Vector3, wheel_r: float) -> void:
	var paint := VehicleGeo.mat(col, VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var seam := VehicleGeo.mat(Color(0.03, 0.03, 0.03), VehicleGeo.K.PLASTIC)
	var steel := VehicleGeo.mat(Color(0.6, 0.62, 0.64), VehicleGeo.K.METAL)
	var z1 := z0 + depth
	P.slab_rows(g, [[z0, hw - 0.06, yb + 0.05, yt - 0.07, 0.16, 0.05], [z0 + 0.07, hw, yb, yt, 0.2, 0.06],
		[z1 - 0.06, hw, yb, yt, 0.2, 0.06], [z1, hw - 0.04, yb + 0.04, yt - 0.04, 0.18, 0.05]], paint, 4)
	var h := yt - yb
	var ws0 := yb + h * 0.52  # windscreen bottom
	var ws1 := yt - 0.14
	P.end_pane(g, gl, -hw + 0.14, hw - 0.14, z0, ws0, z0, ws1, true)
	T.wipers(g, -hw + 0.3, hw - 0.3, ws0, z0)
	g.box(Vector3(0, yt - 0.06, z0 - 0.06), Vector3(hw * 2.0 - 0.1, 0.05, 0.16), black, 0.015)  # sun visor
	T.grille(g, -hw + 0.3, hw - 0.3, yb + h * 0.22, yb + h * 0.44, z0, 5)
	# bumper: steel with lamps and plate, a black lower lip
	g.box(Vector3(0, yb - 0.02, z0 - 0.08), Vector3(hw * 2.0 + 0.04, 0.3, 0.2), steel, 0.05)
	g.box(Vector3(0, yb - 0.2, z0 - 0.06), Vector3(hw * 2.0 - 0.1, 0.1, 0.16), black, 0.03)
	for s in [-1.0, 1.0]:
		T.headlamp(g, Vector3(s * (hw - 0.3), yb + 0.0, z0 - 0.19), Vector3(0.3, 0.16, 0.05))
		g.box(Vector3(s * (hw - 0.08), yb + 0.0, z0 - 0.185), Vector3(0.1, 0.12, 0.04), VehicleGeo.mat(P.AMBER, VehicleGeo.K.TAPE), 0.01)  # indicator
	T.plate(g, Vector3(0, yb - 0.02, z0 - 0.185), 0.5, 0.14, Vector3.FORWARD)
	for s in [-1.0, 1.0]:
		var x: float = s * (hw + 0.002)
		var dz0 := z0 + 0.25
		var dz1 := z1 - 0.15
		P.side_pane(g, gl, s * hw, dz0 + 0.06, dz1 - 0.05, ws0, ws1 - 0.04)
		for dz in [dz0, dz1]:  # door seams
			g.poly([Vector3(x, yb + 0.12, dz - 0.006), Vector3(x, yb + 0.12, dz + 0.006), Vector3(x, yt - 0.15, dz + 0.006), Vector3(x, yt - 0.15, dz - 0.006)], Vector3(s, 0, 0), seam)
		g.poly([Vector3(x, yb + 0.12, dz0), Vector3(x, yb + 0.12, dz1), Vector3(x, yb + 0.132, dz1), Vector3(x, yb + 0.132, dz0)], Vector3(s, 0, 0), seam)
		g.box(Vector3(s * (hw + 0.01), ws0 - 0.12, dz1 - 0.15), Vector3(0.02, 0.04, 0.14), black, 0.008)  # handle
		T.step(g, Vector3(s * (hw - 0.05), yb - 0.25, (dz0 + dz1) * 0.5), 0.5, 0.2)
		T.step(g, Vector3(s * (hw - 0.05), yb - 0.62, (dz0 + dz1) * 0.5), 0.5, 0.2)
		g.box(Vector3(s * (hw - 0.05), yb - 0.44, dz0 + 0.02), Vector3(0.03, 0.4, 0.03), black)
		g.box(Vector3(s * (hw - 0.05), yb - 0.44, dz1 - 0.02), Vector3(0.03, 0.4, 0.03), black)
		T.grab_rail(g, Vector3(s * hw, ws0 - 0.5, z1 - 0.05), 0.9)
		T.mirror(g, Vector3(s * (hw + 0.24), ws0 + 0.25, z0 + 0.18), 1.2)
		T.marker(g, Vector3(s * (hw + 0.005), yb + 0.2, z0 + 0.12), s)
		P.fender(g, front_wheel * Vector3(s, 1, 1), wheel_r, 0.32, black, 0.07, 55.0, 178.0, 8)
	T.beacon(g, Vector3(0, yt, z0 + depth * 0.45), 0, 0.17)
	g.box(Vector3(0, (yb + yt) * 0.5, z1 + 0.02), Vector3(hw * 2.0 - 0.4, h - 0.4, 0.03), VehicleGeo.mat(Color(0.2, 0.2, 0.21), VehicleGeo.K.PLASTIC), 0.01)  # rear wall panel
