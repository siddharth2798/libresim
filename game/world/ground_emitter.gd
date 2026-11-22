class_name GroundEmitter
extends GPUParticles3D
## One ground particle effect (a wheel's spray, a rooster tail, wash mist, dust, rain splashes): GPU particles drawn as
## soft lit sprites (GroundFxLook). No collision, no trails and no sub-emitters, so it runs the same on Forward+, Mobile
## and Compatibility.
## Floating origin: particles live in the emitter's own frame (local_coords) and the emitter never follows its source.
## It only moves by the render shift when FloatingOrigin shifts (so particles already released keep their place on the
## ground), and the source is fed as the process material's emission_shape_offset. Once nothing has been emitted for
## longer than a lifetime the emitter goes back to the render origin, so the offsets stay small (float32).
## capacity (amount) comes from the preset (GroundFxQuality); 0 = off: hidden, never emits. rate 0..1 drives
## amount_ratio, which changes the emission without restarting the system.

var proc := ParticleProcessMaterial.new()
var capacity := 0
var reach := 6.0  # m: half size of the box the live particles stay in, about the source and its recent path
var _rate := 0.0
var _idle := 1e9  # s since the emitter last emitted


func _init(kind := "spray") -> void:
	top_level = true  # position is the render position, whatever the parent does
	local_coords = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	amount = 1
	emitting = false
	visible = false
	process_material = proc
	GroundFxLook.configure(self, kind)


func _ready() -> void:
	FloatingOrigin.shifted.connect(_on_shift)


func _exit_tree() -> void:
	if FloatingOrigin.shifted.is_connected(_on_shift):
		FloatingOrigin.shifted.disconnect(_on_shift)


## The preset's particle budget (0 = off). Changing amount restarts the system, so only on a real change.
func set_capacity(n: int) -> void:
	n = maxi(n, 0)
	if n == capacity:
		return
	capacity = n
	amount = maxi(n, 1)
	if n == 0:
		clear()
	visible = n > 0


## Emission strength 0..1 of the effect now (0 stops new particles; live ones finish their life).
func set_rate(r: float) -> void:
	_rate = clampf(r, 0.0, 1.0) if capacity > 0 else 0.0
	var on := _rate > 0.002
	if on:
		amount_ratio = _rate
		_idle = 0.0
	if on != emitting:
		emitting = on


func rate() -> float:
	return _rate


## Source position (render frame) and its velocity (m/s, render frame: the box the particles stay in trails it).
func place(src: Vector3, vel := Vector3.ZERO) -> void:
	var off := basis.inverse() * (src - position)  # a tilted emitter (RainSplash on a slope) takes it in its own frame
	proc.emission_shape_offset = off
	var r := Vector3.ONE * reach
	var box := AABB(off - r, r * 2.0)
	visibility_aabb = box.merge(AABB(off - vel * lifetime - r, r * 2.0))


## Stops at once and drops every live particle (a new flight, F5, a preset at 0).
func clear() -> void:
	_rate = 0.0
	emitting = false
	restart()
	emitting = false
	position = Vector3.ZERO
	_idle = 1e9


func _process(dt: float) -> void:
	if emitting:
		return
	_idle += dt
	if _idle > lifetime + 0.5 and position != Vector3.ZERO:
		position = Vector3.ZERO  # nothing alive: back to the origin (offsets small again)


func _on_shift(delta_render: Vector3) -> void:
	position += delta_render  # the ground moved in render space: the particles on it move with it
