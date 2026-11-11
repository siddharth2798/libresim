extends Node
## The A320 flight deck stays inside the fuselage: no interior.glb part may show through the outer skin from outside.
## The rear wall's flat side panels once stood 0.40 m out through the roof behind the sliding windows.

const EXT := "res://aircraft/a320/models/exterior.glb"
const INT := "res://aircraft/a320/models/interior.glb"


## Triangles (3 points each) or, with `only`, the vertices of the named meshes, in the glb root frame
## (glTF: x aft, y up, z = -right).
static func _points(root: Node, only: Array, tris: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not only.is_empty() and not (mi.name in only):
			continue
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != root:
			t = (p as Node3D).transform * t if p is Node3D else t
			p = p.get_parent()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if not tris:
				for v in vs:
					out.append(t * v)
				continue
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in idx:
				out.append(t * vs[i])
	return out


## A ray straight up from the cabin (y 0.3) at every outboard wall vertex must hit the skin above that vertex.
func test_flight_deck_rear_wall_stays_under_the_roof() -> String:
	var ext: Node = (load(EXT) as PackedScene).instantiate()
	var inn: Node = (load(INT) as PackedScene).instantiate()
	var wall := _points(inn, ["deck_door"], false)
	var all := _points(ext, [], true)
	ext.free()
	inn.free()
	var x := wall[0].x if not wall.is_empty() else 0.0
	var skin := PackedVector3Array()  # triangles near the wall
	for i in range(0, all.size(), 3):
		if absf(all[i].x - x) < 1.5 or absf(all[i + 1].x - x) < 1.5 or absf(all[i + 2].x - x) < 1.5:
			skin.append_array([all[i], all[i + 1], all[i + 2]])
	if wall.is_empty() or skin.size() < 300:
		return "no wall (%d) or skin (%d) points" % [wall.size(), skin.size()]
	var worst := -INF
	for v in wall:
		if absf(v.z) < 0.6 or v.y < 0.3:
			continue  # the centre of the deck is far below the crown
		var top := INF
		for i in range(0, skin.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(Vector3(v.x, 0.3, v.z), Vector3.UP, skin[i], skin[i + 1], skin[i + 2])
			if hit != null:
				top = minf(top, (hit as Vector3).y)
		worst = maxf(worst, v.y - top)
	return "" if worst < 0.0 else "the rear wall stands %.2f m above the roof" % worst
