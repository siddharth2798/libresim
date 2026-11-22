class_name TreeMeshes
extends RefCounted
## Procedural near tree meshes, one per species and LOD (TreeLod draws them within the preset's lod radius, TreeAtlas
## bakes the impostors from LOD1). Unit size: x and z in crown widths, y in tree heights, origin at the trunk foot.
## Crowns are clumps of alpha-tested leaf cards (TreeParts) with gaps between the clumps, on a trunk with limbs, so sky
## shows through and the branches are seen; palms are a bare ringed trunk with a head of drooping fronds.
## LOD1 = trunk, main limbs and the big cards of every clump. LOD0 adds smaller detail cards and twigs (CUSTOM0.w = 1),
## which tree_mesh.gdshader shrinks away towards TreeLod's detail radius, where the cell switches to LOD1.
## Triangle budget: LOD0 <= MAX_TRIS[0], LOD1 <= MAX_TRIS[1] per tree (tests/test_tree_look.gd).

const BARK := Color(0.15, 0.115, 0.085)
const LEAF := [Color(0.10, 0.17, 0.05), Color(0.075, 0.15, 0.035), Color(0.13, 0.16, 0.07), Color(0.10, 0.15, 0.08), Color(0.06, 0.14, 0.04)]
const MAX_TRIS := [900, 360]

static var _cache := {}  # Vector2i(species, lod) -> ArrayMesh


## Cached: the meshes are deterministic.
static func get_mesh(sp: int, lod: int) -> ArrayMesh:
	var k := Vector2i(sp, lod)
	if not _cache.has(k):
		_cache[k] = build(sp, lod)
	return _cache[k]


static func build(sp: int, lod := 0) -> ArrayMesh:
	var b := TreeParts.new(1000 + sp)
	var a: float = TreeSpecies.ASPECT[sp]
	match sp:
		TreeSpecies.PALM:
			_palm(b, lod, a)
		TreeSpecies.ACACIA:
			_acacia(b, lod, a)
		TreeSpecies.SLIM:
			_slim(b, lod, a)
		TreeSpecies.SPREAD:
			_spread(b, lod, a)
		_:
			_forest(b, lod, a)
	return b.mesh(a)


static func triangle_count(m: ArrayMesh) -> int:
	return m.surface_get_array_index_len(0) / 3


## Clumps: [centre, radius] in the canonical frame. Each gets a limb from the trunk (LOD1: only `main` of them) and
## its cards: `big` large ones in both LODs, `small` detail ones in LOD0 only.
static func _crown(b: TreeParts, lod: int, clumps: Array, trunk_top: Vector3, limb_r: float, main: int, big: int,
		small: int, cell: Vector2i, col: Color, cc: Vector3, cr: Vector3, up_bias := 0.0, hang := false) -> void:
	for k in clumps.size():
		var cen: Vector3 = clumps[k][0]
		var rad: Vector3 = clumps[k][1]
		var foot := trunk_top.lerp(Vector3(0.0, cen.y * 0.75, 0.0), 0.3 + 0.1 * (k % 3))
		b.detail = k >= main
		if lod == 0 or k < main:
			b.tube([foot, foot.lerp(cen, 0.5) + Vector3(0, 0.02, 0), foot.lerp(cen, 0.85)], [limb_r, limb_r * 0.7, limb_r * 0.4], 5 if lod == 0 else 4, BARK)
		b.detail = false
		var size := maxf(rad.x, rad.y) * 1.5
		b.cards(cen, rad, big, size, cell, col, cc, cr, up_bias, hang)
		if lod == 0:  # own random sequence, so the big cards of the next clumps are the same in both LODs
			var st := b.rng.state
			b.rng.seed = 7919 * (k + 1)
			b.detail = true
			b.cards(cen, rad * 1.05, small, size * 0.42, cell, col, cc, cr, up_bias, hang)
			b.detail = false
			b.rng.state = st


## Ring of n clumps around the axis at radius ring, height y, clump radius r (jittered).
static func _ring(b: TreeParts, n: int, ring: float, y: float, r: Vector3, phase := 0.0) -> Array:
	var out := []
	for k in n:
		var ang := TAU * (k + phase) / n + b.rng.randf_range(-0.25, 0.25)
		var cen := Vector3(cos(ang) * ring, y + b.rng.randf_range(-0.04, 0.04), sin(ang) * ring)
		out.append([cen, r * b.rng.randf_range(0.85, 1.15)])
	return out


## Teak / semi-evergreen forest tree: straight trunk to mid height, irregular tall crown of 7 clumps.
static func _forest(b: TreeParts, lod: int, a: float) -> void:
	var top := Vector3(0.008, 0.46, 0.0)
	b.tube([Vector3.ZERO, Vector3(0.01, 0.22, 0.0), top], [0.024, 0.018, 0.013], 7 if lod == 0 else 5, BARK)
	var cc := Vector3(0, 0.67, 0)
	var cr := Vector3(a * 0.5, 0.33, a * 0.5)
	var clumps := [[Vector3(0.0, 0.86, 0.01), Vector3(0.13, 0.1, 0.13)]]
	clumps.append_array(_ring(b, 4, a * 0.26, 0.7, Vector3(0.14, 0.11, 0.14)))
	clumps.append_array(_ring(b, 3, a * 0.24, 0.52, Vector3(0.12, 0.09, 0.12), 0.5))
	_crown(b, lod, clumps, top, 0.009, 4, 7, 16, TreeParts.CELL_LARGE, LEAF[0], cc, cr)


## Mango / banyan / peepal: short thick trunk, heavy limbs spreading out, a wide low dome of 9 clumps.
static func _spread(b: TreeParts, lod: int, a: float) -> void:
	var top := Vector3(0.0, 0.3, 0.0)
	b.tube([Vector3.ZERO, Vector3(0.01, 0.15, 0.0), top], [0.04, 0.032, 0.026], 7 if lod == 0 else 5, BARK)
	var cc := Vector3(0, 0.6, 0)
	var cr := Vector3(a * 0.5, 0.36, a * 0.5)
	var clumps := [[Vector3(0.0, 0.8, 0.0), Vector3(0.2, 0.13, 0.2)]]
	clumps.append_array(_ring(b, 5, a * 0.32, 0.58, Vector3(0.17, 0.13, 0.17)))
	clumps.append_array(_ring(b, 3, a * 0.13, 0.72, Vector3(0.15, 0.12, 0.15), 0.5))
	_crown(b, lod, clumps, top, 0.016, 5, 7, 14, TreeParts.CELL_BROAD, LEAF[4], cc, cr)


## Babul / khair scrub: short forked trunk, a flat open umbrella of thin feathery clumps.
static func _acacia(b: TreeParts, lod: int, a: float) -> void:
	var top := Vector3(0.0, 0.36, 0.0)
	b.tube([Vector3.ZERO, Vector3(0.02, 0.2, 0.0), top], [0.03, 0.025, 0.021], 6 if lod == 0 else 4, BARK)
	var cc := Vector3(0, 0.72, 0)
	var cr := Vector3(a * 0.5, 0.18, a * 0.5)
	var clumps := [[Vector3(0.0, 0.78, 0.0), Vector3(0.22, 0.06, 0.22)]]
	clumps.append_array(_ring(b, 5, a * 0.3, 0.7, Vector3(0.2, 0.06, 0.2)))
	_crown(b, lod, clumps, top, 0.014, 6, 5, 10, TreeParts.CELL_FINE, LEAF[2], cc, cr, 0.6)


## Casuarina / eucalyptus: tall thin trunk, wispy drooping needle strands hung in loose tiers up to a narrow top.
static func _slim(b: TreeParts, lod: int, a: float) -> void:
	var top := Vector3(0.0, 0.95, 0.0)
	b.tube([Vector3.ZERO, Vector3(0.006, 0.45, 0.0), top], [0.028, 0.018, 0.006], 6 if lod == 0 else 4, BARK)
	var cc := Vector3(0, 0.66, 0)
	var cr := Vector3(a * 0.5, 0.34, a * 0.5)
	var clumps := []
	for k in 8:
		var y := lerpf(0.36, 0.93, k / 7.0)
		var r := a * lerpf(0.4, 0.16, k / 7.0)
		var ang := k * 2.4
		clumps.append([Vector3(cos(ang) * a * 0.12, y, sin(ang) * a * 0.12), Vector3(r, 0.06, r)])
	_crown(b, lod, clumps, Vector3(0.0, 0.35, 0.0), 0.006, 0, 4, 5, TreeParts.CELL_NEEDLE, LEAF[3], cc, cr, 0.0, true)


## Coconut palm: slender ringed grey-brown trunk curving out from the foot; a head of long narrow fronds, young ones up,
## old ones hanging, the oldest dead and yellow-brown below the rest; a cluster of coconuts under the crown.
static func _palm(b: TreeParts, lod: int, _a: float) -> void:
	var top := Vector3(0.075, 0.86, 0.03)
	var pts := []
	var radii := []
	var segs := 8 if lod == 0 else 4
	for k in segs + 1:
		var t := float(k) / segs
		pts.append(Vector3(top.x * pow(t, 2.0), top.y * t, top.z * pow(t, 2.0)))
		radii.append(lerpf(0.0135, 0.0095, t) + 0.009 * maxf(0.0, 1.0 - t * 9.0))
	b.tube(pts, radii, 6 if lod == 0 else 5, Color(0.2, 0.17, 0.13), true)
	b.tube([top + Vector3(0, -0.03, 0), top + Vector3(0, 0.01, 0)], [0.016, 0.012], 5, Color(0.16, 0.17, 0.09))  # crown shaft
	for k in 7:  # coconuts, hanging under the frond bases
		var ang := TAU * k / 7.0
		b.blob(top + Vector3(cos(ang) * 0.022, -0.04 - 0.012 * (k % 2), sin(ang) * 0.022), 0.012, Color(0.2, 0.16, 0.05))
	for k in 20:  # LOD1: the first 14; LOD0 adds 6 (detail) and folds every frond into a V
		if lod > 0 and k >= 14:
			break
		var ang := TAU * (k * 0.618034 + 0.05 * sin(k * 2.7))
		var age := fmod(k * 0.381966 + 0.1, 1.0)  # 0 young (up), 1 old (hanging)
		var dead := age > 0.9  # two per palm (one also in LOD1 and the impostor)
		var dir := Vector3(cos(ang), 0, sin(ang))
		b.detail = k >= 14
		b.frond(top + Vector3(0, -0.01 if dead else 0.0, 0), dir, 0.46 * lerpf(0.85, 1.05, 0.5 + 0.5 * sin(k * 1.9)),
			0.1 if dead else lerpf(1.1, 0.3, age), 1.7 if dead else lerpf(0.55, 1.2, age), 0.13,
			Color(0.17, 0.13, 0.075) if dead else LEAF[1], 6 if lod == 0 else 4, lod == 0)
		b.detail = false
