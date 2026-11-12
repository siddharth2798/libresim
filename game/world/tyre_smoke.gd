class_name TyreSmoke
extends Node3D
## White touchdown tyre smoke, soft as a small cloud. Each wheel the runway spins up (TouchdownDetect) lays smoke
## along the short spin-up slide: the slide is cut into SEGMENTS pieces and each piece puffs (a one-shot burst
## from a box over that piece) once the wheel has rolled past it, checked every physics tick, so the smoke is
## only ever where the tyre has been and stays one even trail at any frame rate (an emitter dragged along with
## the wheel drops clumps a render frame apart). Once released a puff hardly moves over the ground, i.e. it
## streams back from the wheel at the aircraft's speed and slows to a stop; it rises a little, spreads as it
## drifts with the wind and thins from dense white to nothing over a few seconds (a smooth alpha ramp).
## Look: round soft puffs (bell-shaped alpha that is zero well inside the quad, a lumpy rim: no square edges),
## each turned at random and turning slowly, lit by the scene with a wrapped diffuse (white by day, grey at dusk,
## dark at night: it does not glow), sorted back to front. Forward+ also fades a puff where it meets the runway
## (proximity fade, needs the depth texture); every renderer fades a puff that comes close to the camera.
## aircraft.json "touchdown.legs" {<gear contact>: {width_m}} (optional): the width across all the tyres of a
## leg (a twin bogie throws a wider puff); default 0.2 m.

const SEGMENTS := 5
const POOL := 4 * SEGMENTS  # four wheels smoking at once
const LEG_W := 0.2  # m
const FOLLOW_S := 0.1  # s of slide at a light touch (+ up to FOLLOW_K more on a hard one)
const FOLLOW_K := 0.12

static var _tex: ImageTexture

var _sec := {}
var _pool: Array = []  # CPUParticles3D
var _i := 0
var _trails: Array = []  # slides being smoked: {wheel, start (ENU), track, seg m, fired, t, sh, k, width}
var wheel_enu: Callable = func(_w: String) -> Vector3: return Vector3.ZERO  # ENU of a wheel's contact now


## Puff shape for strength k 0..1, leg width (m) and ground speed (m/s): {amount (whole slide), lifetime s, size m,
## follow s (slide time), lift m (puff centres above the runway)}. A longer slide gets more puffs: one cloud.
static func shape(k: float, width: float, ground_speed := 28.0) -> Dictionary:
	var follow := FOLLOW_S + FOLLOW_K * k
	var size := (0.9 + 1.0 * width) * (0.8 + 0.6 * k)
	var n := (9.0 + 9.0 * k) * clampf(ground_speed * follow / 2.5, 1.0, 2.5)
	return {"amount": int(n), "lifetime": 3.0 + 2.0 * k, "size": size, "follow": follow, "lift": 0.05 + 0.15 * size}


## Alpha of a puff over its life (0 = born, 1 = gone): quick to dense, then a long smooth thinning to exactly 0.
static func alpha_at(life: float) -> float:
	return alpha_ramp().sample(clampf(life, 0.0, 1.0)).a


static func alpha_ramp() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.025, 0.2, 0.45, 0.7, 0.88, 1.0])  # dense within ~0.1 s, no pop
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.24), Color(1, 1, 1, 0.19), Color(1, 1, 1, 0.11),
		Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.012), Color(1, 1, 1, 0.0)])
	return g


func setup(sec: Dictionary, enu_of_wheel: Callable) -> void:
	_sec = sec
	wheel_enu = enu_of_wheel
	for i in POOL:
		var p := _make()
		add_child(p)
		_pool.append(p)


func leg_width(wheel: String) -> float:
	return float(_sec.get("legs", {}).get(wheel, {}).get("width_m", _sec.get("tyre_width_m", LEG_W)))


## A wheel touched down: smoke its slide (strength k 0..1, track rad from north, ground speed m/s).
func emit(wheel: String, k: float, track: float, ground_speed := 28.0) -> void:
	var w := leg_width(wheel)
	var sh := shape(k, w, ground_speed)
	_trails.append({"wheel": wheel, "start": wheel_enu.call(wheel), "track": track, "fired": 0, "t": 0.0, "sh": sh,
		"k": k, "width": w, "seg": maxf(ground_speed * sh.follow / SEGMENTS, 0.3)})
	_physics_process(0.0)  # the first piece puffs at once, on the contact patch


func _physics_process(dt: float) -> void:
	for tr in _trails.duplicate():
		tr.t += dt
		var fwd := Vector3(sin(tr.track), cos(tr.track), 0.0)
		var along: float = (wheel_enu.call(tr.wheel) - tr.start).dot(fwd)
		while tr.fired < SEGMENTS and (tr.fired == 0 or along >= tr.fired * tr.seg or tr.t > tr.sh.follow * 2.0):
			_fire(tr, fwd)
			tr.fired += 1
		if tr.fired >= SEGMENTS:
			_trails.erase(tr)


## One piece of the slide puffs: a short burst from a box over that piece (the first piece sits on the contact patch).
func _fire(tr: Dictionary, fwd: Vector3) -> void:
	var p: CPUParticles3D = _pool[_i]
	_i = (_i + 1) % POOL
	var sh: Dictionary = tr.sh
	var k: float = tr.k
	p.lifetime = sh.lifetime * randf_range(0.9, 1.1)
	p.explosiveness = 0.85  # a short billow, not one pop
	p.amount = maxi(int(sh.amount / SEGMENTS), 4)
	p.scale_amount_min = sh.size * 0.45
	p.scale_amount_max = sh.size * 1.6
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 2.2 + 1.6 * k
	p.emission_box_extents = Vector3(tr.width * 0.5 + 0.1, sh.size * 0.3, tr.seg * 0.5)  # lumpy top, not a slab
	var wind: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
	p.gravity = Vector3(wind.y * 0.12, 0.35, -wind.x * 0.12)  # warm smoke rises a little and drifts downwind
	p.rotation = Vector3(0.0, -tr.track, 0.0)  # local +Z back along the roll, X across the leg
	var c: Vector3 = tr.start + fwd * (maxf(tr.fired - 0.5, 0.0) * tr.seg)
	p.global_position = FloatingOrigin.to_render_d(c.x, c.y, c.z + sh.lift * randf_range(0.7, 1.5))
	p.restart()
	p.emitting = true


func stop_all() -> void:
	_trails.clear()
	for p in _pool:
		(p as CPUParticles3D).emitting = false
		(p as CPUParticles3D).restart()
		(p as CPUParticles3D).emitting = false


func _make() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.local_coords = false  # released puffs stay where they were laid
	p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.direction = Vector3(0.0, 0.9, 1.0)  # local: thrown back off the tyre and a little up
	p.spread = 70.0
	p.damping_min = 1.2  # air stops it within a few metres
	p.damping_max = 2.2
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -14.0
	p.angular_velocity_max = 14.0
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	p.mesh = q
	p.material_override = _material()
	p.color_ramp = alpha_ramp()
	var sc := Curve.new()  # small at the tyre, spreading as it drifts
	sc.max_value = 3.0
	sc.add_point(Vector2(0.0, 0.5))
	sc.add_point(Vector2(0.12, 1.0))
	sc.add_point(Vector2(0.4, 1.8))
	sc.add_point(Vector2(1.0, 2.6))
	p.scale_amount_curve = sc
	return p


static func _material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true  # else every puff is drawn 1 m across whatever its scale
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture()
	m.albedo_color = Color(0.93, 0.93, 0.92)
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP  # soft light all round, like a cloud
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA  # no hard puff right in front of the camera
	m.distance_fade_min_distance = 0.4
	m.distance_fade_max_distance = 3.0
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		m.proximity_fade_enabled = true  # soft where a puff meets the runway (depth texture)
		m.proximity_fade_distance = 0.5
	return m


## The puff picture: white, alpha a soft round falloff with a lumpy cloud edge, exactly 0 well inside the square.
static func texture() -> ImageTexture:
	if _tex:
		return _tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var r := v.length()
			var lump := _fbm(v.x * 2.2 + 3.0, v.y * 2.2 + 7.0)
			var re := r / (0.75 + 0.25 * lump)  # a cloudy rim, inside the unit circle
			var a := pow(clampf(1.0 - re * re, 0.0, 1.0), 3.0)  # bell-shaped, zero at the rim: overlapping puffs merge
			a *= 0.9 + 0.1 * _fbm(v.x * 5.0 + 11.0, v.y * 5.0 + 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_tex = ImageTexture.create_from_image(img)
	return _tex


static func _fbm(x: float, y: float) -> float:
	return _vn(x, y) * 0.65 + _vn(x * 2.1 + 5.2, y * 2.1 + 1.3) * 0.35


static func _vn(x: float, y: float) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - xi
	var fy := y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var h := func(a: int, b: int) -> float: return float(hash(Vector2i(a, b)) & 0xFFFF) / 65535.0
	return lerpf(lerpf(h.call(xi, yi), h.call(xi + 1, yi), fx), lerpf(h.call(xi, yi + 1), h.call(xi + 1, yi + 1), fx), fy)
