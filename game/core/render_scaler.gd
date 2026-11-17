class_name RenderScaler
extends RefCounted
## Auto render resolution, the same rule on every machine: the 3D world is drawn at the preset's scale, and only when
## the GPU cannot keep up is it drawn smaller, one step at a time, and brought back once there is room again.
## Input: the measured GPU time of the main viewport (RenderingServer.viewport_get_measured_render_time_gpu) against the
## screen's frame budget (1000 / refresh rate ms). Nothing here looks at the brand, processor or OS. Used by
## Graphics only while Render resolution is Auto (a fixed choice wins); the scale feeds _apply_viewport (below 1:
## FSR2 on Forward+, bilinear on Mobile).

const FLOOR := 0.7  # below this a large frame turns to mush; spend frame rate instead
const STEP := 0.1
const WINDOW_S := 1.5  # GPU time is averaged over this long before deciding
const DOWN_LOAD := 0.92  # mean GPU time above this share of the frame budget: one step down
const UP_LOAD := 0.65  # below this share for UP_HOLD_S: one step up (a step up costs about 1.2x, so no see-saw)
const UP_HOLD_S := 6.0

var scale := 1.0
var top := 1.0  # the preset's own scale: never above it

var _sum := 0.0
var _n := 0
var _t := 0.0
var _calm := 0.0


## A new preset or a fresh start: back to the preset's scale and forget the measurements.
func reset(top_scale: float) -> void:
	top = top_scale
	scale = top_scale
	_sum = 0.0
	_n = 0
	_t = 0.0
	_calm = 0.0


## One frame's GPU time (ms) against the frame budget (ms). True when the scale changed.
func feed(gpu_ms: float, budget_ms: float, dt: float) -> bool:
	if gpu_ms <= 0.0 or budget_ms <= 0.0 or dt <= 0.0:
		return false
	_sum += gpu_ms
	_n += 1
	_t += dt
	if _t < WINDOW_S:
		return false
	var load := (_sum / float(_n)) / budget_ms
	var span := _t
	_sum = 0.0
	_n = 0
	_t = 0.0
	if load > DOWN_LOAD and scale > FLOOR + 0.001:
		scale = maxf(FLOOR, scale - STEP)
		_calm = 0.0
		return true
	_calm = _calm + span if load < UP_LOAD else 0.0
	if _calm >= UP_HOLD_S and scale < top - 0.001:
		scale = minf(top, scale + STEP)
		_calm = 0.0
		return true
	return false


## The spec drawn at `s`: below 1 it is upscaled (FSR2 on Forward+, bilinear on Mobile).
static func at_scale(spec: Dictionary, s: float) -> Dictionary:
	var out := spec.duplicate()
	out.scale = s
	out.fsr = s < 1.0
	return out


## Frame budget (ms) of the screen the window is on; 60 Hz when the system does not say.
static func budget_ms(refresh_hz: float) -> float:
	return 1000.0 / (refresh_hz if refresh_hz > 1.0 else 60.0)
