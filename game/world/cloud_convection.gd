class_name CloudConvection
extends RefCounted
## Thermals and the sink between them. Pure functions. Conditions `c` (Dictionary, built by
## CloudPhysics.conditions): cover, base_m, kind, drift (Vector2, cloud advection), land (0..1 surface
## heating factor), heat (0..1 = convection setting x daytime sun x cloud shade x warmth).
## Horizontal structure is the cloud coverage noise (cells of 1-3 km, advected with the cloud field), so
## updrafts sit under and inside the cumulus the aircraft sees; vertical profile peaks mid boundary layer. The sink between
## the cells follows the same profile, scaled so the area-mean vertical wind is zero (world/thermal_balance.gd).

const MAX_UP := 5.0  # m/s
const MAX_DOWN := 3.0  # m/s, strongest sink between the cells
const RAIN_SHAFT := 5.0  # m/s, strongest rain-shaft downdraft (heavy rain)
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


## The horizontal cell field (0..1) at tile coordinates q: the cloud coverage noise plus a little detail.
static func cell_field(q: Vector2) -> float:
	return CloudField.lo(q) * 0.85 + CloudField.hi(q * 6.0) * 0.15


## Cell threshold for a cloud cover: the clouds sit on the strongest cores.
static func threshold(cover: float) -> float:
	return clampf(0.15 + (1.0 - cover) * 0.82 - 0.12, 0.55, 0.68)


## 0..1 updraft share of a point with cell field s.
static func up_share(s: float, thr: float) -> float:
	return smoothstep(thr - 0.05, thr + 0.08, s)


## 0..1 sink share of a point with cell field s: everywhere outside the cells (the descent spread wide and gentle).
static func down_share(s: float, thr: float) -> float:
	return 1.0 - up_share(s, thr)


## Vertical wind (m/s, + up) at ENU p, agl m above ground, for conditions c; dens = cloud density at p.
## Below the cloud the sink between the cells carries the same mass down as the updrafts carry up (ThermalBalance),
## so the area mean is zero: a long flight through thermals neither gains nor loses height on average.
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
	var zt := (CloudField.top_m(float(c.base_m), kind_name) - ground) if cumulus and cover > 0.05 else zi
	zt = maxf(zt, zi)
	var s := cell_field((Vector2(p.x, p.y) + (c.drift as Vector2)) / CloudField.TILE_M)
	var thr := threshold(cover)
	var strength := k * (2.0 + 2.5 * (clampf(cover * 1.5, 0.0, 1.0) if cumulus else 0.0))
	var lift := strength * profile_up(agl, zi, zt, cumulus)
	var w := lift * (up_share(s, thr) * (1.0 + 0.25 * dens) - ThermalBalance.sink_ratio(thr) * down_share(s, thr) * (1.0 - dens))
	return clampf(w, -MAX_DOWN, MAX_UP)


## Rain-shaft downdraft (m/s, + down) at ENU p under convective cloud: where the rain at p (0..1) is heavy, in patches
## about a kilometre across that drift with the cloud field, up to RAIN_SHAFT m/s, from the cloud base down to the
## ground (gone in the last ~150 m). None under stratiform rain.
static func rain_shaft(p: Vector3, agl: float, base_m: float, rain: float, kind_name: String, drift: Vector2) -> float:
	if rain < 0.4 or (kind_name != CloudField.CUMULUS and kind_name != CloudField.CUMULONIMBUS):
		return 0.0
	var q := (Vector2(p.x, p.y) + drift) / CloudField.TILE_M
	var patch := smoothstep(0.58, 0.7, CloudField.hi(q * 1.5 + Vector2(0.37, 0.61)))
	var prof := smoothstep(0.0, 150.0, agl) * (1.0 - smoothstep(base_m - 200.0, base_m + 300.0, p.z))
	return RAIN_SHAFT * smoothstep(0.4, 1.0, rain) * patch * prof
