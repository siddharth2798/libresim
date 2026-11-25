class_name BenchPasses
extends RefCounted
## GPU time of the end of the 3D frame for tools/bench.sh (BenchProbe): the renderer's own timestamps (RENDER_TIMESTAMP, what the
## editor's visual profiler shows) of the last finished frame, read from the RenderingDevice. Godot records them only with
## --gpu-profile (or the profiler running) and only on drivers with timestamp queries (Vulkan / MoltenVK, Direct3D 12; not Godot 4.7's
## Metal driver). "post" = first Tonemap timestamp .. end of the 3D scene: tonemap (with FXAA inside it), SMAA and the copy that
## scales a reduced render to the screen; "smaa" = the SMAA timestamp .. the next one. Used for the edge filter costs (core/screen_aa.gd).
## "sky" = Setup Sky .. the next timestamp: mostly the sky's radiance (reflection / ambient) cubemap update (world/sky_params.gd).

const START := "Tonemap"
const END := "< Render 3D Scene"


## Adds the last frame's times (ms) to `acc` ({"post": [sum, frames], "smaa": [sum, frames]}); a frame is counted once.
static func sample(acc: Dictionary) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var frame := rd.get_captured_timestamps_frame()
	if acc.get("_frame", -1) == frame:
		return
	acc["_frame"] = frame
	var n := rd.get_captured_timestamps_count()
	var t0 := -1
	for i in n:
		var name := rd.get_captured_timestamp_name(i)
		var t := rd.get_captured_timestamp_gpu_time(i)  # ns
		if name == START and t0 < 0:
			t0 = t
		elif name == "Setup Sky" and i + 1 < n:
			_add(acc, "sky", float(rd.get_captured_timestamp_gpu_time(i + 1) - t) / 1e6)
		elif name == "SMAA" and i + 1 < n:
			_add(acc, "smaa", float(rd.get_captured_timestamp_gpu_time(i + 1) - t) / 1e6)
		elif name == END and t0 >= 0:
			_add(acc, "post", float(t - t0) / 1e6)
			return


static func _add(acc: Dictionary, key: String, ms: float) -> void:
	var s: Array = acc.get(key, [0.0, 0])
	acc[key] = [s[0] + ms, s[1] + 1]


## "post:0.812,smaa:0.640,sky:0.050" (mean ms per frame), "n/a" without timestamps.
static func text(acc: Dictionary) -> String:
	var out := []
	for k in ["post", "smaa", "sky"]:
		if acc.has(k) and acc[k][1] > 0:
			out.append("%s:%.3f" % [k, acc[k][0] / acc[k][1]])
	return ",".join(out) if not out.is_empty() else "n/a"
