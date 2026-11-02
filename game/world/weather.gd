class_name Weather
extends Node
## Offline weather. Settings live in Props "weather/*" (UI edits them):
##   wind_dir_deg (from, true), wind_kt (surface, 10 m), aloft_dir_deg, aloft_kt (above ~1500 m AGL),
##   gust_kt (peak), turbulence (0..1), visibility_m, cloud_base_ft (AMSL), cloud_cover (0..1),
##   qnh_hpa, temp_c (sea level), precip (rain 0..1; drawn by WeatherFx),
##   convection (thermals 0..1), storms (microburst cells 0..1, monsoon-like weather only).
## Each physics tick publishes environment/wind_ned (incl. gusts, Dryden-style
## turbulence, terrain-induced ridge lift / lee sink and the cloud physics of
## world/cloud_physics.gd: thermals, cloud / storm turbulence, microburst winds), qnh_pa, delta_t.

const DEFAULTS := {
	"wind_dir_deg": 270.0, "wind_kt": 8.0, "aloft_dir_deg": 280.0, "aloft_kt": 15.0,
	"gust_kt": 0.0, "turbulence": 0.15, "visibility_m": 20000.0,
	"cloud_base_ft": 4500.0, "cloud_cover": 0.3, "qnh_hpa": 1012.0, "temp_c": 30.0, "precip": 0.0,
	"convection": 0.0, "storms": 0.0,  # off unless set (old setups and saves behave as before)
}
const Z0 := 0.15  # surface roughness (m)
const TURB_L := 250.0  # turbulence length scale (m)

var terrain: TerrainQuadtree
var cloud := CloudPhysics.new()  # clouds as physics at the aircraft (thermals, cloud / storm turbulence, microbursts)
var _turb := Vector3.ZERO
var _gust := 0.0
var _gust_target := 0.0
var _gust_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for k in DEFAULTS:
		if not Props.has("weather/" + k):
			Props.set_v("weather/" + k, DEFAULTS[k])


static func _from_dir_to_ned(from_deg: float, speed: float) -> Vector3:
	var a := deg_to_rad(from_deg)
	return Vector3(-cos(a), -sin(a), 0.0) * speed  # air moves toward (from + 180)


func wind_at(agl: float) -> Vector3:
	var w := Props.get_f("weather/wind_kt") * Units.KT
	var wa := Props.get_f("weather/aloft_kt") * Units.KT
	var h := maxf(agl, 1.0)
	var surf := w * clampf(log(h / Z0) / log(10.0 / Z0), 0.0, 1.6)
	var t := clampf((agl - 300.0) / 1200.0, 0.0, 1.0)
	var d := lerp_angle(deg_to_rad(Props.get_f("weather/wind_dir_deg")), deg_to_rad(Props.get_f("weather/aloft_dir_deg")), t)
	return _from_dir_to_ned(rad_to_deg(d), lerpf(surf, maxf(wa, surf), t))


func _physics_process(dt: float) -> void:
	Props.set_v("environment/qnh_pa", Props.get_f("weather/qnh_hpa", 1013.25) * 100.0)
	Props.set_v("environment/delta_t", Props.get_f("weather/temp_c", 15.0) - 15.0)
	var pos: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var agl := Props.get_f("fdm/agl_m", 100.0)
	var tas := maxf(Props.get_f("fdm/tas_mps"), 5.0)
	var wind := wind_at(agl)
	# gusts: random ramps toward a gust peak along the mean wind
	var gust_peak := maxf(Props.get_f("weather/gust_kt") - Props.get_f("weather/wind_kt"), 0.0) * Units.KT
	_gust_timer -= dt
	if _gust_timer <= 0.0:
		_gust_timer = _rng.randf_range(3.0, 12.0)
		_gust_target = _rng.randf_range(0.3, 1.0) * gust_peak if _rng.randf() < 0.6 else 0.0
	_gust = lerpf(_gust, _gust_target, clampf(dt * 0.8, 0.0, 1.0))
	if wind.length() > 0.1:
		wind += wind.normalized() * _gust
	# ridge lift / lee sink from the terrain slope under the aircraft
	var lift := 0.0
	var mech := 0.0
	if terrain and agl < 1500.0:
		var e := 250.0  # slope over the ridge scale, not individual cliffs
		var gx := (terrain.height_at(pos.x + e, pos.y) - terrain.height_at(pos.x - e, pos.y)) / (2.0 * e)
		var gy := (terrain.height_at(pos.x, pos.y + e) - terrain.height_at(pos.x, pos.y - e)) / (2.0 * e)
		var w_en := Vector2(wind.y, wind.x)  # (east, north)
		var decay := exp(-maxf(agl, 0.0) / 400.0)
		lift = clampf(w_en.dot(Vector2(gx, gy)) * 0.5 * decay, -4.0, 6.0)  # m/s, windward up / lee down
		mech = absf(lift) * 0.5 + w_en.length() * Vector2(gx, gy).length() * decay * 0.6
	# Dryden-like turbulence: first-order filtered noise, scale grows near the ground
	var intensity := Props.get_f("weather/turbulence")
	var cx := cloud.update(dt, pos, agl, terrain)
	var sigma: float = intensity * cx.turb_scale * (1.0 + wind.length() * 0.15) * (1.4 if agl < 300.0 else 1.0) + mech * 0.3
	sigma = maxf(sigma, cx.turb_floor)  # a storm core shakes whatever the slider says
	var tau := TURB_L / tas
	var k := sqrt(2.0 * dt / tau)
	_turb.x += -_turb.x * dt / tau + sigma * k * _rng.randfn()
	_turb.y += -_turb.y * dt / tau + sigma * k * _rng.randfn()
	_turb.z += -_turb.z * dt / tau + sigma * 0.7 * k * _rng.randfn()
	var w: Vector3 = wind + _turb + Vector3(0.0, 0.0, -lift) + cx.wind  # + thermal / storm outflow and downdraft
	if agl < 2.0:
		w.z = 0.0
	Props.set_v("environment/wind_ned", w)
	Props.set_v("environment/ridge_lift_mps", lift)
