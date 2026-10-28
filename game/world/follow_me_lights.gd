class_name FollowMeLights
extends RefCounted
## The follow-me car's lamps as aerodrome light points (world/light_point.gdshader, the same glow as
## runway and taxiway lights): headlamps, tail / brake lamps, the six amber beacon lamps of the
## light bar and the board. One MultiMesh in the car body; each frame sets the flash and brake state
## and turns the beams with the car (the shader reads beam directions in render x / z).
## Real lights: a spot light for the headlamps and a small amber omni, at night only.

const HEAD := [Vector3(-0.69, 0.84, -2.41), Vector3(0.69, 0.84, -2.41)]
const TAIL := [Vector3(-0.905, 0.86, 2.45), Vector3(0.905, 0.86, 2.45)]
const WHITE := Color(1.0, 0.95, 0.82)
const RED := Color(1.0, 0.05, 0.03)
const AMBER := Color(1.0, 0.5, 0.06)

static var _mat: ShaderMaterial

var instance: MultiMeshInstance3D
var spot: SpotLight3D
var omni: OmniLight3D
var _n_head := 2
var _n_tail := 2


static func release() -> void:
	_mat = null


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://world/light_point.gdshader")
		_mat.set_shader_parameter("gain", 2.2)
		_mat.set_shader_parameter("base_m", 0.16)
		_mat.set_shader_parameter("min_px", 2.0)
		_mat.set_shader_parameter("max_m", 5.0)
		_mat.set_shader_parameter("halo", 0.4)
		_mat.render_priority = 1
	return _mat


## Lamp positions are in the car's frame (x right, y up, -z forward); LightSet takes (east, north) =
## (x, -z).
func build(body: Node3D) -> void:
	var s := LightSet.new()
	for p in HEAD:
		s.add(p.x, -p.z, p.y, WHITE, Vector2(0, 1), 6.0, 0.04)
	for p in TAIL:
		s.add(p.x, -p.z, p.y, RED, Vector2(0, -1), 4.0, 0.05)
	for lamp in FollowMeRoof.LAMPS:
		var p: Vector3 = lamp[1]
		s.add(p.x, -p.z, p.y, AMBER, Vector2.ZERO, 0.0, 0.0, false, 0.0, 1.3)
	instance = s.make_instance(material(), "Lamps")
	instance.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))
	body.add_child(instance)
	spot = SpotLight3D.new()
	spot.position = Vector3(0, 0.9, -2.4)
	spot.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	spot.spot_range = 42.0
	spot.spot_angle = 26.0
	spot.spot_attenuation = 1.2
	spot.light_color = WHITE
	spot.light_energy = 0.0
	spot.visible = false
	body.add_child(spot)
	omni = OmniLight3D.new()
	omni.position = Vector3(0, 2.0, 0.2)
	omni.omni_range = 8.0
	omni.light_color = AMBER
	omni.light_energy = 0.0
	omni.visible = false
	body.add_child(omni)


## fwd: the car's forward direction in render x / z. flash: [left, right] 0..1; brake: brake lamps on;
## night: 0..1.
func update(fwd: Vector2, flash: Vector2, brake: bool, night: float) -> void:
	var mm := instance.multimesh
	var f := fwd.normalized()
	var level := lerpf(0.3, 1.0, night)
	material().set_shader_parameter("level", level)
	var i := 0
	var head := lerpf(0.5, 1.0, night)
	for k in _n_head:
		mm.set_instance_color(i, Color(WHITE.r * head, WHITE.g * head, WHITE.b * head, 1.0))
		mm.set_instance_custom_data(i, Color(f.x, f.y, 6.04, 0.0))
		i += 1
	var tail := 1.0 if brake else 0.28
	for k in _n_tail:
		mm.set_instance_color(i, Color(RED.r * tail, RED.g * tail, RED.b * tail, 1.5 if brake else 0.8))
		mm.set_instance_custom_data(i, Color(-f.x, -f.y, 4.05, 0.0))
		i += 1
	for lamp in FollowMeRoof.LAMPS:
		var e: float = flash.x if lamp[0] == 0 else flash.y
		mm.set_instance_color(i, Color(AMBER.r, AMBER.g, AMBER.b, 1.3 * e))
		i += 1
	spot.visible = night > 0.03
	spot.light_energy = 5.0 * night
	omni.visible = night > 0.03
	omni.light_energy = 1.6 * night * maxf(flash.x, flash.y)
