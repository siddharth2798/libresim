class_name VehicleGround
extends RefCounted
## Ground decal mesh of a procedural vehicle kind (world/vehicle_ground.gdshader): a soft contact shadow
## under the body footprint, a blob under every tyre, and the headlamp light pool (lit at night when the
## vehicle is working). Built from what the body builder recorded (VehicleGeo.wheels / lamps) and the
## body's bounds; a few quads, one draw call. Lies 4 cm above the vehicle's ground plane.

const LIFT := 0.04
const POOL_M := 14.0  # light pool length ahead of the lamps


static func build(aabb: AABB, wheels: Array, lamps: Array, material: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var add := func(c: Vector2, half: Vector2, shape_h: Vector2, shape: float, k: float, y0: float) -> void:
		for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			st.set_color(Color(shape, k, 0, 1))
			st.set_uv(Vector2(q.x * half.x, -q.y * half.y + y0))
			st.set_uv2(shape_h)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(c.x + q.x * half.x, LIFT, c.y + q.y * half.y))
	var quads := []
	var bc := Vector2(aabb.get_center().x, aabb.get_center().z)
	var bh := Vector2(aabb.size.x, aabb.size.z) * 0.5
	quads.append([bc, bh + Vector2(0.6, 0.6), bh * 0.92, 0.0, 0.5, 0.0])
	for w in wheels:
		var c: Vector3 = w[0]
		var r: float = w[1]
		var wd: float = w[2]
		var sh := Vector2(wd * 0.75, r * 0.75)
		quads.append([Vector2(c.x, c.z), sh * 2.0, sh, 0.5, 0.6, 0.0])
	var heads := []
	for l in lamps:
		if l[0] == "head":
			heads.append(l[1])
	if not heads.is_empty():
		var hx := 0.0
		var hz := 0.0
		var x0 := INF
		var x1 := -INF
		for p in heads:
			hx += p.x / heads.size()
			hz = minf(hz, p.z)
			x0 = minf(x0, p.x)
			x1 = maxf(x1, p.x)
		var half_w := maxf((x1 - x0) * 0.5 + 1.2, 1.6) * 1.8
		quads.append([Vector2(hx, hz - POOL_M * 0.5), Vector2(half_w, POOL_M * 0.5), Vector2(half_w * 0.6, POOL_M), 1.0, 0.4, POOL_M * 0.5])
	for q in quads:
		add.call(q[0], q[1], q[2], q[3], q[4], q[5])
		st.add_index(n)
		st.add_index(n + 2)
		st.add_index(n + 1)
		st.add_index(n)
		st.add_index(n + 3)
		st.add_index(n + 2)
		n += 4
	var m := st.commit()
	m.surface_set_material(0, material)
	return m
