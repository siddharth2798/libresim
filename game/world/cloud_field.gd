class_name CloudField
extends RefCounted
## Cloud geometry and density at an ENU position for the AIRCRAFT (the visual pass in
## volumetric_clouds.gdshader / CloudLayer works relative to the camera). Pure functions, no nodes.
## The density is a CPU copy of the shader's density(): the same noise (FastNoiseLite with CloudLayer's
## parameters, same seamless 256 px image as its NoiseTexture2D), bilinear like the GPU sampler, the same
## base / thickness (WeatherFx.CLOUD_THICK) / cover / drift, so the cloud the aircraft meets is the cloud
## on screen. Also: which cloud type the conditions make, and the turbulence multiplier it implies.

const THICK := WeatherFx.CLOUD_THICK  # m, as the shader's cloud_thick
const TILE_M := 9000.0  # one noise tile, as the shader
const CU_DEPTH := 2500.0  # m, physics depth of cumulus (towers above the drawn layer)
const CB_TOP_M := 11000.0  # m AMSL, physics top of cumulonimbus
const NEAR_M := 300.0  # edge zone: turbulence ramps up this far from a cloud
const IN_CLOUD := 0.05  # density above which the aircraft counts as in cloud (as SkyTime)
const CLEAR := "clear"
const STRATIFORM := "stratiform"
const CUMULUS := "cumulus"
const CUMULONIMBUS := "cumulonimbus"
## Dryden sigma multiplier inside a cloud of each kind (clear air = 1).
const IN_MULT := {"clear": 1.5, "stratiform": 1.5, "cumulus": 2.2, "cumulonimbus": 2.5}
## Least vertical sigma (m/s) inside a cloud of each kind, whatever the Turbulence setting: convective cloud is never smooth.
const IN_FLOOR := {"clear": 0.0, "stratiform": 0.3, "cumulus": 1.2, "cumulonimbus": 3.0}
const _DIRS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]

static var _lo: Image
static var _hi: Image


static func _image(freq: float, octaves: int, seed: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = freq
	n.fractal_octaves = octaves
	return n.get_seamless_image(256, 256, false, false, 0.1, true)  # NoiseTexture2D's defaults


## Coverage (low frequency, ~3 km features) and detail noise, 0..1 at tile coordinates uv.
static func lo(uv: Vector2) -> float:
	if _lo == null:
		_lo = _image(0.012, 4, 1)
	return _bilinear(_lo, uv)


static func hi(uv: Vector2) -> float:
	if _hi == null:
		_hi = _image(0.03, 3, 2)
	return _bilinear(_hi, uv)


static func _bilinear(img: Image, uv: Vector2) -> float:
	var w := img.get_width()
	var x := uv.x * w - 0.5
	var y := uv.y * w - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var xa := posmod(x0, w)
	var xb := posmod(x0 + 1, w)
	var ya := posmod(y0, w)
	var yb := posmod(y0 + 1, w)
	return lerpf(lerpf(img.get_pixel(xa, ya).r, img.get_pixel(xb, ya).r, fx),
		lerpf(img.get_pixel(xa, yb).r, img.get_pixel(xb, yb).r, fx), fy)


## Physics depth (m) of a cloud kind: the drawn 900 m layer for stratiform and clear-sky wisps; cumulus towers to
## CU_DEPTH and cumulonimbus to CB_TOP_M AMSL over the strongest cores (density_deep). The visual pass keeps the 900 m slab.
static func depth_m(base_m: float, kind_name := "") -> float:
	if kind_name == CUMULONIMBUS:
		return maxf(CB_TOP_M - base_m, THICK)
	return CU_DEPTH if kind_name == CUMULUS else THICK


static func top_m(base_m: float, kind_name := "") -> float:
	return base_m + depth_m(base_m, kind_name)


## Density with the towers: the drawn layer as density(), and above its top, for cumulus and cumulonimbus, the columns
## that are still cloud at the layer top, thinning out over the last 40 % to the kind's top. Continuous at the layer top.
static func density_deep(p: Vector3, base_m: float, cover: float, drift: Vector2, kind_name := "") -> float:
	var slab_top := base_m + THICK
	if p.z < slab_top:
		return density(p, base_m, cover, drift)
	var top := top_m(base_m, kind_name)
	if p.z >= top or top <= slab_top + 1.0:
		return 0.0
	var col := density(Vector3(p.x, p.y, slab_top - 0.01), base_m, cover, drift)
	return col * (1.0 - smoothstep(0.6, 1.0, (p.z - slab_top) / (top - slab_top)))


## Cloud density 0..1 at ENU p (east, north, up AMSL), zero below the base and above the top.
static func density(p: Vector3, base_m: float, cover: float, drift: Vector2) -> float:
	var h := (p.z - base_m) / THICK
	if h < 0.0 or h > 1.0 or cover <= 0.0:
		return 0.0
	var q := (Vector2(p.x, p.y) + drift) / TILE_M
	var cov := lo(q) - (1.0 - cover) * 0.82
	var dome := cov * 2.6 - h * h * 1.1 - (1.0 - smoothstep(0.0, 0.1, h)) * 0.4
	var detail := hi(q * 6.0 + Vector2(h * 0.35, -h * 0.27))
	return clampf((dome - (1.0 - detail) * 0.32) * 2.2, 0.0, 1.0)


## 0..1: how close the nearest cloud is (1 = in it, ~0.7 at 150 m, ~0.4 at 300 m, 0 beyond), looked for
## sideways and straight up / down. Only worth calling when p is not in cloud itself.
static func proximity(p: Vector3, base_m: float, cover: float, drift: Vector2, kind_name := "") -> float:
	if cover <= 0.0:
		return 0.0
	var best := 0.0
	for r in [NEAR_M * 0.5, NEAR_M]:
		var k: float = 1.0 - 0.6 * r / NEAR_M
		for dir in _DIRS:
			best = maxf(best, minf(density_deep(p + dir * r, base_m, cover, drift, kind_name) * 3.0, 1.0) * k)
	return best


## The cloud type the conditions make (a property of the weather, not of the spot): clear, stratiform
## (overcast, drizzle, stable), cumulus (fair-weather / scattered / broken by day with convection) or
## cumulonimbus (monsoon-like: heavy cover and rain with convection or storms set).
static func kind(cover: float, precip: float, convection: float, storms: float, sun_elev_deg: float, turbulence := 0.0) -> String:
	if cover < 0.1:
		return CLEAR
	if cover >= 0.9 and precip >= 0.6 and (convection >= 0.4 or storms >= 0.3):
		return CUMULONIMBUS
	var day := sun_elev_deg > 5.0
	if cover >= 0.85 and not (convection >= 0.6 and turbulence >= 0.7 and day):
		return STRATIFORM  # a high, even deck with little convection
	if convection >= 0.3 and day:
		return CUMULUS
	return STRATIFORM


## Turbulence multiplier below a convective base (0..0.4, for cumulus / cumulonimbus by day).
static func under_base(alt_m: float, base_m: float, kind_name: String, convection_heat: float) -> float:
	if kind_name != CUMULUS and kind_name != CUMULONIMBUS:
		return 0.0
	return 0.4 * convection_heat * smoothstep(base_m - 800.0, base_m - 100.0, alt_m) * (1.0 - smoothstep(base_m + THICK, base_m + THICK + 300.0, alt_m))


## Multiplier for the Dryden sigma: 1 in clear air, up to IN_MULT[kind] inside the cloud (full by
## density 0.35), a gentle half-way ramp within NEAR_M of one, and `under` more below a convective base.
static func turbulence_scale(kind_name: String, dens: float, near: float, under: float) -> float:
	var m: float = IN_MULT.get(kind_name, 1.5)
	var s := lerpf(1.0, m, smoothstep(0.0, 0.35, dens))
	s = maxf(s, 1.0 + (m - 1.0) * 0.5 * near)
	return s * (1.0 + under)


## Turbulence floor (m/s, vertical sigma) at cloud density dens: IN_FLOOR[kind] inside (full by density 0.35), half of it
## within NEAR_M of a cloud.
static func turbulence_floor(kind_name: String, dens: float, near: float) -> float:
	var f: float = IN_FLOOR.get(kind_name, 0.0)
	return f * maxf(smoothstep(0.0, 0.35, dens), 0.5 * near)
