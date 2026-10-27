class_name SkyTime
extends Node
## Time of day: sun position for the region (lat 18.75 N, lon 73.4 E, IST = UTC+5:30),
## light colour/energy, sky colours, haze and the visibility fog.
## Props: weather/time_h (local IST hours, default 10.0), weather/day_of_year (default 45),
##        weather/time_rate (1 = real time, 0 = frozen).
## Publishes environment/sun_elev_deg, light_level, visibility_m and the global shader params
## haze_density / fog_color / sky_top_color. Cloud cover dims and diffuses the sun and greys the
## sky (world/weather_visuals.gd); rain, wet ground and lightning live in the WeatherFx child.

const LAT := 18.75
const LON := 73.4

@export var sun_path: NodePath
@export var env_path: NodePath

var _sun: DirectionalLight3D
var _env: Environment
var _adapt := 0.0  # 0..1 how far the eye has adapted to the sun being in view
var _sky: ShaderMaterial  # world/sky_clouds.gdshader
var _drift := Vector2.ZERO
var _night: NightSky
var auto_exposure := true  # graphics preset (off on Low): world/auto_exposure.gd
var _ae := AutoExposure.new()
var _atmo_key := Vector3(INF, 0.0, 0.0)
var _atmo_cache: Array = [Color.BLACK, Color.BLACK]  # zenith, horizon (linear)


func _ready() -> void:
	_sun = get_node(sun_path)
	_env = (get_node(env_path) as WorldEnvironment).environment
	_sky = _env.sky.sky_material
	if not Props.has("weather/time_h"):
		Props.set_v("weather/time_h", 10.0)
		Props.set_v("weather/day_of_year", 45.0)
		Props.set_v("weather/time_rate", 1.0)
	# haze_density / fog_color are declared in project.godot [shader_globals]
	var fx := WeatherFx.new()
	fx.name = "WeatherFx"
	add_child(fx)
	_night = NightSky.new()
	_night.name = "NightSky"
	add_child(_night)


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
	day = maxf(day, 0.12 * clampf((el_deg + 12.0) / 6.0, 0.0, 1.0))  # nautical twilight glow
	var dusk := clampf(1.0 - absf(el_deg - 1.0) / 10.0, 0.0, 1.0)
	# cloud deck: dims and diffuses the sun below the layer top
	var cover := Props.get_f("weather/cloud_cover")
	var base_m := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0))
	var cam := get_viewport().get_camera_3d()
	var cam_alt := FloatingOrigin.to_world(cam.global_position).z if cam else 0.0
	var top_m := base_m + WeatherFx.CLOUD_THICK
	var occl := WeatherVisuals.sun_occlusion(cover, 1.0 - smoothstep(top_m - 150.0, top_m + 150.0, cam_alt))
	var rain := Props.get_f("environment/precip")
	var ls := WeatherVisuals.light_scales(occl, rain)
	var flash := Props.get_f("environment/lightning")
	_sun.light_energy = 1.3 * clampf((el_deg + 1.0) / 12.0, 0.0, 1.0) * ls.sun
	_sun.shadow_opacity = ls.shadow
	var rain_vis := WeatherVisuals.rain_visibility(maxf(Props.get_f("weather/visibility_m", 20000.0), 200.0), rain)
	_sun.light_color = Atmosphere.sun_color(el_deg).lerp(Color(1.0, 0.95, 0.88), occl)
	# clear-sky colours from the analytic atmosphere (zenith, and the horizon towards where the camera
	# looks): the fog / haze below uses the same horizon colour, so ground and sky agree at every hour
	var atmo := _atmosphere(d, el_deg, rain_vis)
	var night_top := Color(0.01, 0.015, 0.04).srgb_to_linear()
	var night_hor := Color(0.03, 0.04, 0.07).srgb_to_linear()
	var night_w := 1.0 - day
	var m_top: Color = atmo[0]
	var m_hor: Color = atmo[1]
	var top := Color(night_top.r * night_w + m_top.r, night_top.g * night_w + m_top.g, night_top.b * night_w + m_top.b).linear_to_srgb()
	var hor := Color(night_hor.r * night_w + m_hor.r, night_hor.g * night_w + m_hor.g, night_hor.b * night_w + m_hor.b).linear_to_srgb()
	var sky: Array = WeatherVisuals.overcast_sky(top, hor, day, occl, ls.dark)
	_night.update_night(t, Props.get_f("weather/day_of_year", 45.0), 1.0 - day, occl, d, _env, _sky)
	sky = _night.night_colors(sky[0], sky[1], 1.0 - day, occl)
	var fl := Color(0.75, 0.78, 0.9) * flash * occl
	top = sky[0] + fl * 0.6
	hor = sky[1] + fl
	_sky.set_shader_parameter("zenith_color", top)
	_sky.set_shader_parameter("model_top", m_top.linear_to_srgb())
	_sky.set_shader_parameter("model_hor", m_hor.linear_to_srgb())
	_sky.set_shader_parameter("clear", 1.0 - smoothstep(0.0, 0.8, occl))
	_sky.set_shader_parameter("atmo_gain", Atmosphere.twilight_gain(el_deg))
	_sky.set_shader_parameter("aerosol", Atmosphere.aerosol_for_visibility(rain_vis))
	_sky.set_shader_parameter("day", day)
	_sky.set_shader_parameter("dusk", dusk * (1.0 - occl))
	_sky.set_shader_parameter("sun_vis", 1.0 - smoothstep(0.5, 0.9, occl))
	_sky.set_shader_parameter("cirrus", 0.6 * (1.0 - smoothstep(0.2, 0.7, occl)) * (1.0 - rain) * (1.0 - 0.4 * Props.get_f("weather/cloud_cover")))
	_sky.set_shader_parameter("cirrus_wind", _drift * 0.00004)
	RenderingServer.global_shader_parameter_set("sky_top_color", top)
	_sky.set_shader_parameter("horizon_color", hor)
	_sky.set_shader_parameter("ground_color", hor * 0.4)
	_env.ambient_light_energy = lerpf(0.5, 0.7, day) * ls.ambient + flash * 1.5 * occl  # night floor: NightSky
	Props.set_v("environment/light_level", maxf(day * ls.dark, 0.08 + 0.1 * _night.moon_light) + flash * occl)
	# visibility -> fog: extinction for a 5 % contrast threshold (about 3 / visibility), less in rain
	var vis := rain_vis
	Props.set_v("environment/visibility_m", vis)
	var haze := WeatherVisuals.fog_density(vis)
	RenderingServer.global_shader_parameter_set("haze_density", haze)
	RenderingServer.global_shader_parameter_set("fog_color", hor.srgb_to_linear())  # shaders add it as light
	_env.fog_enabled = true
	_env.fog_light_color = hor
	_env.fog_density = haze
	_env.fog_sky_affect = clampf(1.0 - (vis - 1500.0) / 8000.0, 0.0, 0.85)
	_update_clouds(dt, occl, rain, hor, day * ls.dark)  # last: in-cloud fog overrides the visibility fog
	_update_exposure(dt, d, el_deg, hor, top, 1.0 - day)
	_update_glare(dt, d, el_deg, occl, rain)


## Clear-sky zenith and horizon colours (linear) for the sun at `sun_dir`, cached until the sun, the
## haze or the camera heading (1 deg) change. The horizon is sampled at least 35 deg of azimuth away
## from the sun so the fog colour never blows out; the sky shader shows the full glow itself.
func _atmosphere(sun_dir: Vector3, el_deg: float, vis: float) -> Array:
	var az := atan2(sun_dir.x, -sun_dir.z)
	var look := az + PI
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		var f := -cam.global_transform.basis.z
		if Vector2(f.x, f.z).length() > 0.2:
			look = atan2(f.x, -f.z)
	var delta := wrapf(look - az, -PI, PI)
	delta = (1.0 if delta >= 0.0 else -1.0) * maxf(absf(delta), deg_to_rad(35.0))
	var a := az + delta
	var key := Vector3(roundf(el_deg * 20.0), roundf(rad_to_deg(a)), roundf(Atmosphere.aerosol_for_visibility(vis) * 10.0))
	if key != _atmo_key:
		_atmo_key = key
		var aer := Atmosphere.aerosol_for_visibility(vis)
		var gain := Atmosphere.twilight_gain(el_deg)
		var top := Atmosphere.sky(Vector3.UP, sun_dir, aer, gain)
		var hor := Atmosphere.sky(Vector3(sin(a), 0.01, -cos(a)), sun_dir, aer, gain)
		var lum := hor.get_luminance()
		if lum > 0.9:
			hor = Color(hor.r * 0.9 / lum, hor.g * 0.9 / lum, hor.b * 0.9 / lum)
		_atmo_cache = [top, hor]
	return _atmo_cache


## Feed the volumetric cloud pass (CloudLayer on the camera) and detect flying inside a cloud.
func _update_clouds(dt: float, occl: float, rain: float, hor: Color, light: float) -> void:
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
	var sun_col := _sun.light_color * clampf(_sun.light_energy, 0.15 * (1.0 - occl) + 0.02, 1.2)
	var light_dir := _sun.global_transform.basis.z
	if day < 0.3:  # night: clouds lit by the moon, undersides by the city glow
		var m := 1.0 - day / 0.3
		sun_col = sun_col.lerp(NightSky.MOON_COLOR * (0.03 + 0.3 * _night.moon_light), m)
		if _night.moon_dir.y > 0.0:
			light_dir = light_dir.lerp(_night.moon_dir, m).normalized()
	var amb := Color(0.5, 0.56, 0.66).lerp(Color(0.06, 0.07, 0.1) + NightSky.CITY_GLOW * 0.8, 1.0 - day).lerp(hor * 0.95, occl)
	layer.update_layer(w, Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0)), Props.get_f("weather/cloud_cover"),
		_drift, light_dir, sun_col, amb, occl * 0.5 + rain * 0.25)
	var d := layer.density_at(w)
	Props.set_v("environment/in_cloud", d > 0.05)
	if d > 0.05:
		_env.fog_enabled = true
		var inside := Color(0.8, 0.82, 0.86) * maxf(light, 0.04)
		_env.fog_density = lerpf(0.002, 0.03, clampf(d * 2.0, 0.0, 1.0))
		_env.fog_light_color = inside
		RenderingServer.global_shader_parameter_set("haze_density", _env.fog_density)
		RenderingServer.global_shader_parameter_set("fog_color", inside.srgb_to_linear())


## Eye-like auto exposure: scene brightness from the sun / sky / camera heading, shade under a cloud
## included (the CPU cloud density along the sun ray), smoothed by AutoExposure. Multiplies the exposure
## NightSky just set; Props environment/exposure_mult is published for the tests and the HUD.
func _update_exposure(dt: float, sun_dir: Vector3, el_deg: float, hor: Color, top: Color, night: float) -> void:
	var target := 1.0
	if auto_exposure:
		var cam := get_viewport().get_camera_3d()
		var pitch_sin := 0.0
		var blocked := 0.0
		if cam:
			pitch_sin = -cam.global_transform.basis.z.y
			blocked = _sun_blocked(cam, sun_dir)
		var sky_lum := 0.5 * (hor.srgb_to_linear().get_luminance() + top.srgb_to_linear().get_luminance())
		var moon := 0.15 * Props.get_f("environment/moon_light")
		var lum := AutoExposure.scene_luminance(_sun.light_energy, sun_dir.y, blocked, _env.ambient_light_energy + moon, sky_lum, pitch_sin)
		target = AutoExposure.target_for(lum * _env.tonemap_exposure, night)
	_env.tonemap_exposure *= _ae.step(dt, target)
	Props.set_v("environment/exposure_mult", _ae.value)


## 0..1: a cloud between the sun and the aircraft (the aircraft is under the layer, in its shadow).
func _sun_blocked(cam: Camera3D, sun_dir: Vector3) -> float:
	var layer := cam.get_node_or_null("CloudLayer") as CloudLayer
	if layer == null or not layer.visible or sun_dir.y < 0.05:
		return 0.0
	var w := FloatingOrigin.to_world(cam.global_position)
	if w.z > layer.base:
		return 0.0
	var sun_enu := Vector3(sun_dir.x, -sun_dir.z, sun_dir.y)
	var p := w + sun_enu * ((layer.base + WeatherFx.CLOUD_THICK * 0.4 - w.z) / sun_dir.y)
	return clampf(layer.density_at(p) * 2.0, 0.0, 1.0)


## Sun glare overlay and the eye's adaptation: looking towards a bright sun pulls the exposure down a little.
func _update_glare(dt: float, sun_dir: Vector3, el_deg: float, occl: float, rain: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var glare: SunGlare = cam.get_node_or_null("SunGlare") if cam else null
	var k := clampf((el_deg + 1.0) / 8.0, 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.8, occl)) * (1.0 - rain)
	var facing := 0.0
	if glare:
		var col := Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.6, 0.35), clampf(1.0 - absf(el_deg - 1.0) / 10.0, 0.0, 1.0))
		glare.update_glare(sun_dir.normalized(), col, k)
		facing = smoothstep(0.75, 0.99, (-cam.global_transform.basis.z).dot(sun_dir.normalized())) * k
	_adapt = lerpf(_adapt, facing, 1.0 - exp(-dt / 0.8))
	_env.tonemap_exposure *= 1.0 - 0.2 * _adapt
