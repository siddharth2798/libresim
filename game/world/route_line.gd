class_name RouteLine
extends RefCounted
## The green taxi-route line (GroundOps): a thin strip along the route points, painted on the ground the FDM
## stands on (GroundPaint: draped on the terrain triangles, depth pull instead of a lift, so the nose wheel
## rolls on it rather than sinking into a ribbon 25 cm up).


## route: [Vector2 ENU]; height_at: Callable(e, n) -> m; mat: its colour (albedo_color of a BaseMaterial3D, or
## a ShaderMaterial used as it is). The node sits at its drape origin in render space (shift it with the origin).
static func build(route: Array, height_at: Callable, mat: Material) -> MeshInstance3D:
	var m := mat
	if mat is BaseMaterial3D:
		m = GroundPaint.material((mat as BaseMaterial3D).albedo_color, GroundPaint.PULL_ROUTE)
	var line := GroundPaint.strip(route, 0.7, height_at, m)
	if line == null:  # fewer than 2 points: an empty node keeps the caller simple
		line = MeshInstance3D.new()
		line.position = FloatingOrigin.to_render(Vector3.ZERO)
		return line
	line.position = FloatingOrigin.to_render(GroundPaint.enu_origin(line))
	return line
