class_name GroundCoverMeshes
extends RefCounted
## Unit-height meshes of the ground cover kinds (GroundCoverRules: GRASS, FERN, SHRUB), base at y = 0, cards textured
## from the leaf-card atlas (TreeParts cells). Grass: two tufts of three crossed upright quads (12 triangles); fern: six cards leaning
## out from the base (12); shrub: a loose ball of eight cards (16). Normals point mostly up, so they light like the
## ground they stand on.

static var _cache := {}


static func get_mesh(kind: int) -> ArrayMesh:
	if not _cache.has(kind):
		_cache[kind] = build(kind)
	return _cache[kind]


static func build(kind: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	match kind:
		GroundCoverRules.FERN:
			for k in 6:
				var a := TAU * (k + 0.3) / 6.0
				var out := Vector3(cos(a), 0, sin(a))
				_card(v, n, uv, idx, out * 0.08, out.cross(Vector3.UP), (Vector3.UP * 0.75 + out * 0.6).normalized(), 0.75, 1.1, TreeParts.CELL_FERN)
		GroundCoverRules.SHRUB:
			for k in 8:
				var a := TAU * k / 8.0 + 0.4 * sin(k * 3.1)
				var out := Vector3(cos(a), 0, sin(a)) * (0.18 if k < 6 else 0.0)
				var side := Vector3(cos(a + 1.2), 0, sin(a + 1.2))
				_card(v, n, uv, idx, out + Vector3(0, 0.05 + 0.12 * (k % 3), 0), side, Vector3.UP.rotated(side, 0.25 * (k % 3 - 1)), 0.85, 0.8, TreeParts.CELL_SHRUB)
		_:  # two tufts side by side, so a field reads as a sward rather than dotted clumps
			for t in 2:
				var o := Vector3(0.45, 0, 0.1) * (1.0 if t == 0 else -1.0)
				for k in 3:
					var a := PI * k / 3.0 + t * 0.5
					_card(v, n, uv, idx, o, Vector3(cos(a), 0, sin(a)), Vector3.UP, 1.2, 1.0 - 0.25 * t, TreeParts.CELL_GRASS)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func triangle_count(m: ArrayMesh) -> int:
	return m.surface_get_array_index_len(0) / 3


## A card from foot `o` (bottom edge centre) spanning `side` (width w) and rising along `up` (height h).
static func _card(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array,
		o: Vector3, side: Vector3, up: Vector3, w: float, h: float, cell: Vector2i) -> void:
	var base := v.size()
	var s := side.normalized() * w * 0.5
	var corners := [o - s, o + s, o + s + up * h, o - s + up * h]
	var tex := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for q in 4:
		v.append(corners[q])
		n.append((Vector3.UP * 0.8 + side.cross(up).normalized() * 0.2).normalized())
		uv.append((Vector2(cell) + tex[q]) / TreeParts.ATLAS)
	idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
