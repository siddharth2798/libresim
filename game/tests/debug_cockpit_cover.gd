extends Node
## Debug: list interior meshes that extend in front of (toward the pilot) or across each gauge quad.
var t := 0.0
var done := false


func _ready() -> void:
	add_child(load("res://world/flight.tscn").instantiate())


func _find(n: Node) -> Node:
	if n.has_method("forward_mouse") and "interior" in n:
		return n
	for c in n.get_children():
		var r := _find(c)
		if r:
			return r
	return null


func _process(dt: float) -> void:
	t += dt
	if t < 3.0 or done:
		return
	done = true
	var ck := _find(self)
	var inv: Transform3D = ck.global_transform.affine_inverse()
	for q in ck._quads:
		var mi: MeshInstance3D = q[0]
		var size: Vector2 = (mi.mesh as QuadMesh).size
		var c := mi.position
		var rect := Rect2(c.x - size.x / 2, c.y - size.y / 2, size.x, size.y)
		print("QUAD z=%.4f rect=%s" % [c.z, rect])
		for m in ck.interior.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (inv * (m as MeshInstance3D).global_transform) * (m as MeshInstance3D).get_aabb()
			if a.end.z < c.z - 0.002:
				continue
			if not Rect2(a.position.x, a.position.y, a.size.x, a.size.y).intersects(rect):
				continue
			print("   %s  zrange %.4f..%.4f  xy %.3f,%.3f size %.3f,%.3f surf=%d" % [m.name, a.position.z, a.end.z, a.position.x, a.position.y, a.size.x, a.size.y, (m as MeshInstance3D).mesh.get_surface_count()])
	get_tree().quit()
