class_name JetwaySound
extends Node3D
## A jetway's drive motor and moving-warning beeper (world/sounds/jetway_motor_loop.wav), heard at the cab while the bridge
## or its canopy moves (JetwayRig.progress / canopy_k change), eased in and out. Child of the rig's cab node.

const GAIN := 0.8
const EASE_S := 0.25
const UNIT_M := 8.0

var rig: JetwayRig
var player: AudioStreamPlayer3D
var level := 0.0  # eased 0..1
var _prev := Vector2(-1.0, -1.0)


static func attach(p_rig: JetwayRig, at: Node3D) -> JetwaySound:
	if not ResourceLoader.exists(WorldSound.path("jetway_motor_loop.wav")):
		return null
	var s := JetwaySound.new()
	s.name = "MotorSound"
	s.rig = p_rig
	s.player = WorldSound.loop_player("jetway_motor_loop.wav", UNIT_M, 400.0)
	s.add_child(s.player)
	at.add_child(s)
	return s


## Is the rig moving between two samples of (progress, canopy_k)? The first sample never counts.
static func moving(prev: Vector2, cur: Vector2) -> bool:
	return prev.x >= 0.0 and prev.distance_to(cur) > 1e-5


func _process(dt: float) -> void:
	var cur := Vector2(rig.progress, rig.canopy_k)
	var target := 1.0 if moving(_prev, cur) else 0.0
	_prev = cur
	level = lerpf(level, target, 1.0 - exp(-dt / EASE_S)) if dt > 0.0 else target
	if level < 0.002:
		if player.playing:
			player.stop()
		return
	if not player.playing and player.stream:
		player.play()
	player.volume_db = linear_to_db(level * GAIN)
	player.attenuation_filter_cutoff_hz = WorldSound.cutoff_hz()
