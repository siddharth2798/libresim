class_name OccluderBuild
extends RefCounted
## Occluders for occlusion culling (OcclusionRules), made at run time from a model's own triangles rather than baked in
## the editor: its walls. Two vertical triangles that share an edge (the very same vertices) and together make a
## rectangle with level top and bottom are one wall panel; panels stacked on the same footprint edge (floor bands, glass
## over a plinth) are merged. The panels then become footprint rings and strips (OccluderRings), which are moved MARGIN
## inside the building. So an occluder never hides something the building does not: the occlusion buffer is coarse,
## and the margin keeps its edge error behind the walls. Columns, fins and slivers are left out. Pure function of its
## input: runs on worker threads.

const MARGIN := 1.0  # m inside the walls
const VERTICAL := 0.01  # |normal.y| below this is a wall
const EPS := 0.02  # m: corners this close are the same


## faces: 3 vertices per triangle (y up). Returns [PackedVector3Array vertices, PackedInt32Array indices] of the
## occluders (empty arrays when there are none).
static func build(faces: PackedVector3Array, margin := MARGIN, min_w := OccluderRings.MIN_W, min_h := OccluderRings.MIN_H) -> Array:
	var out := [PackedVector3Array(), PackedInt32Array()]
	OccluderRings.emit(OccluderRings.chain(segments(faces)), margin, min_w, min_h, out)
	return out


## Wall panels as footprint segments [Vector2 p, Vector2 q, y0, y1, Vector2 normal] (x, z plane), stacked ones merged.
static func segments(faces: PackedVector3Array) -> Array:
	var by_edge := {}  # [Vector3, Vector3] (sorted) -> first triangle index with that edge
	var panels := []
	for t in range(0, faces.size() - 2, 3):
		var nn := (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t])
		if nn.length() < 0.2 or absf(nn.normalized().y) > VERTICAL:
			continue
		for e in 3:
			var a := faces[t + e]
			var b := faces[t + (e + 1) % 3]
			var k := [a, b] if [a.x, a.y, a.z] < [b.x, b.y, b.z] else [b, a]
			if by_edge.has(k):
				var seg := _panel(faces, by_edge[k], t, nn)
				if not seg.is_empty():
					panels.append(seg)
				by_edge.erase(k)
			else:
				by_edge[k] = t
	return _stack(panels)


## The panel two triangles make, or [] when they are not a quad with vertical sides. Its height range is the part every
## column of it covers (base and top may follow the ground a little).
static func _panel(faces: PackedVector3Array, t0: int, t1: int, nn: Vector3) -> Array:
	var pts: Array[Vector3] = []
	for t in [t0, t1]:
		for i in 3:
			var p := faces[t + i]
			if not pts.any(func(q: Vector3) -> bool: return q.distance_to(p) < EPS):
				pts.append(p)
	if pts.size() != 4:
		return []
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var lo := [Vector2(pts[0].x, pts[0].z), Vector2(pts[1].x, pts[1].z)]
	var hi := [Vector2(pts[2].x, pts[2].z), Vector2(pts[3].x, pts[3].z)]
	if not ((lo[0].distance_to(hi[0]) < EPS and lo[1].distance_to(hi[1]) < EPS) or (lo[0].distance_to(hi[1]) < EPS and lo[1].distance_to(hi[0]) < EPS)):
		return []
	var y0 := pts[1].y
	var y1 := pts[2].y
	if y1 - y0 < 0.5 or lo[0].distance_to(lo[1]) < 0.1:
		return []
	var n := Vector2(nn.x, nn.z).normalized()
	var u := Vector2(-n.y, n.x)  # along the wall, one fixed way round the normal
	if (lo[1] - lo[0]).dot(u) < 0.0:
		lo.reverse()
	return [lo[0], lo[1], y0, y1, n]


## Merge panels on the same footprint edge whose height ranges touch or overlap.
static func _stack(panels: Array) -> Array:
	var groups := {}
	for p in panels:
		var k := "%d|%d|%d|%d" % [roundi(p[0].x * 20.0), roundi(p[0].y * 20.0), roundi(p[1].x * 20.0), roundi(p[1].y * 20.0)]
		if not groups.has(k):
			groups[k] = []
		groups[k].append(p)
	var out := []
	for k in groups:
		var g: Array = groups[k]
		g.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
		var cur: Array = g[0].duplicate()
		for i in range(1, g.size()):
			if g[i][2] <= cur[3] + 0.1:
				cur[3] = maxf(cur[3], g[i][3])
			else:
				out.append(cur)
				cur = g[i].duplicate()
		out.append(cur)
	return out


## An OccluderInstance3D for the arrays from walls() (null when empty).
static func instance(arrays: Array, name := "Occluder") -> OccluderInstance3D:
	var verts: PackedVector3Array = arrays[0]
	if verts.is_empty():
		return null
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, arrays[1])
	var oi := OccluderInstance3D.new()
	oi.name = name
	oi.occluder = occ
	oi.add_to_group(OcclusionRules.GROUP)
	return oi


## Triangles of every MeshInstance3D under root, in root's frame (3 vertices per triangle).
static func faces_under(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var nd: Node = mi
		while nd != root and nd is Node3D:
			t = (nd as Node3D).transform * t
			nd = nd.get_parent()
		for p in mi.mesh.get_faces():
			out.append(t * p)
	return out
