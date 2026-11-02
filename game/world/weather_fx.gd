class_name WeatherFx
extends Node
## Rain, wet surfaces and lightning. Created by SkyTime.
## Reads weather/precip (0..1 setting), weather/cloud_cover, weather/cloud_base_ft.
## Publishes environment/precip (local rain rate: showers, none above the cloud tops),
## environment/wetness (lags the rain), environment/lightning (0..1 flash), and the
## global shader params precip, wetness, rain_airspeed (windshield drops, wet terrain).

const CLOUD_THICK := 900.0  # m, as volumetric_clouds.gdshader
const WET_UP := 1.0 / 90.0  # wetness per second while it rains hard
const DRY := 1.0 / 900.0  # drying per second

var rain_max := 6000  # particles at full rain, set by the graphics preset
var _rain: RainParticles
var _t := 0.0
var _seed := 0.0
var _wet := -1.0
var _flash := 0.0
var _next_strike := 10.0
var _strike_t := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_seed = _rng.randf_range(0.0, 100.0)
	_rain = RainParticles.new()
	_rain.name = "Rain"
	_rain.max_count = rain_max
	add_child(_rain)


func set_rain_max(n: int) -> void:
	rain_max = n
	if _rain:
		_rain.set_max(n)


## Rain rate at altitude alt_m (AMSL) from the setting, time and cloud geometry.
static func local_rate(precip: float, t: float, seed: float, alt_m: float, base_m: float) -> float:
	var r := WeatherVisuals.shower_rate(precip, t, seed)
	return r * (1.0 - smoothstep(base_m + CLOUD_THICK * 0.6, base_m + CLOUD_THICK, alt_m))


func _process(dt: float) -> void:
	_t += dt
	var cam := get_viewport().get_camera_3d()
	var cam_w := FloatingOrigin.to_world(cam.global_position) if cam else Vector3(0, 0, 500)
	var base_m := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0))
	var precip := Props.get_f("weather/precip")
	var rain := local_rate(precip, _t, _seed, cam_w.z, base_m)
	rain = minf(rain * (1.0 + 0.6 * Props.get_f("environment/storm_intensity")), 1.0)  # heavier under a storm cell
	Props.set_v("environment/precip", rain)
	# wet ground lags the rain: starts wet if the weather was set rainy
	if _wet < 0.0:
		_wet = WeatherVisuals.wetness_target(precip)
	var target := WeatherVisuals.wetness_target(rain)
	_wet = move_toward(_wet, target, dt * (WET_UP * (0.3 + rain) if target > _wet else DRY))
	Props.set_v("environment/wetness", _wet)
	var ias := Props.get_f("fdm/ias_mps")
	RenderingServer.global_shader_parameter_set("precip", rain)
	RenderingServer.global_shader_parameter_set("wetness", _wet)
	RenderingServer.global_shader_parameter_set("rain_airspeed", ias)
	_lightning(dt, precip, Props.get_f("weather/cloud_cover"))
	if cam == null:
		return
	# rain velocity relative to the camera, render frame (x east, y up, z south)
	var w: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
	var v := Vector3.ZERO
	if cam is CameraRig and (cam as CameraRig).mode != CameraRig.Mode.FREE and (cam as CameraRig).aircraft:
		v = (cam as CameraRig).aircraft.fdm_node.fdm.velocity_ned()
	var rel_ned := Vector3(w.x - v.x, w.y - v.y, RainParticles.FALL * lerpf(0.75, 1.0, rain) - v.z)
	var rel := Vector3(rel_ned.y, -rel_ned.z, -rel_ned.x)
	var amb := Color(0.85, 0.87, 0.9) * clampf(Props.get_f("environment/light_level", 1.0) * 1.2, 0.05, 1.2)
	_rain.update_rain(rain, rel, amb, cam)
	var cockpit := cam is CameraRig and (cam as CameraRig).mode == CameraRig.Mode.COCKPIT
	(_rain.draw_pass_1.surface_get_material(0) as ShaderMaterial).set_shader_parameter("near_fade", 2.2 if cockpit else 1.2)


## Monsoon thunderstorms: occasional double/triple flickers lighting the cloud and the scene.
func _lightning(dt: float, precip: float, cover: float) -> void:
	_flash = maxf(_flash - dt * 9.0, 0.0)
	if precip < 0.6 or cover < 0.9:
		Props.set_v("environment/lightning", 0.0)
		return
	_next_strike -= dt
	if _next_strike <= 0.0:
		_next_strike = _rng.randf_range(12.0, 45.0)
		_strike_t = 0.0
	if _strike_t >= 0.0:
		_strike_t += dt
		for k in [0.0, 0.12, 0.3]:  # return strokes
			if _strike_t - dt < k and _strike_t >= k:
				_flash = _rng.randf_range(0.5, 1.0)
		if _strike_t > 0.4:
			_strike_t = -1.0
	Props.set_v("environment/lightning", _flash)
