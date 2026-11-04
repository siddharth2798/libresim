class_name VehicleMotion
extends Node3D
## Root of a procedural ground vehicle that drives (GroundVehicles.make(..., moving = true)): whoever moves
## it just sets its position and rotation; each frame this rolls the wheels by the distance travelled
## along the vehicle's axis (forward or reversing) and steers the front ones from the turn rate
## (bicycle model: tan(steer) = wheelbase x yaw rate / speed). The shader does the turning
## (world/vehicle.gdshader, instance uniforms wheel_turn / steer).

const MAX_STEER := 0.6
const JUMP_M := 5.0  # a bigger step in one frame is a teleport (or a floating-origin shift): no roll

var turn := 0.0  # metres rolled, model units
var steer := 0.0  # rad, right positive
var _body: GeometryInstance3D
var _wheelbase := 2.0
var _size := 1.0
var _last := Vector3.ZERO
var _last_yaw := 0.0
var _started := false


func setup(body: GeometryInstance3D, wheels: Array, size: float) -> void:
	_body = body
	_size = size
	var zf := INF
	var zr := -INF
	for w in wheels:
		var c: Vector3 = w[0]
		zf = minf(zf, c.z)
		zr = maxf(zr, c.z)
	if zr > zf:
		_wheelbase = (zr - zf) * size


## Advance by a move of d (render frame) and a heading change dyaw (rad, left positive) over dt.
func advance(d: Vector3, dyaw: float, dt: float) -> void:
	if d.length() > JUMP_M or dt <= 0.0:
		return
	var f := -global_basis.z.normalized()
	var ds := d.dot(f)
	turn += ds / _size
	var want := 0.0
	if absf(ds) > 1e-4:
		want = clampf(atan(_wheelbase * (-dyaw) / ds), -MAX_STEER, MAX_STEER)
	steer = lerpf(steer, want, clampf(dt * 6.0, 0.0, 1.0))
	if _body != null:
		_body.set_instance_shader_parameter("wheel_turn", turn)
		_body.set_instance_shader_parameter("steer", steer)


func _process(dt: float) -> void:
	if not is_inside_tree():
		return
	var p := global_position
	var yaw := global_rotation.y
	if _started:
		advance(p - _last, wrapf(yaw - _last_yaw, -PI, PI), dt)
	_started = true
	_last = p
	_last_yaw = yaw
