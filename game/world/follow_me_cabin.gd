class_name FollowMeCabin
extends RefCounted
## Follow-me car, cabin: roof shell, pillars, window glass (a second surface with the glass shader),
## a simple interior seen through the windows, mirrors, door handles, wipers.
## Right-hand drive (India): the driver sits on the right.

const ROOF_Y := 1.76
const BELT := 1.10
## Pillar centre lines, bottom -> top (right side; the left is mirrored in x)
const A_BOT := Vector3(0.89, BELT, -1.08)
const A_TOP := Vector3(0.69, 1.72, -0.20)
const B_BOT := Vector3(0.91, BELT, -0.12)
const B_TOP := Vector3(0.72, 1.70, -0.10)
const C_BOT := Vector3(0.90, BELT, 0.78)
const C_TOP := Vector3(0.72, 1.70, 0.66)


static func build(g: VehicleGeo, glass: VehicleGeo) -> void:
	var paint := VehicleGeo.mat(FollowMeBody.YELLOW, VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(FollowMeBody.BLACK, VehicleGeo.K.PLASTIC)
	_roof(g, paint)
	for s in [-1.0, 1.0]:
		for p in [[A_BOT, A_TOP, 0.075], [B_BOT, B_TOP, 0.085], [C_BOT, C_TOP, 0.09]]:
			g.strut(_mx(p[0], s), _mx(p[1], s), p[2], 0.06, black, 0.012)
	_glass(glass)
	_interior(g)
	_fittings(g, black)


static func _mx(p: Vector3, s: float) -> Vector3:
	return Vector3(p.x * s, p.y, p.z)


static func _roof(g: VehicleGeo, paint: Color) -> void:
	var rows := []
	for k in [[-0.21, 0.70], [-0.17, 0.73], [-0.10, 0.74], [0.60, 0.74], [0.66, 0.73], [0.70, 0.69]]:
		rows.append(VehicleGeo.ring(k[1], ROOF_Y - 0.075, ROOF_Y, 0.04, 0.03, k[0], 4))
	g.loft(rows, paint)
	g.poly(rows[0], Vector3.FORWARD, paint)
	g.poly(rows[-1], Vector3.BACK, paint)


static func _glass(gl: VehicleGeo) -> void:
	var c := Color(0.03, 0.04, 0.045)  # tint, applied by the glass shader
	gl.poly([Vector3(-A_BOT.x, A_BOT.y, A_BOT.z), Vector3(A_BOT.x, A_BOT.y, A_BOT.z), A_TOP, Vector3(-A_TOP.x, A_TOP.y, A_TOP.z)], Vector3(0, 0.6, -1), c)
	gl.poly([Vector3(-C_BOT.x, C_BOT.y, C_BOT.z), Vector3(C_BOT.x, C_BOT.y, C_BOT.z), C_TOP, Vector3(-C_TOP.x, C_TOP.y, C_TOP.z)], Vector3(0, 0.3, 1), c)
	for s in [-1.0, 1.0]:
		gl.poly([_mx(A_BOT, s), _mx(B_BOT, s), _mx(B_TOP, s), _mx(A_TOP, s)], Vector3(s, 0, 0), c)
		gl.poly([_mx(B_BOT, s), _mx(C_BOT, s), _mx(C_TOP, s), _mx(B_TOP, s)], Vector3(s, 0, 0), c)


static func _interior(g: VehicleGeo) -> void:
	var seat := VehicleGeo.mat(Color(0.10, 0.10, 0.105), VehicleGeo.K.PLASTIC)
	var dark := VehicleGeo.mat(Color(0.045, 0.045, 0.05), VehicleGeo.K.PLASTIC)
	g.box(Vector3(0, BELT + 0.012, -0.09), Vector3(1.78, 0.02, 1.84), dark)  # floor / door cards level
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.36, 1.37, -0.02), Vector3(0.46, 0.56, 0.12), seat, 0.04)
		g.box(Vector3(s * 0.36, 1.20, -0.30), Vector3(0.46, 0.12, 0.50), seat, 0.03)
	g.box(Vector3(0, 1.36, 0.70), Vector3(1.5, 0.50, 0.10), seat, 0.04)
	g.box(Vector3(0, 1.20, 0.44), Vector3(1.5, 0.12, 0.46), seat, 0.03)
	g.box(Vector3(0, 1.22, -0.88), Vector3(1.76, 0.14, 0.30), dark, 0.04)  # dashboard
	g.box(Vector3(0.38, 1.32, -0.76), Vector3(0.34, 0.12, 0.10), dark, 0.03)  # instrument hood
	var ring := PackedVector2Array([Vector2(-0.012, 0.17), Vector2(0.0, 0.182), Vector2(0.012, 0.17), Vector2(0.0, 0.158), Vector2(-0.012, 0.17)])
	g.lathe_x(ring, Vector3(0.38, 1.30, -0.58), 12, seat, Basis(Vector3.UP, -PI / 2) * Basis(Vector3.BACK, 0.5))  # steering wheel


static func _fittings(g: VehicleGeo, black: Color) -> void:
	var mirror_glass := VehicleGeo.mat(Color(0.35, 0.37, 0.4), VehicleGeo.K.METAL)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.99, 1.24, -0.98), Vector3(0.12, 0.04, 0.05), black, 0.01)
		g.box(Vector3(s * 1.04, 1.30, -0.99), Vector3(0.08, 0.17, 0.22), black, 0.03)
		g.box(Vector3(s * 1.04, 1.30, -0.875), Vector3(0.07, 0.15, 0.012), mirror_glass)
		for z in [-0.25, 0.66]:  # door handles
			g.box(Vector3(s * 0.958, 0.97, z), Vector3(0.04, 0.05, 0.16), black, 0.01)
		g.box(Vector3(s * 0.96, 0.62, 0.34), Vector3(0.05, 0.03, 0.30), black, 0.008)  # side step
	for s in [-1.0, 1.0]:  # wipers: parked along the windshield's foot
		g.box(Vector3(s * 0.34 + 0.2, 1.135, -1.03), Vector3(0.45, 0.012, 0.02), black, 0.0, Basis(Vector3.UP, 0.12 * s))
