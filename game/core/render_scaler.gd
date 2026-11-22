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
## Where the driver reports no GPU time (no timestamps) the frame time stands in for the GPU time (feed_any).
## With vsync on a frame that kept its refresh slot only says "fast enough", so it counts as HOLD_LOAD (no step either
## way); one past SLOW x the budget missed its slot and counts as it is. A single frame counts at most HITCH x the
## budget, so a loading hitch does not step the scale down. With vsync on there is no headroom reading, so after a
## step down one step up is tried once 98 % of the frames have kept their slots for BLIND_UP_S; a step down within PROBE_S of
## that try doubles the wait (up to BLIND_UP_MAX_S), so a scale that cannot hold is not tried again and again.
const SLOW := 1.15
const HOLD_LOAD := 0.8
const HITCH := 2.0
const BLIND_UP_S := 20.0
const BLIND_UP_MAX_S := 160.0
const PROBE_S := 10.0
const BLIND_SLOW_SHARE := 0.02  # at most this share of missed slots over the wait for a blind step up

var scale := 1.0
var top := 1.0  # the preset's own scale: never above it

var _sum := 0.0
var _n := 0
var _t := 0.0
var _calm := 0.0
var blind_hold := BLIND_UP_S  # current wait before a blind step up (frame-time fallback with vsync)
var _blind_calm := 0.0
var _blind_n := 0
var _blind_slow := 0
var _since_up := INF  # seconds since the last blind step up


## A new preset or a fresh start: back to the preset's scale and forget the measurements.
func reset(top_scale: float) -> void:
	top = top_scale
	scale = top_scale
	_sum = 0.0
	_n = 0
	_t = 0.0
	_calm = 0.0
	blind_hold = BLIND_UP_S
	_blind_reset()
	_since_up = INF


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


## One frame from whatever timing the driver gives: its GPU time when it reports one (feed), else the frame time
## (frame_ms, the time since the last frame) through frame_load_ms, with blind steps up under vsync. The same rule on
## every machine: only the presence of a GPU reading decides, never the brand or OS.
func feed_any(gpu_ms: float, frame_ms: float, budget_ms: float, vsync: bool, dt: float) -> bool:
	if gpu_ms > 0.0:
		return feed(gpu_ms, budget_ms, dt)
	var was := scale
	_since_up += dt
	if feed(frame_load_ms(frame_ms, budget_ms, vsync), budget_ms, dt):
		if scale < was:
			if _since_up < PROBE_S:  # the last blind try could not hold: wait longer before the next
				blind_hold = minf(blind_hold * 2.0, BLIND_UP_MAX_S)
			_blind_reset()
		return true
	if not vsync or frame_ms <= 0.0 or budget_ms <= 0.0:
		return false
	_blind_calm += dt
	_blind_n += 1
	if frame_ms > budget_ms * SLOW:
		_blind_slow += 1
	if _blind_calm < blind_hold or scale >= top - 0.001:
		return false
	var steady := _blind_slow <= int(float(_blind_n) * BLIND_SLOW_SHARE)  # a few hitches allowed, not a slow scene
	_blind_reset()
	if not steady:
		return false
	scale = minf(top, scale + STEP)
	_since_up = 0.0
	return true


func _blind_reset() -> void:
	_blind_calm = 0.0
	_blind_n = 0
	_blind_slow = 0


## The load one frame counts for when there is no GPU time (see SLOW, HOLD_LOAD, HITCH).
static func frame_load_ms(frame_ms: float, budget_ms: float, vsync: bool) -> float:
	var ms := minf(frame_ms, budget_ms * HITCH)
	if vsync and ms <= budget_ms * SLOW:
		return budget_ms * HOLD_LOAD
	return ms
