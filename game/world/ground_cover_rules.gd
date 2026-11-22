class_name GroundCoverRules
extends RefCounted
## What grows on the ground at a grid point (GroundCover): one rule, deterministic per world grid point, from the
## ESA WorldCover class (tools/19; 0 = no data: nothing) and the land-class value (tools/11: tree density 1..200, used for
## "under canopy"; 255 water; 0 is both open grassland and roads, so roads come from GroundRoads instead). Kinds:
##   GRASS  tufts on grassland, farmland and wetland edges; dry straw-coloured tufts (dry = 1) on the plateau above
##          DRY_ABOVE_M, on shrubland and bare laterite
##   FERN   ferns and low understorey under forest canopy
##   SHRUB  small-leaved bushes (lantana, karvanda) under forest and on shrubland
## Nothing on water or without WorldCover data, nor where GroundCover's checks say road or river (GroundRoads) or paved
## (runway / taxiway ribbons and the apron mask, GroundSurface; TreeClear).

enum { GRASS, FERN, SHRUB }
const MESHES := 3
const NONE := Vector2i(-1, 0)
const DRY_ABOVE_M := 400.0
const FOREST_LC := 110  # land-class density above which the ground is under canopy
# WorldCover codes (tools/19_worldcover.py; as TreeSpecies.WC_*, repeated here because match patterns need local
# constants)
const WC_TREE := 1
const WC_SHRUB := 2
const WC_GRASS := 3
const WC_CROP := 4
const WC_BUILT := 5
const WC_BARE := 6
const WC_WATER := 8
const WC_WETLAND := 9
const WC_MANGROVE := 10
## Height (m) of a full-size tuft / fern / bush (the instance scale multiplies it by 0.6..1.2).
const SIZE := [0.55, 0.95, 1.25]


static func hash3(i: int, j: int, k: int) -> float:
	return TreeSampler.hash3(i, j, k)


## [mesh, dry] at grid point (i, j), or NONE. lc / wc / g: land class, WorldCover class, ground height (m).
static func pick(i: int, j: int, lc: int, wc: int, g: float) -> Vector2i:
	if lc < 0 or lc == 255 or wc <= 0 or wc == WC_WATER:
		return NONE
	var r := hash3(i, j, 21)
	var dry := 1 if g > DRY_ABOVE_M else 0
	if lc > FOREST_LC or wc == WC_TREE:
		if r < 0.38:
			return Vector2i(FERN, 0)
		return Vector2i(SHRUB, 0) if r < 0.52 else NONE
	match wc:
		WC_GRASS, WC_WETLAND:
			return Vector2i(GRASS, dry) if r < 0.6 else NONE
		WC_CROP:
			return Vector2i(GRASS, dry) if r < 0.45 else NONE
		WC_SHRUB:
			if r < 0.18:
				return Vector2i(SHRUB, 0)
			return Vector2i(GRASS, 1) if r < 0.45 else NONE
		WC_BARE:
			return Vector2i(GRASS, 1) if r < 0.22 else NONE
		WC_BUILT:
			return Vector2i(GRASS, dry) if r < 0.12 else NONE
		WC_MANGROVE:
			return Vector2i(SHRUB, 0) if r < 0.2 else NONE
	return NONE  # snow, moss: not in this region


## World position (east, north) of grid point (i, j) for grid step `step` (m): jittered within its square.
static func point(i: int, j: int, step: float) -> Vector2:
	return Vector2((i + 0.5 + (hash3(i, j, 22) - 0.5) * 0.9) * step, (j + 0.5 + (hash3(i, j, 23) - 0.5) * 0.9) * step)


## Instance height (m) of a kind at grid point (i, j); dry tufts are shorter.
static func height(i: int, j: int, kind: Vector2i) -> float:
	return float(SIZE[kind.x]) * lerpf(0.6, 1.2, hash3(i, j, 24)) * (0.7 if kind.y == 1 else 1.0)
