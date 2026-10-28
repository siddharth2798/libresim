class_name FollowMeRoof
extends RefCounted
## Follow-me car, roof: rack, amber light bar, the chequered FOLLOW ME board on two posts (facing
## aft, where the aircraft is, and forward) with a beacon at each top corner, antenna.

const BAR_Z := -0.02
const BAR_Y := 1.91
const SIGN_Z := 0.42
const SIGN_Y := 2.12
const SIGN_SIZE := Vector2(1.30, 0.42)
const BEACON_Y := 2.40
## Beacon positions: [side (0 left, 1 right), position], used by the lens meshes and the light points.
const LAMPS := [
	[0, Vector3(-0.50, BAR_Y, BAR_Z)], [0, Vector3(-0.16, BAR_Y, BAR_Z)], [0, Vector3(-0.62, BEACON_Y, SIGN_Z)],
	[1, Vector3(0.50, BAR_Y, BAR_Z)], [1, Vector3(0.16, BAR_Y, BAR_Z)], [1, Vector3(0.62, BEACON_Y, SIGN_Z)]]


static func build(g: VehicleGeo) -> void:
	var black := VehicleGeo.mat(FollowMeBody.BLACK, VehicleGeo.K.PLASTIC)
	var metal := VehicleGeo.mat(Color(0.12, 0.12, 0.13), VehicleGeo.K.METAL)
	var ry := FollowMeCabin.ROOF_Y
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.55, ry + 0.03, 0.25), Vector3(0.04, 0.03, 0.92), metal, 0.008)  # rails
		g.box(Vector3(s * 0.55, ry + 0.012, -0.12), Vector3(0.06, 0.03, 0.06), black)  # feet
		g.box(Vector3(s * 0.55, ry + 0.012, 0.62), Vector3(0.06, 0.03, 0.06), black)
	g.box(Vector3(0, ry + 0.065, BAR_Z), Vector3(1.30, 0.03, 0.05), metal, 0.008)  # cross bars
	g.box(Vector3(0, ry + 0.065, SIGN_Z), Vector3(1.30, 0.03, 0.05), metal, 0.008)
	_light_bar(g, black)
	_sign(g, black, metal)
	g.strut(Vector3(-0.62, ry, 0.64), Vector3(-0.66, 2.18, 0.69), 0.012, 0.012, metal)  # antenna


static func _light_bar(g: VehicleGeo, black: Color) -> void:
	g.box(Vector3(0, FollowMeCabin.ROOF_Y + 0.10, BAR_Z), Vector3(1.28, 0.03, 0.15), black, 0.008)
	var l := VehicleGeo.mat(FollowMeBody.AMBER, VehicleGeo.K.LENS_L)
	var r := VehicleGeo.mat(FollowMeBody.AMBER, VehicleGeo.K.LENS_R)
	g.box(Vector3(-0.33, BAR_Y - 0.01, BAR_Z), Vector3(0.58, 0.11, 0.13), l, 0.035)
	g.box(Vector3(0.33, BAR_Y - 0.01, BAR_Z), Vector3(0.58, 0.11, 0.13), r, 0.035)
	g.box(Vector3(0, BAR_Y - 0.01, BAR_Z), Vector3(0.06, 0.12, 0.14), black, 0.01)


static func _sign(g: VehicleGeo, black: Color, metal: Color) -> void:
	var ry := FollowMeCabin.ROOF_Y
	var post_top := SIGN_Y - SIGN_SIZE.y * 0.5
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.52, (ry + post_top) * 0.5, SIGN_Z), Vector3(0.04, post_top - ry, 0.04), metal, 0.008)
	var board := VehicleGeo.mat(FollowMeBody.YELLOW, VehicleGeo.K.PLASTIC)
	var face := VehicleGeo.mat(FollowMeBody.YELLOW, VehicleGeo.K.SIGN)
	var hx := SIGN_SIZE.x * 0.5
	var hy := SIGN_SIZE.y * 0.5
	g.box(Vector3(0, SIGN_Y, SIGN_Z), Vector3(SIGN_SIZE.x, SIGN_SIZE.y, 0.05), board, 0.012)
	for s in [-1.0, 1.0]:  # s = +1 faces aft
		var z: float = SIGN_Z + s * 0.0265
		var pts := [Vector3(-hx, SIGN_Y - hy, z), Vector3(hx, SIGN_Y - hy, z), Vector3(hx, SIGN_Y + hy, z), Vector3(-hx, SIGN_Y + hy, z)]
		var uv := [Vector2(1, 1), Vector2(0, 1), Vector2(0, 0), Vector2(1, 0)] if s > 0.0 else [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		g.poly(pts, Vector3(0, 0, s), face, uv)
	for lamp in LAMPS:
		if lamp[1].y > 2.0:
			var k := VehicleGeo.K.LENS_L if lamp[0] == 0 else VehicleGeo.K.LENS_R
			g.box(lamp[1] - Vector3(0, 0.04, 0), Vector3(0.11, 0.11, 0.11), VehicleGeo.mat(FollowMeBody.AMBER, k), 0.03)
	g.box(Vector3(0, SIGN_Y + hy + 0.012, SIGN_Z), Vector3(1.0, 0.02, 0.04), black, 0.005)
