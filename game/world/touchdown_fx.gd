class_name TouchdownFx
extends Node3D
## Touchdown tyre smoke and rubber marks. Watches each main wheel's first contact after
## being airborne (FDM gear.info, no extra Props): the faster the ground speed and the
## harder the sink, the bigger the puff and the longer the skid mark left on the runway.
## Smoke: a small pool of one-shot CPUParticles3D puffs that drift with the wind.
## Marks: Decals (project onto whatever surface is below, so they sit on the runway
## without z-fighting), kept in a ring buffer and repositioned on origin shifts.

const MIN_AIR_S := 0.6        # a wheel must have been off the ground this long
const MIN_GS := 12.0          # m/s (~23 kt): slower contacts are taxiing, not landing
const MAX_MARKS := 40
const SMOKE_POOL := 6

var fdm_node: FdmNode
var _air := {}                # wheel name -> seconds since it last touched
var _marks: Array = []        # [Decal, Vector3 enu (e, n, up)]
var _smoke: Array = []        # [CPUParticles3D, Vector3 enu]
var _smoke_i := 0
var _mark_tex: Array[ImageTexture] = []
var _rng := RandomNumberGenerator.new()
var _puff_tex: GradientTexture2D


## Puff strength 0..1 for a wheel's first contact, 0 when it is not a landing contact.
static func puff(ground_speed: float, sink: float, airborne_s: float) -> float:
	if airborne_s < MIN_AIR_S or ground_speed < MIN_GS:
		return 0.0
	var speed_f := clampf((ground_speed - MIN_GS) / 22.0, 0.0, 1.0)
	var sink_f := clampf(sink / 2.5, 0.0, 1.0)
	return clampf(speed_f * (0.35 + 0.65 * sink_f) + 0.1, 0.0, 1.0)


## Rubber-mark strength 0..1 from how hard the wheel hit: a butter landing (< ~80 fpm) leaves
## nothing, a smooth one a faint short scuff, a firm one a clear dark mark, a hard one a long
## heavy streak. Ground speed matters a little (more rubber is scrubbed at higher speed).
static func mark_strength(sink: float, ground_speed: float) -> float:
	var fpm := sink * 196.85
	var s := clampf((fpm - 60.0) / 740.0, 0.0, 1.0)
	return s * (0.7 + 0.3 * clampf((ground_speed - MIN_GS) / 22.0, 0.0, 1.0))


static func mark_length(strength: float) -> float:
	return 0.8 + 7.0 * strength


static func mark_alpha(strength: float) -> float:
	return clampf(0.08 + 0.9 * strength, 0.0, 1.0)


func setup(f: FdmNode) -> void:
	fdm_node = f
	_rng.randomize()
	for i in 4:
		_mark_tex.append(_make_mark_texture(i * 7919 + 13))
	_puff_tex = GradientTexture2D.new()
	_puff_tex.fill = GradientTexture2D.FILL_RADIAL
	_puff_tex.fill_from = Vector2(0.5, 0.5)
	_puff_tex.fill_to = Vector2(1.0, 0.5)
	_puff_tex.width = 64
	_puff_tex.height = 64
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	_puff_tex.gradient = g
	for i in SMOKE_POOL:
		var p := _make_smoke()
		add_child(p)
		_smoke.append([p, Vector3.ZERO])
	FloatingOrigin.shifted.connect(func(_d): _reposition())


func clear() -> void:
	for m in _marks:
		m[0].queue_free()
	_marks.clear()
	_air.clear()


func _physics_process(dt: float) -> void:
	if fdm_node == null or fdm_node.paused or fdm_node.replaying:
		return
	var gear := fdm_node.fdm.gear
	for c in gear.contacts:
		if not c.wheel:
			continue
		var info: Dictionary = gear.info.get(c.name, {})
		if info.get("depth", 0.0) <= 0.0:
			_air[c.name] = _air.get(c.name, 0.0) + dt
			continue
		var air: float = _air.get(c.name, 0.0)
		_air[c.name] = 0.0
		if air < MIN_AIR_S or c.name == "NOSE":
			continue
		var v := fdm_node.fdm.velocity_ned()
		var gs := Vector2(v.x, v.y).length()
		var sink := float(info.get("vz", 0.0))
		var k := puff(gs, sink, air)
		if k > 0.0:
			_spawn(float(info.n), float(info.e), atan2(v.y, v.x), k, mark_strength(sink, gs))


func _spawn(n: float, e: float, track: float, k: float, strength := -1.0) -> void:
	var up: float = fdm_node.fdm.ground_height.call(n, e)
	var enu := Vector3(e, n, up)
	_emit_smoke(enu, track, k)
	_add_mark(enu, track, k if strength < 0.0 else strength)


func _emit_smoke(enu: Vector3, track: float, k: float) -> void:
	var slot: Array = _smoke[_smoke_i]
	_smoke_i = (_smoke_i + 1) % SMOKE_POOL
	var p: CPUParticles3D = slot[0]
	slot[1] = enu
	p.global_position = FloatingOrigin.to_render_d(enu.x, enu.y, enu.z + 0.15)
	var wind: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
	p.gravity = Vector3(wind.y, 0.25, -wind.x) * 0.35  # drifts downwind, rises slowly
	p.amount = int(6 + 22.0 * k)
	p.initial_velocity_max = 1.0 + 2.0 * k
	p.scale_amount_max = 1.4 + 1.8 * k
	p.lifetime = 1.6 + 1.4 * k
	# darker by night so the smoke does not glow
	var night := clampf((5.0 - Props.get_f("environment/sun_elev_deg", 30.0)) / 9.0, 0.0, 1.0)
	(p.material_override as StandardMaterial3D).albedo_color = Color(0.82, 0.82, 0.84).lerp(Color(0.16, 0.16, 0.18), night)
	p.restart()
	p.emitting = true


func _add_mark(enu: Vector3, track: float, strength: float) -> void:
	if strength < 0.03:
		return  # a butter landing leaves no mark
	if _marks.size() >= MAX_MARKS:
		_marks.pop_front()[0].queue_free()
	var len := mark_length(strength) * _rng.randf_range(0.85, 1.15)
	var d := Decal.new()
	d.size = Vector3(0.85 + 0.35 * strength, 1.5, len) * Vector3(_rng.randf_range(0.9, 1.1), 1.0, 1.0)
	d.texture_albedo = _mark_tex[_rng.randi() % _mark_tex.size()]  # a few noise variants: no two marks alike
	d.cull_mask = 1  # world only: aircraft meshes use their own render layer
	d.modulate = Color(1, 1, 1, mark_alpha(strength) * _rng.randf_range(0.85, 1.0))
	d.rotation.y = -track + deg_to_rad(_rng.randf_range(-1.5, 1.5))
	var ahead := Vector3(sin(track), 0.0, -cos(track)) * (len * 0.5)  # mark starts at the touch point
	add_child(d)
	d.set_meta("ahead", ahead)
	_marks.append([d, enu])
	_place(d, enu)


func _place(d: Decal, enu: Vector3) -> void:
	d.global_position = FloatingOrigin.to_render_d(enu.x, enu.y, enu.z) + d.get_meta("ahead", Vector3.ZERO)


func _reposition() -> void:
	for m in _marks:
		_place(m[0], m[1])
	for s in _smoke:
		(s[0] as CPUParticles3D).global_position = FloatingOrigin.to_render_d(s[1].x, s[1].y, s[1].z + 0.15)


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.3
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.8
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _puff_tex
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	p.material_override = m
	var ramp := Gradient.new()  # fade in fast, fade out slowly
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	p.color_ramp = ramp
	var sc := Curve.new()  # puffs grow as they drift
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = sc
	return p


## Value noise 0..1 on a hashed lattice (deterministic per seed).
static func _vn(x: float, y: float, seed: int) -> float:
	var xi := floori(x)
	var yi := floori(y)
	var fx := x - xi
	var fy := y - yi
	var h := func(a: int, b: int) -> float:
		return float(hash(Vector3i(a, b, seed)) & 0xFFFF) / 65535.0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(h.call(xi, yi), h.call(xi + 1, yi), fx), lerpf(h.call(xi, yi + 1), h.call(xi + 1, yi + 1), fx), fy)


## One rubber mark. X across the tyre, Y along the mark with the touch point at the BOTTOM
## (+Z end): a dark smudge where the tyre spins up, then a trail that fades and breaks into
## patches (rubber is laid down unevenly), with a ragged edge and slight width wander.
static func _make_mark_texture(seed: int) -> ImageTexture:
	var w := 32
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var d := 1.0 - float(y) / (h - 1)  # 0 at the touch point -> 1 at the far end
		var spin := exp(-pow(d / 0.17, 2.0))  # the spin-up smudge
		var trail := exp(-d * 1.7)
		var fade := smoothstep(0.0, 0.025, d) * (1.0 - smoothstep(0.8, 1.0, d))
		var half := 0.62 + 0.18 * (_vn(d * 6.0, 4.5, seed + 5) - 0.5)  # width wander
		for x in w:
			var across := absf(float(x) / (w - 1) * 2.0 - 1.0)
			var xn := float(x) / (w - 1)
			# blotchy break-up in 2D (not banded): coarse patches plus fine speckle
			var n := _vn(d * 8.0, xn * 2.2, seed) * 0.6 + _vn(d * 26.0, xn * 6.0, seed + 3) * 0.4 + 0.14 - d * 0.18
			var patchy := smoothstep(0.24, 0.5, n)
			var along := clampf(0.2 * spin + 0.85 * spin * patchy + 0.75 * trail * patchy, 0.0, 1.0) * fade
			var rag := _vn(float(x) * 0.5, d * 24.0, seed + 9)  # ragged edge
			var edge := 1.0 - smoothstep(half * 0.45, half * (0.85 + 0.3 * rag), across)
			var grain := 0.75 + 0.25 * _vn(float(x) * 1.3, float(y) * 0.9, seed + 11)
			img.set_pixel(x, y, Color(0.02, 0.02, 0.025, clampf(edge * along * grain, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
