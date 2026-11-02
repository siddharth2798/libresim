class_name CloudConvection
extends RefCounted
## Thermals and the sink between them. Pure functions. Conditions `c` (Dictionary, built by
## CloudPhysics.conditions): cover, base_m, kind, drift (Vector2, cloud advection), land (0..1 surface
## heating factor), heat (0..1 = convection setting x daytime sun x cloud shade x warmth).
## Horizontal structure is the cloud coverage noise (cells of 1-3 km, advected with the cloud field), so
## updrafts sit under and inside the cumulus the aircraft sees; vertical profile peaks mid boundary layer.

const MAX_UP := 5.0  # m/s
const CEILING_AGL := 4000.0  # nothing above this height


## 0..1 sun heating: none below ~2 deg elevation (night), full from ~40 deg.
static func heating(sun_elev_deg: float) -> float:
	return smoothstep(2.0, 40.0, sun_elev_deg)


## Surface heating factor from the land class (255 water, 0 other = bare / urban / crops, 1..200 trees,
## -1 = tile still loading).
static func land_factor(landclass: int) -> float:
	if landclass == 255:
		return 0.15  # water: weak
	if landclass < 0:
		return 0.8
	if landclass == 0:
		return 1.0
	return 0.8 - 0.1 * clampf(landclass / 200.0, 0.0, 1.0)  # forest: cooler, moister


## Height profile of the updraft (0..1): strongest in the middle of the boundary layer (depth zi, = the
## cloud base under cumulus), still 0.65 under the base, held up to the cloud top zt for cumulus and
## decaying above it (a clear-air thermal fades just above zi). All heights AGL.
static func profile_up(agl: float, zi: float, zt: float, cumulus: bool) -> float:
	var z := agl / maxf(zi, 1.0)
	var p: float
	if agl <= zi:
		p = smoothstep(0.0, 0.2, z) * (0.65 + 0.35 * sin(PI * z))
	else:
		p = 0.65 * (1.0 - smoothstep(zt, zt + (500.0 if cumulus else 300.0), agl))
	return p * smoothstep(0.0, 50.0, agl) * (1.0 - smoothstep(CEILING_AGL - 500.0, CEILING_AGL, agl))


## Vertical wind (m/s, + up) at ENU p, agl m above ground, for conditions c; dens = cloud density at p.
static func thermal(p: Vector3, agl: float, c: Dictionary, dens: float) -> float:
	var k: float = float(c.heat) * float(c.land)
	if k <= 0.001 or agl <= 0.0 or agl >= CEILING_AGL or float(c.convection) <= 0.0:
		return 0.0
	k *= float(c.convection)
	var cover: float = c.cover
	var kind_name: String = c.kind
	var cumulus := kind_name == CloudField.CUMULUS or kind_name == CloudField.CUMULONIMBUS
	var ground := p.z - agl
	var zi := clampf(float(c.base_m) - ground, 300.0, 3500.0) if cover > 0.05 else 700.0 + 1500.0 * minf(k, 1.0)
	var zt := (CloudField.top_m(float(c.base_m)) - ground) if cumulus and cover > 0.05 else zi
	zt = maxf(zt, zi)
	# horizontal cell structure
	var q := (Vector2(p.x, p.y) + (c.drift as Vector2)) / CloudField.TILE_M
	var s := CloudField.lo(q) * 0.85 + CloudField.hi(q * 6.0) * 0.15
	var thr := clampf(0.15 + (1.0 - cover) * 0.82 - 0.12, 0.55, 0.68)  # clouds sit on the strongest cores
	var up := smoothstep(thr - 0.05, thr + 0.08, s)
	var down := 1.0 - smoothstep(thr - 0.2, thr - 0.04, s)
	var strength := k * (2.0 + 2.5 * (clampf(cover * 1.5, 0.0, 1.0) if cumulus else 0.0))
	var w := up * strength * profile_up(agl, zi, zt, cumulus) * (1.0 + 0.25 * dens)
	var z := agl / zi
	var sink := (0.3 + 0.7 * minf(k, 1.0)) * smoothstep(0.0, 0.15, z) * (1.0 - smoothstep(0.9, 1.2, z))
	w -= down * sink * (1.0 - dens) * (1.0 - up)
	return clampf(w, -1.5, MAX_UP)
