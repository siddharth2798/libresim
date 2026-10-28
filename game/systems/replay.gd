class_name Replay
extends Node
## Instant replay. While flying it records the FDM state and the Props that the
## model, gauges and sound read (ReplayChannels) into a ring buffer at 20 Hz
## (last `minutes`). In replay mode the FDM is held (FdmNode.replaying) and this
## node writes the interpolated recorded state into the FDM object and Props every
## frame, so the model, cameras, instruments and audio all follow the recording.
## take_control() resumes live flight from the current replay point.
## Props: "replay/active" (bool), "replay/speed", "replay/playing".

signal started
signal stopped(took_control: bool)

const RATE_HZ := 20.0
const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0]
const JUMP_M := 500.0  # a larger move between two samples = reset / teleport: start over

@export var fdm_path: NodePath = ^"../Fdm"
@export var minutes := 10.0

var fdm_node: FdmNode
var buffer: ReplayBuffer
var channels: ReplayChannels
var active := false
var playing := false
var speed := 1.0
var t := 0.0  # replay position on the recording clock (s)
var clock := 0.0  # recording clock: flight time while the FDM runs (s)
var _next_sample := 0.0
var _frame := {}
var _live := {}  # FDM fields when replay started (restored on exit)
var _live_props := {}


func _ready() -> void:
	process_priority = 1000  # our Props writes land after keyboard controls and systems
	if fdm_node == null:
		setup(get_node_or_null(fdm_path))
	get_tree().process_frame.connect(_on_frame)  # before any _process: pose ready for model/camera


func setup(node: FdmNode) -> void:
	fdm_node = node
	channels = ReplayChannels.new()
	buffer = ReplayBuffer.new(channels.kinds, minutes * 60.0, RATE_HZ)
	_publish()


func _physics_process(dt: float) -> void:
	record_tick(dt)


## Called every physics tick: advances the recording clock and samples at 20 Hz.
func record_tick(dt: float) -> void:
	if active or fdm_node == null or fdm_node.paused or fdm_node.fdm.damage.crashed:
		return
	clock += dt
	if clock + 1e-6 < _next_sample:
		return
	_next_sample += 1.0 / RATE_HZ
	if _next_sample <= clock:
		_next_sample = clock + 1.0 / RATE_HZ
	var f := fdm_node.fdm
	var p := Vector3(f.pos_e, f.pos_n, -f.pos_d)
	if buffer.size() > 0 and buffer.position_at(buffer.end_time()).distance_to(p) > JUMP_M:
		buffer.clear()
	buffer.push(clock, f.pos_e, f.pos_n, -f.pos_d, channels.capture(f))


func can_replay() -> bool:
	return buffer != null and buffer.size() >= 2


## Enter replay `from_seconds_ago` before the newest frame (clamped to the oldest).
func start_replay(from_seconds_ago := 60.0) -> bool:
	if active or not can_replay():
		return false
	_live = ReplayChannels.save_live(fdm_node.fdm)
	_live_props = {}
	for k in channels.keys + ["fdm/position_enu", "fdm/body_rates", "fdm/accel_body"]:
		_live_props[k] = Props.get_v(k)
	active = true
	playing = true
	speed = 1.0
	fdm_node.replaying = true
	t = maxf(buffer.end_time() - from_seconds_ago, buffer.start_time())
	_apply_state()
	_publish()
	started.emit()
	return true


## Leave replay and return to the live flight exactly where it was.
func stop_replay() -> void:
	if not active:
		return
	ReplayChannels.restore_live(fdm_node.fdm, _live)
	for k in _live_props:
		if _live_props[k] != null:
			Props.set_v(k, _live_props[k])
	_end(false)


## Resume live flight from the current replay point; later frames are discarded.
func take_control() -> void:
	if not active:
		return
	var fr := buffer.sample(t)
	var f := fdm_node.fdm
	channels.apply_state(fr, f)  # position, attitude, recorded velocity, body rates, rpm
	channels.apply_props(fr)  # controls/*, switches, instruments
	var c: PackedFloat32Array = fr.ch
	var g := func(k: String, d: Variant) -> Variant:
		var v: Variant = channels.prop_value(c, k)
		return d if v == null else v
	f.fcs.pitch_trim = g.call("controls/pitch_trim", f.fcs.pitch_trim)
	f.fcs.flap_cmd = g.call("controls/flaps", f.fcs.flap_cmd)
	f.engine.throttle = g.call("controls/throttle", f.engine.throttle)
	f.engine.mixture = g.call("controls/mixture", f.engine.mixture)
	f.engine.egt_k = g.call("engine/egt_k", f.engine.egt_k)
	f.engine.cht_k = g.call("engine/cht_k", f.engine.cht_k)
	f.engine.oil_temp_k = g.call("engine/oil_temp_k", f.engine.oil_temp_k)
	f.engine.oil_press_pa = g.call("engine/oil_press_pa", f.engine.oil_press_pa)
	f.mb.set_side_kg("left", g.call("fuel/left_kg", f.mb.side_kg("left")))
	f.mb.set_side_kg("right", g.call("fuel/right_kg", f.mb.side_kg("right")))
	f.mb.update()
	if f.damage.crashed:  # taking over before the crash: aircraft as it was then
		f.damage.reset()
		f.gear = GearGround.new(f.cfg)
		for u in f.units:
			u.engine.failed = false
	buffer.truncate_after(t)
	clock = t
	_next_sample = t + 1.0 / RATE_HZ
	_end(true)


## Velocity (NED) the live FDM gets on take_control at time `at`: the recorded one.
## velocity_estimate_ned() is the track-derived cross-check.
func recorded_velocity_ned(at: float) -> Vector3:
	return ReplayChannels.velocity_ned(buffer.sample(at).ch)


func velocity_estimate_ned(at: float) -> Vector3:
	var v := buffer.velocity_estimate(at)  # ENU
	return Vector3(v.y, v.x, -v.z)


func set_speed(x: float) -> void:
	speed = x
	_publish()


## One step slower (-1) or faster (+1) through SPEEDS.
func step_speed(dir: int) -> void:
	var i := SPEEDS.find(speed)
	i = clampi((i if i >= 0 else 2) + dir, 0, SPEEDS.size() - 1)
	set_speed(SPEEDS[i])


func set_playing(on: bool) -> void:
	playing = on
	if on and t >= buffer.end_time() - 1e-3:
		t = buffer.start_time()  # at the end: play again from the start
	_publish()


func toggle_play() -> void:
	set_playing(not playing)


## Jump to a recording-clock time (clamped to the recorded span).
func seek(to: float) -> void:
	if not active:
		return
	t = clampf(to, buffer.start_time(), buffer.end_time())
	_apply_state()


func seek_relative(dt: float) -> void:
	seek(t + dt)


func elapsed() -> float:
	return t - buffer.start_time()


func total() -> float:
	return buffer.duration()


## Forget everything (flight reset / new start position). Leaves replay without restoring.
func clear() -> void:
	if active:
		_end(false)
	buffer.clear()
	_next_sample = clock


func _end(took: bool) -> void:
	active = false
	playing = false
	fdm_node.replaying = false
	fdm_node._snap()
	_frame = {}
	_publish()
	stopped.emit(took)


func _on_frame() -> void:
	if not active:
		return
	if playing and not fdm_node.paused:  # the pause menu also pauses the replay
		t += get_process_delta_time() * speed
		if t >= buffer.end_time():
			t = buffer.end_time()
			playing = false
			_publish()
	_apply_state()


func _apply_state() -> void:
	_frame = buffer.sample(t)
	if _frame.is_empty():
		return
	channels.apply_state(_frame, fdm_node.fdm)
	fdm_node._snap()
	channels.apply_props(_frame)


func _process(_dt: float) -> void:
	if active and not _frame.is_empty():
		channels.apply_props(_frame)  # again, after keyboard controls / systems wrote theirs


func _publish() -> void:
	Props.set_v("replay/active", active)
	Props.set_v("replay/playing", playing)
	Props.set_v("replay/speed", speed)
