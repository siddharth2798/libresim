class_name FollowMeCar
extends Node3D
## The airport follow-me car: a yellow double-cab pickup (generic, no brand) with a chequered FOLLOW ME
## board and amber light bar on the roof, headlamps, brake lamps, reflective stripes. GroundOps moves
## it along the taxi route and calls place() every frame; everything else is cosmetic and lives
## here: steered, rolling wheels, body pitch and roll from acceleration and turning, tilt to the
## ground under the four wheels, brake lamps when it slows or waits, beacon flash pattern, lamps at
## night. Meshes: follow_me_shell.gd (+ _body, _cabin, _roof), follow_me_wheel.gd; maths:
## follow_me_logic.gd; lamps: follow_me_lights.gd. Not a solid for the crash check.

const LABEL_COLOR := Color(0.02, 0.02, 0.02)

static var _shell: ArrayMesh
static var _wheel: ArrayMesh
static var _mat: ShaderMaterial
static var _glass_mat: ShaderMaterial
static var _shadow_mat: ShaderMaterial

var world_enu := Vector3.ZERO  # last placed position (east, north, up)
var heading := 0.0  # smoothed compass heading (rad)
var speed := 0.0  # m/s
var accel := 0.0  # m/s2, filtered
var steer := 0.0  # front wheel angle (rad, right positive)
var brake := false
var flash := Vector2.ZERO  # beacon intensity left / right
var _body: Node3D
var _wheels: Array = []  # [pivot (steer), spin, is_front]
var _lights := FollowMeLights.new()
var _spin := 0.0
var _yaw_rate := 0.0
var _tilt := Vector2.ZERO  # ground pitch, roll
var _pb := Vector2.ZERO  # body pitch (x), pitch rate (y)
var _rb := Vector2.ZERO  # body roll, roll rate
var _t := 0.0
var _night := 0.0
var _night_timer := 0.0
var _placed := false


static func _materials() -> void:
	if _mat != null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://world/follow_me.gdshader")
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = preload("res://world/follow_me_glass.gdshader")
	_glass_mat.render_priority = -1
	_shadow_mat = ShaderMaterial.new()
	_shadow_mat.shader = preload("res://world/follow_me_shadow.gdshader")
	_shadow_mat.render_priority = -2
	_shell = FollowMeShell.build(_mat, _glass_mat)
	_wheel = FollowMeWheel.build(_mat)


static func release() -> void:
	_shell = null
	_wheel = null
	_mat = null
	_glass_mat = null
	_shadow_mat = null
	FollowMeLights.release()


func _init() -> void:
	_materials()
	name = "FollowMeCar"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var mi := MeshInstance3D.new()
	mi.mesh = _shell
	_body.add_child(mi)
	_lights.build(_body)
	_add_sign_text()
	for i in 4:
		var front := i < 2
		var left := i % 2 == 0
		var pivot := Node3D.new()
		pivot.position = Vector3(-FollowMeLogic.TRACK_HALF if left else FollowMeLogic.TRACK_HALF, FollowMeLogic.WHEEL_R,
			FollowMeLogic.AXLE_F if front else FollowMeLogic.AXLE_R)
		var spin := Node3D.new()
		var wm := MeshInstance3D.new()
		wm.mesh = _wheel
		if left:
			wm.rotation.y = PI  # dish outward
		spin.add_child(wm)
		pivot.add_child(spin)
		add_child(pivot)
		_wheels.append([pivot, spin, front])
	var sh := MeshInstance3D.new()  # soft contact shadow
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.4, 7.0)
	sh.mesh = pm
	sh.material_override = _shadow_mat
	sh.position = Vector3(0, 0.05, 0.0)
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sh)
	_apply_pose(0.0)


func _add_sign_text() -> void:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.8
	for s in [-1.0, 1.0]:  # +1 faces aft
		var l := Label3D.new()
		l.text = "FOLLOW ME"
		l.font = font
		l.font_size = 96
		l.pixel_size = 0.00175
		l.modulate = LABEL_COLOR
		l.outline_size = 0
		l.shaded = false
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.position = Vector3(0, FollowMeRoof.SIGN_Y, FollowMeRoof.SIGN_Z + s * 0.031)
		l.rotation.y = 0.0 if s > 0.0 else PI
		_body.add_child(l)


## Put the car at ENU (e, n) heading `target` (compass rad) after dt seconds; hf(e, n) = ground height.
## The position and the route heading are GroundOps' (unchanged); the heading is smoothed into turns
## here so the wheels steer and the body leans.
func place(e: float, n: float, target: float, dt: float, hf: Callable) -> void:
	if not _placed:
		_placed = true
		world_enu = Vector3(e, n, hf.call(e, n))
		heading = target
	if dt > 0.0:
		var v := Vector2(e - world_enu.x, n - world_enu.y).length() / dt
		var a := clampf((v - speed) / dt, -4.0, 4.0)
		speed = lerpf(speed, v, clampf(dt * 10.0, 0.0, 1.0))
		accel = lerpf(accel, a, clampf(dt * 4.0, 0.0, 1.0))
		var h0 := heading
		heading = FollowMeLogic.turn_toward(heading, target, maxf(0.9, speed * 0.45), dt)
		_yaw_rate = lerpf(_yaw_rate, FollowMeLogic.angle_diff(h0, heading) / dt, clampf(dt * 8.0, 0.0, 1.0))
		steer = lerpf(steer, FollowMeLogic.steer_angle(speed, _yaw_rate), clampf(dt * 8.0, 0.0, 1.0))
		_spin = FollowMeLogic.spin(_spin, speed, FollowMeLogic.WHEEL_R, dt)
		brake = FollowMeLogic.brake_on(accel, speed, brake)
	var fwd := Vector2(sin(heading), cos(heading))
	var right := Vector2(cos(heading), -sin(heading))
	var c := Vector2(e, n)
	var pf := c + fwd * -FollowMeLogic.AXLE_F
	var pr := c - fwd * FollowMeLogic.AXLE_R
	var pl := c - right * FollowMeLogic.TRACK_HALF
	var pp := c + right * FollowMeLogic.TRACK_HALF
	var hf_ := float(hf.call(pf.x, pf.y))
	var hr_ := float(hf.call(pr.x, pr.y))
	var tilt := FollowMeLogic.ground_tilt(hf_, hr_, float(hf.call(pl.x, pl.y)), float(hf.call(pp.x, pp.y)))
	_tilt = tilt if dt <= 0.0 else _tilt.lerp(tilt, clampf(dt * 6.0, 0.0, 1.0))
	world_enu = Vector3(e, n, (hf_ + hr_) * 0.5)
	var tgt := FollowMeLogic.body_targets(accel, speed * _yaw_rate)
	if dt > 0.0:
		_pb = FollowMeLogic.spring_step(_pb.x, _pb.y, tgt.x, 9.0, 0.6, dt)
		_rb = FollowMeLogic.spring_step(_rb.x, _rb.y, tgt.y, 9.0, 0.6, dt)
	_apply_pose(dt)


func _apply_pose(_dt: float) -> void:
	position = FloatingOrigin.to_render(world_enu)
	basis = Basis(Vector3.UP, -heading) * Basis(Vector3.RIGHT, _tilt.x) * Basis(Vector3.BACK, _tilt.y)
	var bb := Basis(Vector3.RIGHT, _pb.x) * Basis(Vector3.BACK, _rb.x)
	_body.transform = Transform3D(bb, FollowMeLogic.ROLL_PIVOT - bb * FollowMeLogic.ROLL_PIVOT)
	for w in _wheels:
		(w[0] as Node3D).basis = Basis(Vector3.UP, -steer) if w[2] else Basis.IDENTITY
		(w[1] as Node3D).basis = Basis(Vector3.RIGHT, -_spin)


func _process(dt: float) -> void:
	_t += dt
	_night_timer -= dt
	if _night_timer <= 0.0:
		_night_timer = 0.25
		_night = FollowMeLogic.night_level(Props.get_f("environment/sun_elev_deg", 30.0),
			Props.get_f("environment/visibility_m", Props.get_f("weather/visibility_m", 20000.0)))
	flash = Vector2(FollowMeLogic.flash(_t, 0), FollowMeLogic.flash(_t, 1))
	_mat.set_shader_parameter("amber_l", flash.x)
	_mat.set_shader_parameter("amber_r", flash.y)
	_mat.set_shader_parameter("tail_glow", 1.0 if brake else lerpf(0.1, 0.3, _night))
	_mat.set_shader_parameter("head_glow", lerpf(0.25, 1.0, _night))
	_mat.set_shader_parameter("night", _night)
	var f := -global_transform.basis.z
	_lights.update(Vector2(f.x, f.z), flash, brake, _night)
