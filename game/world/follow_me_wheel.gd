class_name FollowMeWheel
extends RefCounted
## One wheel mesh for the follow-me car: tyre (rounded shoulders, tread by shader), steel dish with a
## centre cap and lug nuts. Axis along x, outer face toward +x (the left wheels are turned round).

const SEGS := 18
const R := FollowMeLogic.WHEEL_R


static func build(material: Material) -> ArrayMesh:
	var g := VehicleGeo.new()
	var rubber := VehicleGeo.mat(Color(0.05, 0.05, 0.055), VehicleGeo.K.RUBBER)
	var steel := VehicleGeo.mat(Color(0.52, 0.54, 0.56), VehicleGeo.K.METAL)
	var cap := VehicleGeo.mat(Color(0.75, 0.77, 0.8), VehicleGeo.K.METAL)
	var dark := VehicleGeo.mat(Color(0.03, 0.03, 0.035), VehicleGeo.K.PLASTIC)
	var tyre := PackedVector2Array([
		Vector2(-0.112, 0.205), Vector2(-0.122, 0.25), Vector2(-0.106, 0.325), Vector2(-0.068, R - 0.003),
		Vector2(0.068, R - 0.003), Vector2(0.106, 0.325), Vector2(0.122, 0.25), Vector2(0.112, 0.205)])
	g.lathe_x(tyre, Vector3.ZERO, SEGS, rubber)
	g.lathe_x(PackedVector2Array([Vector2(0.0, 0.205), Vector2(0.0, 0.0)]), Vector3.ZERO, SEGS, dark)
	var dish := PackedVector2Array([Vector2(0.108, 0.206), Vector2(0.088, 0.19), Vector2(0.062, 0.115), Vector2(0.074, 0.07), Vector2(0.074, 0.0)])
	g.lathe_x(dish, Vector3.ZERO, SEGS, steel)
	var centre := PackedVector2Array([Vector2(0.074, 0.066), Vector2(0.092, 0.058), Vector2(0.102, 0.03), Vector2(0.104, 0.0)])
	g.lathe_x(centre, Vector3.ZERO, SEGS, cap)
	var nut := PackedVector2Array([Vector2(0.068, 0.0), Vector2(0.068, 0.014), Vector2(0.086, 0.014), Vector2(0.086, 0.0)])
	for i in 5:
		var a := TAU * i / 5.0
		g.lathe_x(nut, Vector3(0.0, 0.1 * cos(a), 0.1 * sin(a)), 5, cap)
	var mesh := ArrayMesh.new()
	g.commit(mesh, material)
	return mesh
