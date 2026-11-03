class_name ApronLamps
extends Node3D
## Real SpotLights for the apron floodlight banks nearest the camera (child of RunwayLights). The budget comes
## from the graphics preset (Graphics "real_lights": few on Mobile, which lights a mesh with at most 8 spot
## lights, more on Forward+); "apron_shadows" banks nearest the player's aircraft also cast shadows (Ultra / Max).
## No popping: with the banks sorted by distance d from the camera and R the distance of the first bank that
## gets no lamp (or RANGE), a bank's real lamp has energy 1 - f and its fake ground pool (light_pool.gdshader)
## f = smoothstep(R - BAND, R, d). R moves continuously with the camera, so a bank swaps between real and fake
## only while both are at zero.

const RANGE := 650.0  # banks farther than this from the camera only get the pool
const BAND := 90.0  # cross-fade width (m)
const ENERGY := 0.28  # irradiance at the aim point (energy = ENERGY x throw^2, inverse-square spot); pool = strength
const CONE_EXTRA := 10.0  # deg: the spot cone is the bank's half-angle + this (light_pool.gdshader: same cone)
const CONE_EXP := 1.0  # spot_angle_attenuation; 1 = a peaked beam (2 was flat-topped: an even white apron)
const RANGE_K := 2.2  # spot range = throw x this (light_pool.gdshader RANGE_K)
const SHADOW_R := 140.0  # only banks this close to the player's aircraft may cast shadows

var _lamps: Array[SpotLight3D] = []
var _owner: Array = []  # lamp index -> bank key ("" = free)
var _shadows := 0
var _near: Array = []  # banks within reach of the camera (refreshed every 0.5 s)
var _timer := 0.0
var real_in := -1.0  # what the pools were last told (tests / debug)
var real_out := -1.0


func set_budget(n: int, shadows := 0) -> void:
	_shadows = shadows
	while _lamps.size() > n:
		_lamps.pop_back().queue_free()
		_owner.pop_back()
	while _lamps.size() < n:
		var l := SpotLight3D.new()
		l.spot_attenuation = 2.0  # inverse square, as the pool (light_pool.gdshader)
		l.spot_angle_attenuation = CONE_EXP
		l.light_specular = 0.35
		l.shadow_enabled = false
		l.shadow_bias = 0.08
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_lamps.append(l)
		_owner.append("")


func count() -> int:
	return _lamps.size()


## Called every frame. built: icao -> AirportLights; eye: camera ENU; player: aircraft ENU; level: night 0..1;
## pool: the pool material (gets real_eye / real_in / real_out).
func update(dt: float, built: Dictionary, eye: Vector3, player: Vector3, level: float, pool: ShaderMaterial) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_timer = 0.5
		_refresh(built, eye)
	var cand := []
	if level > 0.01:
		for b in _near:
			var d: float = eye.distance_to(b.lamp)
			if d < RANGE:
				cand.append([d, b])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var n := _lamps.size()
	var r_out := RANGE if cand.size() <= n else minf(RANGE, cand[n][0])
	var r_in := maxf(r_out - BAND, 0.0)
	var picked := cand.slice(0, mini(n, cand.size()))
	var keys := {}
	for c in picked:
		keys[c[1].key] = c
	for k in n:  # lamps whose bank dropped out are freed; the others keep theirs (no re-aiming)
		if not keys.has(_owner[k]):
			_owner[k] = ""
	var taken := {}
	for k in n:
		if _owner[k] != "":
			taken[_owner[k]] = k
	var shadow_keys := _shadow_banks(picked, player)
	for c in picked:
		var key: String = c[1].key
		if not taken.has(key):
			var free := _owner.find("")
			_owner[free] = key
			taken[key] = free
			_aim(_lamps[free], c[1])
		var l := _lamps[taken[key]]
		var f := smoothstep(r_in, r_out, c[0]) if r_out > r_in else 1.0
		l.light_energy = ENERGY * c[1].throw * c[1].throw * level * (1.0 - f)
		l.visible = l.light_energy > 0.002
		l.shadow_enabled = key in shadow_keys
		l.position = FloatingOrigin.to_render_d(c[1].lamp.x, c[1].lamp.y, c[1].lamp.z)
	for k in n:
		if _owner[k] == "":
			_lamps[k].visible = false
	real_in = r_in if not picked.is_empty() else -1.0
	real_out = r_out if not picked.is_empty() else -1.0
	if pool:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		pool.set_shader_parameter("real_eye", cam.global_position if cam else Vector3.ZERO)
		pool.set_shader_parameter("real_in", real_in)
		pool.set_shader_parameter("real_out", real_out)


## Point the lamp at its bank's aim (render frame), colour and cone.
func _aim(l: SpotLight3D, b: Dictionary) -> void:
	var p := FloatingOrigin.to_render_d(b.lamp.x, b.lamp.y, b.lamp.z)
	var a := FloatingOrigin.to_render_d(b.aim.x, b.aim.y, b.aim.z)
	l.basis = Basis.looking_at(a - p, Vector3.UP if absf((a - p).normalized().y) < 0.99 else Vector3.FORWARD)
	l.light_color = b.col
	l.spot_angle = cone_deg(b.half_deg)
	l.spot_range = b.throw * RANGE_K


## Spot cone angle (deg) of a bank with this beam half-angle (the pool uses the same, ApronFloodlights._pool).
static func cone_deg(half_deg: float) -> float:
	return minf(half_deg + CONE_EXTRA, 85.0)


## The banks (keys) nearest the player's aircraft that cast shadows.
func _shadow_banks(picked: Array, player: Vector3) -> Array:
	if _shadows <= 0:
		return []
	var by := picked.map(func(c): return [Vector2(c[1].lamp.x, c[1].lamp.y).distance_to(Vector2(player.x, player.y)), c[1].key])
	by = by.filter(func(x): return x[0] < SHADOW_R)
	by.sort_custom(func(a, b): return a[0] < b[0])
	return by.slice(0, _shadows).map(func(x): return x[1])


func _refresh(built: Dictionary, eye: Vector3) -> void:
	_near.clear()
	var e := Vector2(eye.x, eye.y)
	for icao in built:
		for b in built[icao].banks:
			if e.distance_to(Vector2(b.lamp.x, b.lamp.y)) < RANGE + 300.0:
				_near.append(b)
