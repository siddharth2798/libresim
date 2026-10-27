class_name TreeSpecies
extends RefCounted
## Which tree stands in a land cell, and how big. Deterministic, and shared by the billboards
## (TreeSampler.build), the LOD0 meshes (TreeLod) and the collision discs (Trees._tree_cell), so
## what is drawn is what is hit. Region and elevation steer the mix: coconut palms on the Konkan
## and Kerala coast and in the lowlands, umbrella acacias on the dry Deccan plateau, slim
## casuarina / eucalyptus near the sea, broadleaf (mango, neem, banyan) everywhere else.

enum { BROADLEAF, PALM, ACACIA, SLIM }
const COUNT := 4
const VARIANTS := 4  # sprites per species in the impostor atlas (TreeAtlas)
const MAX_HEIGHT := 22.0  # tallest tree of any species
## Width of the billboard / crown as a fraction of the height, per species (the atlas draws its
## sprites for these proportions).
const ASPECT := [0.70, 0.66, 1.35, 0.27]


## Probability of a palm at north offset n (ENU m from 18.75 N) and ground height g (m AMSL).
static func palm_p(n: float, g: float) -> float:
	var region := lerpf(0.10, 0.40, smoothstep(0.0, -150000.0, n))  # Mumbai: some; Konkan: many
	region = lerpf(region, 0.45, smoothstep(-400000.0, -600000.0, n))  # Kerala: groves everywhere
	var upland := 1.0 - smoothstep(25.0, 160.0 if n > -400000.0 else 320.0, g)
	return region * upland


static func of(ci: int, cj: int, n: float, g: float) -> int:
	var r := TreeSampler.hash3(ci, cj, 11)
	var palm := palm_p(n, g)
	if r < palm:
		return PALM
	r -= palm
	var acacia := 0.22 if g > 400.0 else 0.05
	if r < acacia:
		return ACACIA
	r -= acacia
	if r < (0.10 if g < 30.0 else 0.03):
		return SLIM
	return BROADLEAF


## [species, variant, height m, crown width m] of the tree cell_tree() placed in cell (ci, cj) at
## north n on ground g.
static func shape(ci: int, cj: int, n: float, g: float) -> PackedFloat32Array:
	var sp := of(ci, cj, n, g)
	var u := TreeSampler.hash3(ci, cj, 4)
	var v := TreeSampler.hash3(ci, cj, 5)
	var h: float
	var w: float
	match sp:
		PALM:
			h = lerpf(9.0, 16.0, u)
			w = lerpf(8.0, 11.0, v)
		ACACIA:
			h = lerpf(5.0, 10.0, u)
			w = h * lerpf(1.1, 1.6, v)
		SLIM:
			h = lerpf(12.0, 22.0, u)
			w = h * lerpf(0.22, 0.32, v)
		_:
			h = lerpf(6.0, 15.0, u)
			w = h * lerpf(0.55, 0.85, v)
	return PackedFloat32Array([sp, int(TreeSampler.hash3(ci, cj, 12) * VARIANTS) % VARIANTS, h, w])


## Radius of the collision disc and its top, as a fraction of the height.
static func hit_radius(sp: int, w: float) -> float:
	return w * (0.2 if sp == PALM else 0.4)


static func hit_top(sp: int, h: float) -> float:
	return h * (1.0 if sp == PALM else 0.9)
