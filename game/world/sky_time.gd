class_name SkyTime
extends Node
## Time of day: sun position for the region (lat 18.75 N, lon 73.4 E, IST = UTC+5:30),
## light colour/energy, sky colours, haze and the visibility fog.
## Props: weather/time_h (local IST hours, default 10.0), weather/day_of_year (default 45),
##        weather/time_rate (1 = real time, 0 = frozen).
## Publishes environment/sun_elev_deg and the global shader params haze_density / fog_color.

const LAT := 18.75
const LON := 73.4

@export var sun_path: NodePath
@export var env_path: NodePath

var _sun: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial  # world/sky_clouds.gdshader
var _drift := Vector2.ZERO


func _ready() -> void:
	_sun = get_node(sun_path)
	_env = (get_node(env_path) as WorldEnvironment).environment
	_sky = _env.sky.sky_material
	if not Props.has("weather/time_h"):
		Props.set_v("weather/time_h", 10.0)
		Props.set_v("weather/day_of_year", 45.0)
		Props.set_v("weather/time_rate", 1.0)
	# haze_density / fog_color are declared in project.godot [shader_globals]


## Returns Vector2(elevation, azimuth) in radians (azimuth from north, clockwise).
static func sun_position(hours_ist: float, day: float) -> Vector2:
	var decl := deg_to_rad(-23.44) * cos(TAU / 365.0 * (day + 10.0))
	var b := TAU / 365.0 * (day - 81.0)
	var eot := 9.87 * sin(2.0 * b) - 7.53 * cos(b) - 1.5 * sin(b)  # minutes
	var solar := hours_ist + (4.0 * (LON - 82.5) + eot) / 60.0  # IST meridian 82.5 E
	var ha := deg_to_rad(15.0 * (solar - 12.0))
	var lat := deg_to_rad(LAT)
	var el := asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha))
	var az := atan2(sin(ha), cos(ha) * sin(lat) - tan(decl) * cos(lat)) + PI
	return Vector2(el, az)


func _process(dt: float) -> void:
	var t := fposmod(Props.get_f("weather/time_h") + dt * Props.get_f("weather/time_rate") / 3600.0, 24.0)
	Props.set_v("weather/time_h", t)
	var sp := sun_position(t, Props.get_f("weather/day_of_year", 45.0))
	var el := sp.x
	Props.set_v("environment/sun_elev_deg", rad_to_deg(el))
	# light points FROM the sun: render frame x = east, z = south
	var d := Vector3(sin(sp.y) * cos(el), sin(el), -cos(sp.y) * cos(el))
	if d.length() > 0.01:
		_sun.look_at_from_position(Vector3.ZERO, -d, Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD)
	var el_deg := rad_to_deg(el)
	var day := clampf((el_deg + 6.0) / 14.0, 0.0, 1.0)  # civil twilight -> full day at +8 deg
	var dusk := clampf(1.0 - absf(el_deg - 1.0) / 10.0, 0.0, 1.0)
	_sun.light_energy = 1.3 * clampf((el_deg + 1.0) / 12.0, 0.0, 1.0)
	_sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.55, 0.3), dusk)
	var night_top := Color(0.01, 0.015, 0.04)
	var night_hor := Color(0.03, 0.04, 0.07)
	var top := night_top.lerp(Color(0.25, 0.45, 0.85), day)
	_sky.set_shader_parameter("zenith_color", top)
	_sky.set_shader_parameter("day", day)
	_sky.set_shader_parameter("dusk", dusk)
	RenderingServer.global_shader_parameter_set("sky_top_color", top)
	var hor := night_hor.lerp(Color(0.7, 0.78, 0.88), day).lerp(Color(0.95, 0.6, 0.4), dusk * 0.6 * day)
	_sky.set_shader_parameter("horizon_color", hor)
	_sky.set_shader_parameter("ground_color", hor * 0.4)
	_env.ambient_light_energy = lerpf(0.06, 0.7, day)
	# visibility -> haze (Koschmieder: extinction = 3.9 / visibility)
	var vis := maxf(Props.get_f("weather/visibility_m", 20000.0), 200.0)
	var haze := 1.5 / vis
	RenderingServer.global_shader_parameter_set("haze_density", haze)
	RenderingServer.global_shader_parameter_set("fog_color", hor)
	_env.fog_enabled = vis < 15000.0
	_env.fog_light_color = hor
	_env.fog_density = haze * 0.6
	_env.fog_sky_affect = 0.3
	_update_clouds(dt)  # last: in-cloud fog overrides the visibility fog


## Feed the volumetric cloud pass (CloudLayer on the camera) and detect flying inside a cloud.
func _update_clouds(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var layer := cam.get_node_or_null("CloudLayer") as CloudLayer
	if layer == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	var wind: Vector3 = Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	_drift -= Vector2(wind.y, wind.x) * dt  # field moves with the wind
	var day: float = _sky.get_shader_parameter("day")
	var sun_col := _sun.light_color * clampf(_sun.light_energy, 0.15, 1.2)
	var amb := Color(0.5, 0.56, 0.66).lerp(Color(0.05, 0.06, 0.09), 1.0 - day)
	layer.update_layer(w, Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0)), Props.get_f("weather/cloud_cover"),
		_drift, _sun.global_transform.basis.z, sun_col, amb)
	var d := layer.density_at(w)
	Props.set_v("environment/in_cloud", d > 0.05)
	if d > 0.05:
		_env.fog_enabled = true
		_env.fog_density = lerpf(0.002, 0.03, clampf(d * 2.0, 0.0, 1.0))
		_env.fog_light_color = Color(0.85, 0.87, 0.9) * maxf(day, 0.1)
