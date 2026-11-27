class_name FrameCpu
extends RefCounted
## CPU time of the last frame (ms) for Auto render resolution (core/render_scaler.gd), measured as tests/bench_probe.gd
## does: main-thread work from the first physics / process step of the frame to the start of drawing (scripts, the 120 Hz
## physics steps, the property tree), plus the renderer's CPU time for the viewport and the frame setup
## (RenderingServer.viewport_get_measured_render_time_cpu, get_frame_setup_time_cpu). Waiting for vsync or the GPU is
## not counted, so a frame that is slow only because of the CPU can be told from one the GPU holds up. The same on every
## machine and renderer (the CPU readings need no GPU timestamps). -1 until a frame has been measured.

var _rid := RID()
var _start := -1  # usec, first physics / process step of the frame being built
var _game_ms := -1.0  # the last frame's main-thread part


## Measure `rid` (the main viewport); true on the first call for a viewport (its readings start next frame).
func watch(rid: RID) -> bool:
	if rid == _rid:
		return false
	_rid = rid
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and not tree.physics_frame.is_connected(_on_step):
		tree.physics_frame.connect(_on_step)
		tree.process_frame.connect(_on_step)
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	return true


## The last frame's CPU time in ms, or -1 when nothing was measured yet.
func cpu_ms() -> float:
	if _game_ms < 0.0 or not _rid.is_valid():
		return -1.0
	return _game_ms + RenderingServer.viewport_get_measured_render_time_cpu(_rid) + RenderingServer.get_frame_setup_time_cpu()


func _on_step() -> void:
	if _start < 0:
		_start = Time.get_ticks_usec()


func _on_pre_draw() -> void:
	if _start >= 0:
		_game_ms = float(Time.get_ticks_usec() - _start) / 1000.0
	_start = -1
