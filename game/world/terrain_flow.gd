class_name TerrainFlow
extends RefCounted
## What the terrain does to the wind at the aircraft, for Weather (heights from a Callable (east, north) -> m):
## - Ridge lift / lee sink: the full kinematic w = U . grad(h) at the surface (slope over +-RIDGE_E m), decaying with
##   height on the ridge scale RIDGE_L (about 1.5 km), clamped to -5..+6 m/s.
## - Mechanical turbulence over steep ground (decays over MECH_L).
## - Lee waves (linear, trapped-wave picture): every drop of the terrain upwind (profile along the wind aloft, every
##   WAVE_STEP m out to WAVE_REACH) sends waves downwind, w = -0.3 N drop cos(2 pi d / lambda) x envelope, wavelength
##   lambda = 2 pi U / N (about 6-20 km for 10-30 m/s and N = 0.01 /s); the first crest about half a wavelength downwind,
##   fading over four wavelengths and above about 6 km AGL. Ascents send waves of the opposite sign, so a narrow ridge
##   mostly cancels and one about half a wavelength wide resonates. Only with the cross-ridge wind above ~6 m/s
##   (full by 12), weaker on a convective day (a stable layer is assumed: weather/wave_stability, N, default 0.01 /s).
## - Rotor: 0..1 under the first wave crest (about 0.4 wavelength downwind of a big drop), below about 1 km AGL; Weather
##   turns it into strong turbulence.
## The wave field is worked out every WAVE_EVERY s and blended linearly between updates, so it is smooth along the
## flight path and the same for the same path.

const RIDGE_E := 500.0
const RIDGE_L := 1500.0
const MECH_L := 400.0
const WAVE_STEP := 1000.0
const WAVE_REACH := 40000.0
const WAVE_EVERY := 0.2
const WAVE_N := 0.01
const ROTOR_DROP := 600.0  # m of lee drop for a full-strength rotor

var lift := 0.0  # m/s, + up
var mech := 0.0  # m/s of extra turbulence sigma
var wave := 0.0  # m/s, + up
var rotor := 0.0  # 0..1
var _from := Vector2.ZERO  # (wave, rotor) at the last update ...
var _to := Vector2.ZERO  # ... and the newest
var _timer := 0.0


static func ridge_lift(wind_en: Vector2, grad: Vector2, agl: float) -> float:
	return clampf(wind_en.dot(grad) * exp(-maxf(agl, 0.0) / RIDGE_L), -5.0, 6.0)


static func wavelength(u: float, n := WAVE_N) -> float:
	return TAU * u / n


## Lee wave (x: m/s, + up) and rotor (y: 0..1) from an upwind terrain profile (profile[k] = height k * step upwind of the
## aircraft), wind u along the profile, cross-ridge share cosine (0..1), stability n, agl.
static func lee_wave(profile: PackedFloat64Array, step: float, u: float, cosine: float, n: float, agl: float) -> Vector2:
	var gate := smoothstep(6.0, 12.0, u * cosine)
	if gate <= 0.0 or agl <= 0.0:
		return Vector2.ZERO
	var lam := wavelength(u, n)
	var w := 0.0
	var rot := 0.0
	for k in profile.size() - 1:
		var drop := profile[k + 1] - profile[k]  # the ground falls this much going downwind
		var d := (k + 0.5) * step
		var env := smoothstep(0.2 * lam, 0.6 * lam, d) * exp(-d / (4.0 * lam))
		w -= 0.3 * n * drop * cos(TAU * d / lam) * env
		if drop > 0.0:
			rot += drop * exp(-pow((d - 0.4 * lam) / (0.2 * lam), 2.0))
	var vz := smoothstep(0.0, 300.0, agl) * (1.0 - smoothstep(4000.0, 8000.0, agl))
	var r := clampf(rot / ROTOR_DROP, 0.0, 1.0) * smoothstep(0.0, 50.0, agl) * (1.0 - smoothstep(400.0, 1200.0, agl))
	return Vector2(clampf(w * gate * vz, -5.0, 5.0), r * gate)


## Every physics tick. height: (east, north) -> m; pos ENU; wind_en: wind at the aircraft (east, north); aloft_en: the wind
## the waves ride on (east, north); conv: 0..1 convective heating (weakens the waves).
func update(dt: float, height: Callable, pos: Vector3, agl: float, wind_en: Vector2, aloft_en: Vector2, conv := 0.0) -> void:
	var e := RIDGE_E
	var grad := Vector2(height.call(pos.x + e, pos.y) - height.call(pos.x - e, pos.y),
		height.call(pos.x, pos.y + e) - height.call(pos.x, pos.y - e)) / (2.0 * e)
	lift = ridge_lift(wind_en, grad, agl)
	mech = (absf(lift) * 0.5 + wind_en.length() * grad.length() * 0.6) * exp(-maxf(agl, 0.0) / MECH_L)
	_timer -= dt
	if _timer <= 0.0:
		_timer = WAVE_EVERY
		_from = _to
		_to = _wave_at(height, pos, agl, aloft_en, conv)
	var k := 1.0 - clampf(_timer / WAVE_EVERY, 0.0, 1.0)
	var v := _from.lerp(_to, k)
	wave = v.x
	rotor = v.y


func _wave_at(height: Callable, pos: Vector3, agl: float, aloft_en: Vector2, conv: float) -> Vector2:
	var u := aloft_en.length()
	if u < 6.0:
		return Vector2.ZERO
	var up := -aloft_en / u  # toward where the wind comes from
	var n := Props.get_f("weather/wave_stability", WAVE_N)
	var prof := PackedFloat64Array()
	var steps := int(WAVE_REACH / WAVE_STEP)
	prof.resize(steps + 1)
	var big := 0
	for k in steps + 1:
		prof[k] = height.call(pos.x + up.x * k * WAVE_STEP, pos.y + up.y * k * WAVE_STEP)
		if k > 0 and absf(prof[k] - prof[k - 1]) > absf(prof[big] - prof[maxi(big - 1, 0)]):
			big = k
	# cross-ridge share at the biggest drop: its slope along the wind against the slope across it
	var c := Vector2(pos.x, pos.y) + up * (big - 0.5) * WAVE_STEP
	var side := Vector2(-up.y, up.x) * WAVE_STEP
	var along := absf(prof[big] - prof[maxi(big - 1, 0)])
	var across := absf(height.call(c.x + side.x, c.y + side.y) - height.call(c.x - side.x, c.y - side.y)) * 0.5
	var cosine := along / maxf(sqrt(along * along + across * across), 1e-3)
	var r := lee_wave(prof, WAVE_STEP, u, cosine, n, agl)
	return r * (1.0 - 0.6 * clampf(conv, 0.0, 1.0))
