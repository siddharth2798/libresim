class_name SkinProbe
extends RefCounted
## Where an aircraft's outer skin is, measured on its exterior meshes: a ray from outside toward the centre line at structural
## (x, z) finds the skin's y. Used to lay door panels on the real surface (CabinDoorPanel), which is not a circle (the A320's
## lower lobe is wider than its crown). Meshes become TriangleMeshes once. Structural frame x aft, y right, z up.

const FROM_M := 8.0  # rays start this far out from the centre line

var _meshes: Array = []  # [TriangleMesh, Transform3D model local -> mesh local]
var _s: Callable  # structural -> model local


## exterior: the glb root under `model`; s: structural -> model local (AircraftModel._s). Null without meshes.
static func make(exterior: Node3D, model: Node3D, s: Callable) -> SkinProbe:
	if exterior == null:
		return null
	var p := SkinProbe.new()
	p._s = s
	for n in exterior.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var t := Transform3D.IDENTITY
		var at: Node = mi
		while at != null and at != model:
			if at is Node3D:
				t = (at as Node3D).transform * t
			at = at.get_parent()
		var tm := mi.mesh.generate_triangle_mesh()
		if tm != null:
			p._meshes.append([tm, t.affine_inverse()])
	return p if not p._meshes.is_empty() else null


## The skin's structural y at (x, z) on `side` (-1 left, +1 right); NAN when the ray finds nothing.
func y_at(x: float, z: float, side: float) -> float:
	var from: Vector3 = _s.call(Vector3(x, side * FROM_M, z))
	var dir: Vector3 = (_s.call(Vector3(x, 0.0, z)) as Vector3) - from
	var len := dir.length()
	dir /= len
	var best := INF
	for m in _meshes:
		var inv: Transform3D = m[1]
		var hit: Dictionary = (m[0] as TriangleMesh).intersect_ray(inv * from, (inv.basis * dir).normalized())
		if not hit.is_empty():
			best = minf(best, (inv.affine_inverse() * (hit.position as Vector3) - from).dot(dir))
	return side * (FROM_M - best) if best < len else NAN
