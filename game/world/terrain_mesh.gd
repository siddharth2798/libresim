class_name TerrainMesh
## Shared grid mesh for every terrain node: (GRID+1)^2 vertices over the unit
## square plus a skirt ring. UV = grid position in [0,1] (u east, v north);
## UV2.x = 1 marks skirt vertices, which the shader pulls downward to hide LOD cracks.
## The shader scales and displaces vertices, so one mesh serves all LODs.

const GRID := 64


static func build() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()
	var w := GRID + 1
	for j in w:
		for i in w:
			verts.append(Vector3(float(i) / GRID, 0.0, -float(j) / GRID))
			uvs.append(Vector2(float(i) / GRID, float(j) / GRID))
			uv2s.append(Vector2.ZERO)
	for j in GRID:
		for i in GRID:
			var a := j * w + i
			# Godot front faces are clockwise seen from the viewer; we look down (-Y)
			idx.append_array([a, a + w, a + 1, a + 1, a + w, a + w + 1])
	# Skirt: walk the border counter-clockwise (seen from above) and drop a copy of it.
	var ring: Array[int] = []
	for i in w: ring.append(i)
	for j in range(1, w): ring.append(j * w + GRID)
	for i in range(GRID - 1, -1, -1): ring.append(GRID * w + i)
	for j in range(GRID - 1, 0, -1): ring.append(j * w)
	var base := verts.size()
	for k in ring:
		verts.append(verts[k])
		uvs.append(uvs[k])
		uv2s.append(Vector2(1.0, 0.0))
	var n := ring.size()
	for s in n:
		var t0: int = ring[s]
		var t1: int = ring[(s + 1) % n]
		var b0 := base + s
		var b1 := base + (s + 1) % n
		idx.append_array([t0, t1, b0, t1, b1, b0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
