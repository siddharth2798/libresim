class_name FollowMeShell
extends RefCounted
## Builds the follow-me car body mesh: surface 0 = opaque body (paint, plastic, lenses, board), surface 1 = glass.
## Parts: follow_me_body.gd, follow_me_cabin.gd, follow_me_roof.gd; wheels: follow_me_wheel.gd.


static func build(body_mat: Material, glass_mat: Material) -> ArrayMesh:
	var g := VehicleGeo.new()
	var gl := VehicleGeo.new()
	FollowMeBody.build(g)
	FollowMeCabin.build(g, gl)
	FollowMeRoof.build(g)
	var mesh := ArrayMesh.new()
	g.commit(mesh, body_mat)
	gl.commit(mesh, glass_mat)
	return mesh


## Triangles in a mesh (all surfaces).
static func triangles(mesh: ArrayMesh) -> int:
	var n := 0
	for i in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n
