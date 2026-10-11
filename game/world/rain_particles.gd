class_name RainParticles
extends GPUParticles3D
## Rain streaks in a box around the camera (world/rain_streak.gdshader draws each one as a
## camera-facing streak along its velocity). The box follows the camera without rotating;
## particles move at the rain's velocity relative to the camera (fall + wind - aircraft),
## so streaks lean into the wind and stretch with airspeed.

const BOX := 40.0  # emission box edge (m)
const FALL := 8.0  # heavy-rain drop fall speed (m/s)

var max_count := 6000  # set from the graphics preset
var _proc := ParticleProcessMaterial.new()
var _draw := ShaderMaterial.new()


func _ready() -> void:
	amount = maxi(max_count, 1)
	lifetime = 0.9
	preprocess = 0.9
	local_coords = true
	fixed_fps = 0
	interpolate = false
	visibility_aabb = AABB(Vector3.ONE * -BOX, Vector3.ONE * BOX * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_proc.emission_box_extents = Vector3.ONE * BOX * 0.5
	_proc.gravity = Vector3.ZERO
	_proc.spread = 2.0
	_proc.particle_flag_align_y = true
	process_material = _proc
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, 0, 0)
	_draw.shader = preload("res://world/rain_streak.gdshader")
	q.material = _draw
	draw_pass_1 = q
	emitting = false


func set_max(n: int) -> void:
	max_count = maxi(n, 0)
	if n > 0 and amount != n:
		amount = n


## rain: rate 0..1; rel_vel: rain velocity relative to the camera (render frame, m/s);
## light: brightness of the streaks (ambient grey); cam: the active camera.
func update_rain(rain: float, rel_vel: Vector3, light: Color, cam: Camera3D) -> void:
	var on := rain > 0.005 and max_count > 0 and cam != null
	if on != emitting:
		emitting = on
	visible = on or emitting
	if cam == null:
		return
	global_position = cam.global_position + rel_vel * -lifetime * 0.5  # upstream so streaks pass the camera
	global_basis = Basis.IDENTITY
	amount_ratio = clampf(rain, 0.0, 1.0)
	var spd := rel_vel.length()
	_proc.direction = rel_vel / maxf(spd, 0.01)
	_proc.initial_velocity_min = spd * 0.92
	_proc.initial_velocity_max = spd * 1.05
	_draw.set_shader_parameter("streak_len", clampf(0.35 + spd * 0.022, 0.35, 2.2))
	_draw.set_shader_parameter("tint", light)
	_draw.set_shader_parameter("alpha", lerpf(0.3, 0.55, clampf(rain, 0.0, 1.0)))
