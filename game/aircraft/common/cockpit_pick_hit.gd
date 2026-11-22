class_name CockpitPickHit
extends RefCounted
## Ray tests for cockpit picking (CockpitPick.pick). A pivot is hit on its own meshes (not a nested pivot's), tested
## triangle by triangle in each mesh's own frame, so a turned knob's loose bounding box no longer swallows the buttons
## next to it. A pivot with no mesh (a hotspot on a static part of the panel) is a box of `half` metres around it.
## exact(): distance along the ray to a real hit, or -1.  near(): the same against each mesh's own box grown by PAD,
## for a pointer that grazes the edge of a small part.

const PAD := 0.002
const EMPTY_HALF := 0.03

static var _tri := {}  # Mesh instance id -> TriangleMesh


static func exact(pivot: Node3D, from: Vector3, dir: Vector3, half: float = EMPTY_HALF) -> float:
	var meshes := owned_meshes(pivot)
	if meshes.is_empty():
		var p := pivot.global_position
		return ray_box(from, dir, AABB(p - Vector3.ONE * half, Vector3.ONE * half * 2.0))
	var best := -1.0
	for m in meshes:
		var mi := m as MeshInstance3D
		var inv := mi.global_transform.affine_inverse()
		var tm := _triangles(mi.mesh)
		if tm == null:
			continue
		var hit := tm.intersect_ray(inv * from, (inv.basis * dir).normalized())
		if hit.is_empty():
			continue
		var t := (mi.global_transform * (hit.position as Vector3) - from).length()
		if best < 0.0 or t < best:
			best = t
	return best


static func near(pivot: Node3D, from: Vector3, dir: Vector3) -> float:
	var best := -1.0
	for m in owned_meshes(pivot):
		var mi := m as MeshInstance3D
		var inv := mi.global_transform.affine_inverse()
		var lf: Vector3 = inv * from
		var ld: Vector3 = (inv.basis * dir).normalized()
		var t := ray_box(lf, ld, mi.get_aabb().grow(PAD))
		if t < 0.0:
			continue
		t = (mi.global_transform * (lf + ld * t) - from).length()
		if best < 0.0 or t < best:
			best = t
	return best


static func owned_meshes(pivot: Node) -> Array:
	var out: Array = []
	if pivot is MeshInstance3D:
		out.append(pivot)
	for mi in pivot.find_children("*", "MeshInstance3D", true, false):
		if _nearest_pivot(mi) == pivot and (mi as MeshInstance3D).mesh != null:
			out.append(mi)
	return out


static func depth(n: Node) -> int:
	var d := 0
	var p := n.get_parent()
	while p != null:
		d += 1
		p = p.get_parent()
	return d


static func ray_box(from: Vector3, dir: Vector3, box: AABB) -> float:
	var t0 := 0.0
	var t1 := 1.0e8
	var lo := box.position
	var hi := box.end
	for a in 3:
		var o: float = from[a]
		var d: float = dir[a]
		if absf(d) < 1.0e-8:
			if o < lo[a] or o > hi[a]:
				return -1.0
			continue
		var ta := (lo[a] - o) / d
		var tb := (hi[a] - o) / d
		if ta > tb:
			var s := ta
			ta = tb
			tb = s
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return -1.0
	if t1 < 0.0:
		return -1.0
	return maxf(t0, 0.0)


static func _triangles(mesh: Mesh) -> TriangleMesh:
	if mesh == null:
		return null
	var id := mesh.get_instance_id()
	if not _tri.has(id):
		_tri[id] = mesh.generate_triangle_mesh()
	return _tri[id]


static func _nearest_pivot(node: Node) -> Node:
	var n := node.get_parent()
	while n != null:
		if str(n.name).begins_with("pivot_"):
			return n
		n = n.get_parent()
	return null
