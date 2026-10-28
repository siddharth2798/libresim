class_name VehTug
extends RefCounted
## Aircraft pushback tug (towbarless style): low yellow body, glazed cab at the front, nose-gear cradle
## arms at the rear (toward the aircraft), beacon, hazard chevrons. About 4.6 x 2.3 x 2.4 m, scaled
## for bigger aircraft by GroundVehicles.make(kind, size) (ground.tug_scale; the cradle is at z +2.9 m x size). Generic.


static func build(g: VehicleGeo, gl: VehicleGeo) -> void:
	var P := VehicleParts
	var yellow := VehicleGeo.mat(Color(0.98, 0.72, 0.04), VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(P.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.3, 0.31, 0.33), VehicleGeo.K.METAL)
	for z in [-1.4, 0.9]:
		P.axle(g, z, 1.05, 0.5, 0.42, 12)
		for s in [-1.0, 1.0]:
			P.arch_dark(g, s * 1.12, 0.5, z, 0.62, 0.4)
			P.arch_flare(g, s, 1.12, 0.5, z, 0.62, black)
	P.slab_rows(g, [[-2.3, 1.0, 0.42, 1.1, 0.2, 0.08], [-2.2, 1.12, 0.38, 1.2, 0.2, 0.08], [1.4, 1.12, 0.38, 1.2, 0.18, 0.08], [1.5, 1.05, 0.42, 1.15, 0.18, 0.08]], yellow)
	P.slab_rows(g, [[-1.9, 0.9, 1.2, 2.25, 0.2, 0.05], [-1.8, 0.98, 1.15, 2.35, 0.22, 0.05], [-0.1, 0.98, 1.15, 2.35, 0.22, 0.05], [0.0, 0.9, 1.2, 2.25, 0.2, 0.05]], yellow)  # cab
	P.end_pane(g, gl, -0.8, 0.8, -1.9, 1.35, -1.9, 2.2, true)
	P.end_pane(g, gl, -0.8, 0.8, 0.0, 1.4, 0.0, 2.2, false)
	for s in [-1.0, 1.0]:
		P.side_pane(g, gl, s * 0.983, -1.6, -0.3, 1.4, 2.2)
		P.side_band(g, s * 1.12, -2.1, 1.3, 0.72, 0.84, P.BLACK)
		P.headlamp(g, Vector3(s * 0.75, 0.88, -2.31), Vector3(0.34, 0.2, 0.08))
		P.taillamp(g, Vector3(s * 0.85, 0.9, 1.5), Vector3(0.22, 0.16, 0.06))
		g.box(Vector3(s * 0.55, 0.62, 2.2), Vector3(0.28, 0.2, 1.4), metal, 0.04)  # cradle arms
		g.box(Vector3(s * 1.2, 0.55, -0.6), Vector3(0.18, 0.05, 0.5), black, 0.01)  # step
	g.box(Vector3(0, 0.55, -2.4), Vector3(2.2, 0.3, 0.26), black, 0.06)  # bumper
	g.box(Vector3(0, 2.4, -0.9), Vector3(1.2, 0.08, 1.9), yellow, 0.03)  # cab roof
	P.beacon(g, Vector3(0, 2.44, -0.6), 0, 0.2)
	P.chevrons(g, -1.0, 1.0, 0.45, 0.8, 1.51, true, 10, P.BLACK, Color(0.98, 0.72, 0.04))
