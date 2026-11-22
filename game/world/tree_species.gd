class_name TreeSpecies
extends RefCounted
## Which tree stands in a land cell, and how big. Deterministic, and shared by the impostors (TreeSampler.build), the
## near meshes (TreeLod) and the collision discs (Trees._tree_cell), so what is drawn is what is hit.
## Five kinds, picked from the region (north offset), the ground height and the ESA WorldCover class of the cell
## (tools/19_worldcover.py codes, 0 = unknown):
##   BROADLEAF  forest broadleaf: teak, ain, jamun and the semi-evergreen Ghat forest (WorldCover tree cover, uplands)
##   PALM       coconut palm: Konkan and Kerala lowlands, most of all around villages and paddies
##   ACACIA     dry scrub: babul / khair acacia on the Deccan plateau, shrubland and bare laterite
##   SLIM       casuarina on the coast, eucalyptus plantations inland (few)
##   SPREAD     wide village and town trees: mango, banyan, peepal, rain tree (built-up and farmland)
## Heights come in families so a tree keeps its height whatever the WorldCover data says: BROADLEAF and SPREAD share
## one range and the same random draw, so only palms, scrub and slim trees can differ in height from the old 4-kind mix.

enum { BROADLEAF, PALM, ACACIA, SLIM, SPREAD }
const COUNT := 5
const VARIANTS := 4  # shape picks packed into custom.g (species * VARIANTS + variant)
const MAX_HEIGHT := 22.0  # tallest tree of any species
## Width of the crown as a fraction of the height, per species (mean of shape(); the impostors are baked at this).
const ASPECT := [0.70, 0.66, 1.35, 0.27, 1.12]
## WorldCover codes (tools/19_worldcover.py)
const WC_TREE := 1
const WC_SHRUB := 2
const WC_GRASS := 3
const WC_CROP := 4
const WC_BUILT := 5
const WC_BARE := 6
const WC_MANGROVE := 10


## Probability of a palm at north offset n (ENU m from 18.75 N), ground height g (m AMSL), WorldCover class wc.
static func palm_p(n: float, g: float, wc := 0) -> float:
	var region := lerpf(0.10, 0.40, smoothstep(0.0, -150000.0, n))  # Mumbai: some; Konkan: many
	region = lerpf(region, 0.45, smoothstep(-400000.0, -600000.0, n))  # Kerala: groves everywhere
	var upland := 1.0 - smoothstep(25.0, 160.0 if n > -400000.0 else 320.0, g)
	var k := 1.0
	match wc:
		WC_BUILT, WC_CROP:
			k = 1.4  # coconut gardens round houses and along paddy bunds
		WC_TREE:
			k = 0.85
		WC_SHRUB, WC_GRASS, WC_BARE:
			k = 0.5  # open laterite plateau
		WC_MANGROVE:
			k = 0.0
	return minf(region * upland * k, 0.75)


## Share of scrub acacia among the trees that are not palms.
static func acacia_p(g: float, wc: int) -> float:
	var p := 0.22 if g > 400.0 else 0.05
	match wc:
		WC_SHRUB, WC_BARE:
			p = minf(p * 2.5 + 0.15, 0.7)
		WC_GRASS:
			p = minf(p * 1.6 + 0.05, 0.5)
		WC_TREE:
			p *= 0.4
		WC_BUILT:
			p *= 0.5
		WC_MANGROVE:
			p = 0.0
	return p


## Share of wide village trees (mango, banyan, peepal) among the remaining broadleaf trees.
static func spread_p(g: float, wc: int) -> float:
	match wc:
		WC_BUILT:
			return 0.75
		WC_CROP:
			return 0.7
		WC_GRASS:
			return 0.55
		WC_SHRUB, WC_BARE:
			return 0.4
		WC_TREE:
			return 0.22 if g < 150.0 else 0.08  # Konkan orchards and village groves; the Ghats are forest
		WC_MANGROVE:
			return 0.0
	return 0.35


static func of(ci: int, cj: int, n: float, g: float, wc := 0) -> int:
	var r := TreeSampler.hash3(ci, cj, 11)
	var palm := palm_p(n, g, wc)
	if r < palm:
		return PALM
	r -= palm
	var acacia := acacia_p(g, wc) * (1.0 - palm)
	if r < acacia:
		return ACACIA
	r -= acacia
	if r < (0.10 if g < 30.0 else 0.03) * (0.0 if wc == WC_MANGROVE else 1.0):
		return SLIM
	return SPREAD if TreeSampler.hash3(ci, cj, 13) < spread_p(g, wc) else BROADLEAF


## [species, variant, height m, crown width m] of the tree cell_tree() placed in cell (ci, cj) at north n on ground g
## with WorldCover class wc.
static func shape(ci: int, cj: int, n: float, g: float, wc := 0) -> PackedFloat32Array:
	var sp := of(ci, cj, n, g, wc)
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
		SPREAD:
			h = lerpf(6.0, 15.0, u)
			w = h * lerpf(0.9, 1.35, v)
		_:
			h = lerpf(6.0, 15.0, u)
			w = h * lerpf(0.55, 0.85, v)
	return PackedFloat32Array([sp, int(TreeSampler.hash3(ci, cj, 12) * VARIANTS) % VARIANTS, h, w])


## Radius of the collision disc and its top, as a fraction of the height.
static func hit_radius(sp: int, w: float) -> float:
	return w * (0.2 if sp == PALM else (0.3 if sp == SPREAD else 0.4))


static func hit_top(sp: int, h: float) -> float:
	return h * (1.0 if sp == PALM else 0.9)
