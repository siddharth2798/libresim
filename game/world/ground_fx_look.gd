class_name GroundFxLook
extends RefCounted
## How each ground particle effect looks and moves (GroundEmitter kinds). Spray, wash and dust are soft, irregular mist
## wisps (GroundFxTextures.mist: one of four noise-shaped frames per particle, turned at random) that fade in, grow and
## fade out smoothly; the rooster tail is upright streaks stretched along the droplets' flight (a thin sheet, not balls).
## All are lit by the scene with a wrapped diffuse and no emission or specular: white-grey by day, grey at dusk, dark at
## night (nothing glows); they fade out close to the camera so nothing fills the cockpit or chase view, and on Forward+
## also where they meet the ground (proximity fade needs the depth texture). Fixed parts only: GroundFx / RainSplash
## set the source box, direction, speed and drift every frame.
##   splash  tiny crown of droplets where a raindrop hits, 0.3 s (world/rain_splash.gdshader: unshaded, tinted by the
##           daylight like WeatherFx's rain streaks, none where the aircraft shelters the ground)
##   spray   fine mist thrown up and out by a wheel: many small faint wisps near the tyre, spreading as they slow
##   tail    rooster tail: a thin fan of droplet streaks thrown up behind a main wheel at speed, falling back
##   wash    mist (or dust) blown back along the ground by a propeller or jet
##   dust    tan dust off dry grass or dirt

const WATER := Color(0.86, 0.88, 0.9)
const DUST := Color(0.72, 0.62, 0.48)
# kind: [lifetime s, scale min, max, alpha peak, gravity y, damping min, max, spread deg, reach m, texture, grow to]
const KINDS := {
	"splash": [0.3, 0.09, 0.2, 0.9, 0.0, 0.0, 0.0, 0.0, 25.0, "crown", 1.2],
	"spray": [1.4, 0.22, 0.45, 0.42, -4.0, 1.5, 3.0, 50.0, 10.0, "mist", 3.0],
	"tail": [1.1, 0.25, 0.5, 0.32, -9.8, 0.4, 0.8, 6.0, 15.0, "streak", 2.2],
	"wash": [2.2, 0.45, 0.9, 0.75, 0.25, 2.0, 3.5, 30.0, 15.0, "mist", 3.5],
	"dust": [3.2, 0.5, 1.0, 0.6, 0.25, 1.5, 2.5, 75.0, 12.0, "mist", 3.5],
}

static var _mats := {}


static func configure(e: GPUParticles3D, kind: String) -> void:
	var k: Array = KINDS.get(kind, KINDS.spray)
	var p: ParticleProcessMaterial = e.process_material
	e.lifetime = k[0]
	e.explosiveness = 0.0
	e.randomness = 0.5
	e.fixed_fps = 0
	e.interpolate = false
	e.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH if k[9] == "mist" else GPUParticles3D.DRAW_ORDER_INDEX
	if "reach" in e:
		e.reach = k[8]
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.2, 0.05, 0.3)
	p.direction = Vector3.UP
	p.spread = k[7]
	p.gravity = Vector3(0.0, k[4], 0.0)
	p.damping_min = k[5]
	p.damping_max = k[6]
	p.scale_min = k[1]
	p.scale_max = k[2]
	p.lifetime_randomness = 0.35
	var turn: bool = k[9] == "mist"  # wisps turn at random; crowns and streaks stand upright
	p.angle_min = -180.0 if turn else 0.0
	p.angle_max = 180.0 if turn else 0.0
	p.angular_velocity_min = -20.0 if turn else 0.0
	p.angular_velocity_max = 20.0 if turn else 0.0
	p.anim_offset_min = 0.0  # mist: a random frame of the 2 x 2 atlas per particle (anim_speed 0: it keeps it)
	p.anim_offset_max = 1.0 if turn else 0.0
	p.color = DUST if kind == "dust" else WATER
	p.color_ramp = _ramp(k[3], kind == "splash")
	p.scale_curve = _grow(kind == "splash", k[10])
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 1.0) if k[9] == "streak" else Vector2.ONE  # a streak is long along its flight
	q.material = material(k[9])
	e.draw_pass_1 = q


## Alpha over life: a smooth fade in, a long smooth thinning to exactly 0 (a splash is all over in a blink).
static func _ramp(peak: float, quick: bool) -> GradientTexture1D:
	var g := Gradient.new()
	if quick:
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, peak), Color(1, 1, 1, peak * 0.5), Color(1, 1, 1, 0.0)])
	else:
		g.offsets = PackedFloat32Array([0.0, 0.12, 0.3, 0.6, 0.85, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, peak * 0.85), Color(1, 1, 1, peak),
			Color(1, 1, 1, peak * 0.55), Color(1, 1, 1, peak * 0.15), Color(1, 1, 1, 0.0)])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Size over life: a splash opens quickly; spray, mist and dust start small at the source and spread to `to` x.
static func _grow(quick: bool, to: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = maxf(to, 1.5)
	if quick:
		c.add_point(Vector2(0.0, 0.35))
		c.add_point(Vector2(0.3, 1.0))
		c.add_point(Vector2(1.0, to))
	else:
		c.add_point(Vector2(0.0, 0.55))
		c.add_point(Vector2(0.2, 1.0))
		c.add_point(Vector2(1.0, to))
	var t := CurveTexture.new()
	t.curve = c
	return t


## Shared material of a sprite kind ("mist", "streak": lit StandardMaterial3D; "crown": the splash ShaderMaterial).
static func material(tex: String) -> Material:
	if _mats.has(tex):
		return _mats[tex]
	if tex == "crown":
		var s := ShaderMaterial.new()
		s.shader = preload("res://world/rain_splash.gdshader")
		s.set_shader_parameter("tex", GroundFxTextures.crown())
		_mats[tex] = s
		return s
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	if tex == "streak":  # upright, turning about its long axis to face the camera
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.albedo_texture = GroundFxTextures.streak()
	else:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
		m.albedo_texture = GroundFxTextures.mist()
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.8
	m.distance_fade_max_distance = 5.0
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		m.proximity_fade_enabled = true  # soft where the spray meets the ground
		m.proximity_fade_distance = 0.4
	_mats[tex] = m
	return m


## Daylight tint of the unshaded splash sprites (as WeatherFx tints the rain streaks): light_level 0..1.
static func splash_tint(light_level: float) -> void:
	material("crown").set_shader_parameter("tint", Color(0.85, 0.87, 0.9) * clampf(light_level * 1.2, 0.05, 1.2))


## Where the aircraft shelters the ground from rain (no splashes there): render position and nose direction (x, z),
## fuselage and wing boxes (centre along, half length, half width, top height above the reference point).
static func set_shelter(pos: Vector3, fwd: Vector2, body: Vector4, wing: Vector4) -> void:
	var s: ShaderMaterial = material("crown")
	s.set_shader_parameter("shelter_pos", pos)
	s.set_shader_parameter("shelter_fwd", fwd)
	s.set_shader_parameter("shelter_body", body)
	s.set_shader_parameter("shelter_wing", wing)
