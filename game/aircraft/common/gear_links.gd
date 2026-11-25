class_name GearLinks
extends RefCounted
## Torque links and side stays of a retractable leg (used by TyreContact): they fold about their upper end so the
## leg shortens with the oleo instead of the links floating off their mounts.


## [node, rest position, rest basis, upper hinge, lower tip, length], mesh space, for the link nodes (or their first mesh).
static func make(nodes: Array) -> Array:
	var out: Array = []
	for nd in nodes:
		var mi := nd as MeshInstance3D
		if mi == null or mi.mesh == null:
			var found := (nd as Node).find_children("*", "MeshInstance3D", true, false)
			mi = found[0] if not found.is_empty() else null
		if mi == null or mi.mesh == null:
			continue
		var ends := _ends(mi)
		var hinge: Vector3 = ends[0]
		var tip: Vector3 = ends[1]
		out.append([nd, (nd as Node3D).position, (nd as Node3D).basis, hinge, tip, hinge.distance_to(tip)])
	return out


## The highest and lowest vertices of a link (mesh space): the upper mount and the end that follows the oleo.
static func _ends(mi: MeshInstance3D) -> Array:
	var top := Vector3.ZERO
	var bot := Vector3.ZERO
	var hi := -INF
	var lo := INF
	for si in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = v
			if p.y > hi:
				hi = p.y
				top = p
			if p.y < lo:
				lo = p.y
				bot = p
	return [top, bot]


## Fold a link about its upper end so the lower end rises `stroke` metres along the strut.
static func fold(link: Array, stroke: float) -> void:
	var nd: Node3D = link[0]
	var rest_pos: Vector3 = link[1]
	var rest_basis: Basis = link[2]
	var hinge: Vector3 = link[3]
	var tip: Vector3 = link[4]
	var length: float = link[5]
	var s := clampf(stroke, 0.0, length * 0.85)
	var a := tip - hinge
	var b := a + Vector3(0.0, s, 0.0)
	if a.length() < 1e-4 or b.length() < 1e-4:
		nd.position = rest_pos
		nd.basis = rest_basis
		return
	nd.basis = rest_basis * Basis(Quaternion(a.normalized(), b.normalized()))
	nd.position = rest_pos + rest_basis * hinge - nd.basis * hinge
