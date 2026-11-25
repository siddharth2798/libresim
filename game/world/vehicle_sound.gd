class_name VehicleSound
extends Node3D
## The engine of an airport vehicle (WorldSound.KINDS: pushback tug, follow-me car, GPU, fuel truck ...), a positional
## loop at the vehicle that idles at rest and revs with its speed, worked out from how far it moved each frame (a jump
## over JUMP_M, a teleport or an origin shift, is ignored). A stationary machine (GPU, fuel pump) just runs.
## VehicleSound.attach(vehicle, kind) adds one; an unknown kind or a missing file adds nothing.

const JUMP_M := 5.0
const EASE_S := 0.4

var kind := ""
var speed := 0.0  # m/s, smoothed
var player: AudioStreamPlayer3D
var _last := Vector3.ZERO
var _started := false


static func attach(vehicle: Node3D, p_kind: String) -> VehicleSound:
	var k: Dictionary = WorldSound.KINDS.get(p_kind, {})
	if k.is_empty() or not ResourceLoader.exists(WorldSound.path(k.file)):
		return null
	var v := VehicleSound.new()
	v.name = "EngineSound"
	v.kind = p_kind
	v.player = WorldSound.loop_player(k.file, float(k.unit_m))
	v.add_child(v.player)
	vehicle.add_child(v)
	return v


func _ready() -> void:
	_apply()
	if player.stream:
		player.play(randf() * player.stream.get_length())  # vehicles of one kind do not run in step


func _process(dt: float) -> void:
	var p := global_position
	if _started and dt > 0.0 and p.distance_to(_last) <= JUMP_M:
		speed = lerpf(speed, p.distance_to(_last) / dt, 1.0 - exp(-dt / EASE_S))
	_started = true
	_last = p
	_apply()


func _apply() -> void:
	var st := WorldSound.vehicle_state(kind, speed)
	player.volume_db = linear_to_db(maxf(st[0], 0.0001))
	player.pitch_scale = st[1]
	player.attenuation_filter_cutoff_hz = WorldSound.cutoff_hz()
