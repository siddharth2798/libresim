class_name NightSky
extends Node3D
## Night look (child of SkyTime): the moon (position, phase, a cool directional light),
## stars and city sky-glow in the sky shader, a night ambient floor and a little more
## exposure, so terrain, coastline, water and clouds stay readable while still night.
## Publishes environment/moon_elev_deg and environment/moon_light (0..1).

const YEAR_JD := 2461041.5  # 2026-01-01 00:00 UTC (the sim's calendar year)
const NEW_MOON_JD := 2451550.26  # 2000-01-06 18:14 UTC
const SYNODIC := 29.530589
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const NIGHT_AMBIENT := Color(0.22, 0.27, 0.4)  # starlight + airglow + city spill, sRGB
const CITY_GLOW := Color(0.05, 0.042, 0.036)  # warm light pollution over Mumbai / Pune

var moon: DirectionalLight3D
var moon_dir := Vector3.UP  # render frame, towards the moon
var moon_light := 0.0  # 0..1 effective moonlight (phase x elevation x clouds)


func _ready() -> void:
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = MOON_COLOR
	moon.shadow_enabled = false  # moonlight is soft; no second shadow map
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # the sky shader draws the disc itself
	moon.light_energy = 0.0
	add_child(moon)


## Moon phase 0..1 (0 new, 0.5 full) at IST hours on day_of_year.
static func phase(hours_ist: float, day: float) -> float:
	var jd := YEAR_JD + (day - 1.0) + (hours_ist - 5.5) / 24.0
	return fposmod((jd - NEW_MOON_JD) / SYNODIC, 1.0)


## Illuminated fraction of the disc for a phase.
static func illumination(ph: float) -> float:
	return (1.0 - cos(ph * TAU)) * 0.5


## Moon (elevation, azimuth) in radians: the moon sits `phase` of a turn east of the sun
## along the ecliptic (orbit inclination ignored), so it rises ~50 min later each day.
static func moon_position(hours_ist: float, day: float) -> Vector2:
	var ph := phase(hours_ist, day)
	return SkyTime.sun_position(hours_ist - ph * 24.0, day + ph * 365.25)


static func to_render_dir(p: Vector2) -> Vector3:
	return Vector3(sin(p.y) * cos(p.x), sin(p.x), -cos(p.y) * cos(p.x))


## Called by SkyTime each frame. night: 0 day .. 1 full night; occl: cloud occlusion.
func update_night(hours: float, day_of_year: float, night: float, occl: float, sun_dir: Vector3,
		env: Environment, sky: ShaderMaterial) -> void:
	var mp := moon_position(hours, day_of_year)
	moon_dir = to_render_dir(mp)
	var k := illumination(phase(hours, day_of_year))
	var up := smoothstep(deg_to_rad(-1.0), deg_to_rad(12.0), mp.x)
	moon_light = clampf(k * up * night, 0.0, 1.0)
	Props.set_v("environment/moon_elev_deg", rad_to_deg(mp.x))
	Props.set_v("environment/moon_light", moon_light * (1.0 - occl))
	if moon_dir.y > -0.2:
		moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP if absf(moon_dir.y) < 0.99 else Vector3.FORWARD)
	moon.light_energy = 0.22 * moon_light * (1.0 - 0.85 * occl)
	moon.visible = moon.light_energy > 0.002
	sky.set_shader_parameter("moon_dir", moon_dir)
	sky.set_shader_parameter("moon_illum", k)
	sky.set_shader_parameter("moon_vis", night * (1.0 - smoothstep(0.4, 0.85, occl)) * smoothstep(-0.02, 0.02, moon_dir.y))
	sky.set_shader_parameter("sun_dir_u", sun_dir)
	sky.set_shader_parameter("stars", night * night * (1.0 - smoothstep(0.3, 0.8, occl)) * (1.0 - 0.5 * moon_light))
	# ambient: blend toward a fixed cool night floor as the sky radiance fades
	env.ambient_light_color = NIGHT_AMBIENT.lerp(MOON_COLOR * 0.5, moon_light * 0.5)
	env.ambient_light_sky_contribution = lerpf(1.0, 0.35, night)
	env.tonemap_exposure = lerpf(1.0, 1.45, night)


## Night additions to the sky colours (moonlit zenith, city glow on the horizon).
func night_colors(top: Color, hor: Color, night: float, occl: float) -> Array:
	var moonlit := Color(0.03, 0.045, 0.08) * moon_light * (1.0 - occl)
	var glow := CITY_GLOW * night * (1.0 + 0.5 * occl)  # a deck reflects the city back down
	return [top + moonlit + glow * 0.25, hor + moonlit * 0.6 + glow]
