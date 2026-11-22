class_name TreeParts
extends RefCounted
## Geometry pieces of the near tree meshes (TreeMeshes): tapered bark tubes, clumps of alpha-tested leaf cards and
## palm fronds. Built in the canonical tree frame (height 1, crown width TreeSpecies.ASPECT, origin at the trunk foot);
## mesh() squeezes x and z by the aspect into the unit mesh the instances scale by (width, height, width).
## COLOR.rgb is the base colour with baked occlusion, COLOR.a the part: 0 bark, 0.5 leaf card, 1 frond.
## UV is in the leaf-card atlas (game/world/textures/trees/leaf_cards.png, tools/tree_leaf_cards.py, 4 x 2 cells).
## COLOR.a 0.1 marks ringed bark (palm trunks: tree_parts.gdshaderinc draws the leaf-scar rings).
## CUSTOM0.xyz is the point a part collapses to, CUSTOM0.w = 1 marks LOD0-only detail: tree_mesh.gdshader shrinks it
## away before TreeLod swaps in the LOD1 mesh, so the swap shows nothing. Normals of leaf cards lean towards the
## direction out of the crown, so a crown shades as one soft mass rather than as a pile of flat cards.

const CELL_BROAD := Vector2i(0, 0)  # mango, banyan, peepal
const CELL_FINE := Vector2i(1, 0)  # acacia
const CELL_NEEDLE := Vector2i(2, 0)  # casuarina
const CELL_GRASS := Vector2i(3, 0)  # grass tuft (GroundCover)
const CELL_FROND := Vector2i(0, 1)  # coconut frond
const CELL_LARGE := Vector2i(1, 1)  # teak, semi-evergreen
const CELL_FERN := Vector2i(2, 1)  # fern / understorey (GroundCover)
const CELL_SHRUB := Vector2i(3, 1)  # small-leaved shrub (GroundCover)
const ATLAS := Vector2(4.0, 2.0)  # cells across, down

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var uv := PackedVector2Array()
var cu := PackedFloat32Array()  # CUSTOM0, 4 floats per vertex
var idx := PackedInt32Array()
var detail := false  # parts added while true are LOD0-only
var rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	rng.seed = seed_value


func vert(p: Vector3, nrm: Vector3, col: Color, t: Vector2, anchor: Vector3) -> int:
	v.append(p)
	n.append(nrm.normalized())
	c.append(col)
	uv.append(t)
	cu.append_array([anchor.x, anchor.y, anchor.z, 1.0 if detail else 0.0])
	return v.size() - 1


## Tapered tube through pts (rings of `sides`), bark coloured; rings = banded shading (palm trunk).
func tube(pts: Array, radii: Array, sides: int, col: Color, rings := false) -> void:
	var kind := 0.1 if rings else 0.0
	var base := v.size()
	for k in pts.size():
		var p: Vector3 = pts[k]
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
		var up := dir.cross(side)
		var shade := lerpf(0.75, 1.0, clampf(p.y * 2.0, 0.0, 1.0))
		for s in sides:
			var a := TAU * s / sides
			var d := side * cos(a) + up * sin(a)
			vert(p + d * float(radii[k]), d, Color(col.r * shade, col.g * shade, col.b * shade, kind), Vector2.ZERO, pts[0])
	for k in pts.size() - 1:
		for s in sides:
			var a0 := base + k * sides + s
			var a1 := base + k * sides + (s + 1) % sides
			idx.append_array([a0, a0 + sides, a1, a1, a0 + sides, a1 + sides])


## `count` leaf cards of about `size` in an ellipsoid clump (centre, radius), facing roughly out of it. up_bias tilts the
## cards towards lying flat (umbrella crowns); hang = upright cards with the texture's top up (casuarina strands).
## crown_c / crown_r: the whole crown, for the soft normals and occlusion.
func cards(centre: Vector3, radius: Vector3, count: int, size: float, cell: Vector2i, col: Color,
		crown_c: Vector3, crown_r: Vector3, up_bias := 0.0, hang := false) -> void:
	for k in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var p := centre + dir * radius * lerpf(0.3, 1.0, sqrt(rng.randf()))
		var face := (dir + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))).normalized()
		face = face.lerp(Vector3.UP, up_bias).normalized()
		var t1 := face.cross(Vector3.UP if absf(face.y) < 0.95 else Vector3.RIGHT).normalized()
		t1 = t1.rotated(face, rng.randf() * TAU)
		var t2 := face.cross(t1)
		if hang:  # upright cards, texture top up (hanging needles): face horizontal, t2 = world up
			face = Vector3(face.x, 0.0, face.z).normalized() if Vector2(face.x, face.z).length() > 0.05 else Vector3.BACK
			t2 = Vector3.UP.rotated(face, rng.randf_range(-0.45, 0.45))
			t1 = t2.cross(face)
		var s := size * rng.randf_range(0.8, 1.2) * 0.5
		var base := v.size()
		var corners := [p - t1 * s - t2 * s, p + t1 * s - t2 * s, p + t1 * s + t2 * s, p - t1 * s + t2 * s]
		var tex := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for q in 4:
			var pc: Vector3 = corners[q]
			var rel := (pc - crown_c) / crown_r
			var out := rel.normalized() if rel.length() > 0.01 else Vector3.UP
			var ao := lerpf(0.4, 1.0, clampf(rel.length(), 0.0, 1.0)) * lerpf(0.72, 1.0, clampf(rel.y * 0.5 + 0.5, 0.0, 1.0))
			var bright := rng.randf_range(0.9, 1.1) * ao
			vert(pc, out * 0.8 + face * 0.2, Color(col.r * bright, col.g * bright, col.b * bright, 0.5),
				(Vector2(cell) + tex[q]) / ATLAS, p)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## Palm frond from o along dir (horizontal unit vector): rises then droops (rise, droop as fractions of length).
## v_shape: two strips folded down from the rachis (LOD0); else one flat strip.
func frond(o: Vector3, dir: Vector3, length: float, rise: float, droop: float, width: float, col: Color, segs: int, v_shape: bool) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	# each strip runs from u0 (at offset s0 across the frond) to u1 (offset s1); offsets in frond half-widths
	var strips := [[0.5, 0.0, 0.0, -1.0], [0.5, 1.0, 0.0, 1.0]] if v_shape else [[0.0, 1.0, -1.0, 1.0]]
	for st in strips:
		var base := v.size()
		for s in segs + 1:
			var t := float(s) / segs
			var p := o + dir * length * t + Vector3.UP * length * (rise * t - droop * t * t)
			var w := width * 0.5 * (0.45 + 0.55 * sin(PI * minf(0.12 + t, 1.0))) * (1.0 - 0.35 * t)
			var shade := lerpf(0.65, 1.0, t)
			var cc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			var nrm := (Vector3.UP + dir * 0.35).normalized()
			for e in 2:
				var off: float = st[2 + e]
				var hang := Vector3.DOWN * w * 0.7 * absf(off)  # leaflets hang below the rachis
				vert(p + side * w * off + hang, nrm, cc, (Vector2(CELL_FROND) + Vector2(float(st[e]), 1.0 - t)) / ATLAS, o)
		for s in segs:
			var i := base + s * 2
			idx.append_array([i, i + 2, i + 1, i + 1, i + 2, i + 3])


## Small closed blob (octahedron, 8 triangles) of radius r: coconuts.
func blob(c0: Vector3, r: float, col: Color) -> void:
	var base := v.size()
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		vert(c0 + d * r, d, Color(col.r, col.g, col.b, 0.0), Vector2.ZERO, c0)
	for f in [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [0, 4, 3], [4, 1, 3], [1, 5, 3], [5, 0, 3]]:
		idx.append_array([base + f[0], base + f[1], base + f[2]])


## Unit mesh: x and z divided by the crown aspect (normals and anchors too; MultiMesh instances transform normals
## with the instance matrix, so this keeps them right once the instance scales the tree back out).
func mesh(aspect: float) -> ArrayMesh:
	var sq := Vector3(1.0 / aspect, 1.0, 1.0 / aspect)
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := cu.duplicate()
	for k in v.size():
		vv.append(v[k] * sq)
		nn.append((n[k] * sq).normalized())
		cc[k * 4] *= sq.x
		cc[k * 4 + 2] *= sq.z
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vv
	arrays[Mesh.ARRAY_NORMAL] = nn
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_CUSTOM0] = cc
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return m
