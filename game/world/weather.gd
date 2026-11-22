class_name Weather
extends Node
## Offline weather. Settings live in Props "weather/*" (UI edits them):
##   wind_dir_deg (from, true), wind_kt (surface, 10 m), aloft_dir_deg, aloft_kt (blended in from ~50 m AGL,
##   and allowed to be lighter than the surface wind). weather/wind_table, when it has rows
##   [height AGL m, from deg, kt], replaces that blend above 10 m. The mean wind eases in over ~3 s;
##   gusts, thermals and storm cells are applied the same tick.
##   gust_kt (peak), turbulence (0..1), visibility_m, cloud_base_ft (AMSL), cloud_cover (0..1),
##   qnh_hpa, temp_c (sea level), precip (rain 0..1; drawn by WeatherFx),
##   convection (thermals 0..1), storms (microburst cells 0..1, monsoon-like weather only).
## Each physics tick publishes environment/wind_ned (incl. gusts and lulls around the set wind, MIL-F-8785C turbulence
## (world/turbulence.gd; its rotary gusts as environment/gust_pqr, sigma_w as environment/turbulence_sigma), the terrain
## (world/terrain_flow.gd: ridge lift / lee sink, lee waves, rotor turbulence), rain-shaft downdrafts and the cloud physics
## of world/cloud_physics.gd: thermals, cloud / storm turbulence, storm up- and downdrafts and outflow),
## environment/ac_precip (rain rate at the aircraft, the same field as the drawn rain), qnh_pa, delta_t.
## The vertical wind tapers to zero over the last 10 m above the wheels. Holds while paused or replaying (SimHold).

const DEFAULTS := {
	"wind_dir_deg": 270.0, "wind_kt": 8.0, "aloft_dir_deg": 280.0, "aloft_kt": 15.0,
	"gust_kt": 0.0, "turbulence": 0.15, "visibility_m": 20000.0,
	"cloud_base_ft": 4500.0, "cloud_cover": 0.3, "qnh_hpa": 1012.0, "temp_c": 30.0, "precip": 0.0,
	"convection": 0.0, "storms": 0.0,  # off unless set (old setups and saves behave as before)
}
const Z0 := 0.15  # surface roughness (m)
const GUST_SHARE := 0.4  # share of the gust periods that are gusts (0.3-1 x the peak); the rest are lulls ...
const LULL := [0.2, 0.667]  # ... of this share of the peak, so the mean wind stays the set wind
const GUST_FADE := [1000.0, 1500.0]  # m AGL: gusts and lulls fade out above the boundary layer
const W_TAPER_M := 10.0  # vertical wind fades to zero over this height above the wheels
const ROTOR_SIGMA := 3.0  # m/s, turbulence floor in a full-strength rotor

var terrain: TerrainQuadtree
var cloud := CloudPhysics.new()  # clouds as physics at the aircraft (thermals, cloud / storm turbulence, microbursts)
var turbulence := Turbulence.new()  # MIL-F-8785C filters (world/turbulence.gd)
var flow := TerrainFlow.new()  # ridge lift, lee waves, rotor (world/terrain_flow.gd)
var _turb := Vector3.ZERO  # its last output, NED
var _gust := 0.0
var _gust_target := 0.0
var _gust_timer := 0.0
var _mean := Vector3.ZERO
var _mean_set := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	turbulence.rng = _rng  # one noise stream: seeding _rng repeats the gusts and the turbulence
	for k in DEFAULTS:
		if not Props.has("weather/" + k):
			Props.set_v("weather/" + k, DEFAULTS[k])


static func _from_dir_to_ned(from_deg: float, speed: float) -> Vector3:
	var a := deg_to_rad(from_deg)
	return Vector3(-cos(a), -sin(a), 0.0) * speed  # air moves toward (from + 180)


func wind_at(agl: float) -> Vector3:
	var table := _wind_table()
	if table.is_empty():
		return _two_point(agl)
	return _from_table(agl, table)


func _two_point(agl: float) -> Vector3:
	var w := Props.get_f("weather/wind_kt") * Units.KT
	var wa := Props.get_f("weather/aloft_kt") * Units.KT
	var h := maxf(agl, 1.0)
	var surf := w * clampf(log(h / Z0) / log(10.0 / Z0), 0.0, 1.6)
	var t := clampf((agl - 50.0) / 1450.0, 0.0, 1.0)  # surface at 50 m, the aloft wind by ~1500 m, either way
	var d := lerp_angle(deg_to_rad(Props.get_f("weather/wind_dir_deg")), deg_to_rad(Props.get_f("weather/aloft_dir_deg")), t)
	return _from_dir_to_ned(rad_to_deg(d), lerpf(surf, wa, t))


func _wind_table() -> Array:
	var raw = Props.get_v("weather/wind_table", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return []
	var rows: Array = []
	for item in raw:
		if item is Array and (item as Array).size() >= 3:
			rows.append(item)
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return rows


## 10 m is the surface wind (the log law). Above that, blend to the next sample and hold the last one.
func _from_table(agl: float, table: Array) -> Vector3:
	var h := maxf(agl, 1.0)
	var dir0 := Props.get_f("weather/wind_dir_deg")
	var spd0 := Props.get_f("weather/wind_kt")
	var logk := clampf(log(h / Z0) / log(10.0 / Z0), 0.0, 1.6)
	if h <= 10.0:
		return _from_dir_to_ned(dir0, spd0 * logk * Units.KT)
	var prev_h := 10.0
	var prev_dir := dir0
	var prev_spd := spd0
	for row in table:
		var hh := float(row[0])
		var dd := float(row[1])
		var kk := float(row[2])
		if h <= hh:
			var t := clampf((h - prev_h) / maxf(hh - prev_h, 1.0), 0.0, 1.0)
			var spd_a := spd0 * logk if prev_h <= 10.0 else prev_spd
			var d := lerp_angle(deg_to_rad(prev_dir), deg_to_rad(dd), t)
			return _from_dir_to_ned(rad_to_deg(d), lerpf(spd_a, kk, t) * Units.KT)
		prev_h = hh
		prev_dir = dd
		prev_spd = kk
	return _from_dir_to_ned(prev_dir, prev_spd * Units.KT)


## The mean wind eases toward `target` over about 3 s. The first sample is the setting itself.
func _mean_wind(target: Vector3, dt: float) -> Vector3:
	if not _mean_set:
		_mean = target
		_mean_set = true
		return _mean
	_mean = _mean.lerp(target, 1.0 - exp(-dt / 3.0))
	return _mean


func _physics_process(dt: float) -> void:
	Props.set_v("environment/qnh_pa", Props.get_f("weather/qnh_hpa", 1013.25) * 100.0)
	Props.set_v("environment/delta_t", Props.get_f("weather/temp_c", 15.0) - 15.0)
	if SimHold.active():  # paused or replaying: the air holds (wind_ned keeps its last value)
		return
	var pos: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var agl := Props.get_f("fdm/agl_m", 100.0)
	var wind := _mean_wind(wind_at(agl), dt)
	if wind.length() > 0.1:
		wind += wind.normalized() * _gusts(dt, agl)
	# terrain: ridge lift / lee sink, mechanical turbulence, lee waves and rotor (world/terrain_flow.gd)
	if terrain:
		var aloft := wind_at(1500.0)
		var conv := Props.get_f("weather/convection") * CloudConvection.heating(Props.get_f("environment/sun_elev_deg", 45.0))
		flow.update(dt, terrain.height_at, pos, agl, Vector2(wind.y, wind.x), Vector2(aloft.y, aloft.x), conv)
	# turbulence: the setting is a MIL-F-8785C level (Turbulence.sigma_w); clouds multiply it and set a floor, terrain adds
	var cx := cloud.update(dt, pos, agl, terrain)
	var sigma: float = Turbulence.sigma_w(Props.get_f("weather/turbulence"), agl) * cx.turb_scale + flow.mech * 0.3
	sigma = maxf(sigma, maxf(cx.turb_floor, ROTOR_SIGMA * flow.rotor))  # cumulus, storm cores and rotors are never smooth
	_turb = turbulence.step(dt, agl, _air_speed(), sigma, wind, Props.get_f("fdm/heading_rad"), Props.get_f("fdm/wingspan_m"))
	var base_m := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0))
	var drift: Vector2 = Props.get_v("environment/cloud_drift", Vector2.ZERO)
	var rain := WeatherFx.local_rate(Props.get_f("weather/precip"), pos, base_m, Props.get_f("weather/cloud_cover"), drift)
	rain = minf(rain * (1.0 + 0.6 * float(cx.storm_intensity)), 1.0)
	var shaft := CloudConvection.rain_shaft(pos, agl, base_m, rain, cx.kind, drift)
	var w: Vector3 = wind + _turb + Vector3(0.0, 0.0, shaft - flow.lift - flow.wave) + cx.wind  # + thermal / storm winds
	var wheels := agl - Props.get_f("fdm/wheel_depth_m", 0.0)  # lowest wheel above the ground
	var taper := smoothstep(0.0, W_TAPER_M, wheels)  # no vertical wind through the ground; no step in the flare
	w.z *= taper
	Props.set_v("environment/wind_ned", w)
	Props.set_v("environment/gust_pqr", turbulence.pqr * taper)
	Props.set_v("environment/turbulence_sigma", sigma)
	Props.set_v("environment/ridge_lift_mps", flow.lift)
	Props.set_v("environment/lee_wave_mps", flow.wave)
	Props.set_v("environment/rotor", flow.rotor)
	Props.set_v("environment/rain_shaft_mps", shaft)
	Props.set_v("environment/ac_precip", rain)


## Gust (+) or lull (-) along the mean wind, m/s: ramps toward a new random target every 3-12 s. Gusts reach up to the
## set peak (gust_kt - wind_kt), lulls are a little shallower but longer-lived, so the mean is the set wind. Fades out
## above the boundary layer.
func _gusts(dt: float, agl: float) -> float:
	var peak := maxf(Props.get_f("weather/gust_kt") - Props.get_f("weather/wind_kt"), 0.0) * Units.KT
	_gust_timer -= dt
	if _gust_timer <= 0.0:
		_gust_timer = _rng.randf_range(3.0, 12.0)
		if _rng.randf() < GUST_SHARE:
			_gust_target = _rng.randf_range(0.3, 1.0) * peak
		else:
			_gust_target = -minf(_rng.randf_range(LULL[0], LULL[1]) * peak, 0.8 * Props.get_f("weather/wind_kt") * Units.KT)
	_gust = lerpf(_gust, _gust_target, 1.0 - exp(-0.8 * dt))
	return _gust * (1.0 - smoothstep(GUST_FADE[0], GUST_FADE[1], agl))


## Airspeed through the air mass without the turbulence (the turbulence filters' time constants; JSBSim does the same):
## the ground velocity against last tick's wind minus last tick's turbulence. Falls back to fdm/tas_mps.
func _air_speed() -> float:
	if not Props.has("fdm/track_rad"):
		return maxf(Props.get_f("fdm/tas_mps"), 5.0)
	var gs := Props.get_f("fdm/groundspeed_mps")
	var trk := Props.get_f("fdm/track_rad")
	var vg := Vector3(gs * cos(trk), gs * sin(trk), -Props.get_f("fdm/vs_mps"))
	var air: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO) - _turb
	return maxf((vg - air).length(), 5.0)
