class_name RouteLine
extends RefCounted
## The green taxi-route line (GroundOps): a thin strip along the route points, draped on the terrain.


## route: [Vector2 ENU]; height_at: Callable(e, n) -> m. The node sits at the floating-origin render offset.
static func build(route: Array, height_at: Callable, mat: Material) -> MeshInstance3D:
	var verts := PackedVector3Array()
	for i in range(route.size() - 1):
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var d := (b - a).normalized()
		var sd := Vector2(d.y, -d.x) * 0.35
		var n := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var h0: float = height_at.call(p0.x, p0.y) + 0.25
			var h1: float = height_at.call(p1.x, p1.y) + 0.25
			for v in [p0 - sd, p0 + sd, p1 + sd, p0 - sd, p1 + sd, p1 - sd]:
				var h: float = h0 if v.distance_to(p0) < v.distance_to(p1) else h1
				verts.append(Vector3(v.x, h, -v.y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var line := MeshInstance3D.new()
	line.mesh = m
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.position = FloatingOrigin.to_render(Vector3.ZERO)
	return line
