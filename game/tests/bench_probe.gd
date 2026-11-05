class_name BenchProbe
extends RefCounted
## Frame-time measurement for tools/bench.sh (through tests/debug_showcase.gd --bench=<s>). Everything in ms.
## Vsync is switched off while measuring (DisplayServer, Engine.max_fps = 0); bench.sh also passes --disable-vsync, but on macOS
## 4.7.2 that flag is ignored when another option follows it, so the run-time switch is what counts.
## GPU: the viewport's render-time query (RenderingServer.viewport_get_measured_render_time_gpu). Godot 4.7's Metal driver has no
## timestamp queries, so on macOS / Metal the GPU columns are "n/a"; bench.sh DRIVER=vulkan (MoltenVK) gives real GPU times.
## CPU: main-thread work per frame: from the first physics / process step of a frame to the start of drawing (scripts, physics,
## property tree) plus the renderer's CPU time for viewport and frame setup (viewport_get_measured_render_time_cpu,
## get_frame_setup_time_cpu). Waiting for vsync or the GPU is not counted. (Performance TIME_PROCESS is not usable: it is the
## worst frame of the last second, waits included.)

## Per-frame timestamps, written by the signal handlers below (main thread).
class _Clock:
	var frame_start := -1  # usec, first physics / process step of the frame being built
	var game_us: Array[float] = []  # per frame: frame_start .. frame_pre_draw

	func on_step() -> void:
		if frame_start < 0:
			frame_start = Time.get_ticks_usec()

	func on_pre_draw() -> void:
		if frame_start >= 0:
			game_us.append(float(Time.get_ticks_usec() - frame_start))
		frame_start = -1


## Samples `secs` seconds of frames after `warm` frames of warm-up; returns
## {frames, fps, ms_avg, ms_p95, ms_p99, gpu_avg, gpu_p95 (-1 = not available), cpu_avg}.
static func measure(n: Node, secs: float, warm := 30) -> Dictionary:
	var vp := n.get_viewport()
	var rid := vp.get_viewport_rid()
	var tree := n.get_tree()
	var vsync := DisplayServer.window_get_vsync_mode()
	var max_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for i in warm:
		await tree.process_frame
	var clock := _Clock.new()
	tree.physics_frame.connect(clock.on_step)
	tree.process_frame.connect(clock.on_step)
	RenderingServer.frame_pre_draw.connect(clock.on_pre_draw)
	var ft: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var start := Time.get_ticks_usec()
	var last := start
	while float(Time.get_ticks_usec() - start) < secs * 1e6:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		ft.append(float(now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		var game: float = clock.game_us.back() / 1000.0 if not clock.game_us.is_empty() else 0.0
		cpu.append(game + RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu())
	tree.physics_frame.disconnect(clock.on_step)
	tree.process_frame.disconnect(clock.on_step)
	RenderingServer.frame_pre_draw.disconnect(clock.on_pre_draw)
	RenderingServer.viewport_set_measure_render_time(rid, false)
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	ft.remove_at(0)  # the first sample started mid-frame
	var total := 0.0
	for v in ft:
		total += v
	var has_gpu := gpu.any(func(v: float) -> bool: return v > 0.0)
	return {"frames": ft.size(), "fps": ft.size() / maxf(total / 1000.0, 1e-3), "ms_avg": _mean(ft), "ms_p95": _pct(ft, 0.95),
		"ms_p99": _pct(ft, 0.99), "gpu_avg": _mean(gpu) if has_gpu else -1.0, "gpu_p95": _pct(gpu, 0.95) if has_gpu else -1.0,
		"cpu_avg": _mean(cpu)}


## One line for the log, parsed by tools/bench.sh ("n/a" where the GPU time is not available).
static func line(scene: String, preset: String, renderer: String, r: Dictionary) -> String:
	return "BENCH scene=%s preset=%s renderer=%s driver=%s fps=%.1f ms_avg=%.2f ms_p95=%.2f ms_p99=%.2f gpu_avg=%s gpu_p95=%s cpu_avg=%.2f frames=%d" % [
		scene, preset, renderer, RenderingServer.get_current_rendering_driver_name(), r.fps, r.ms_avg, r.ms_p95, r.ms_p99,
		_ms(r.gpu_avg), _ms(r.gpu_p95), r.cpu_avg, r.frames]


static func _ms(v: float) -> String:
	return "n/a" if v < 0.0 else "%.2f" % v


static func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _pct(a: Array[float], p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(p * (b.size() - 1)), 0, b.size() - 1)]
