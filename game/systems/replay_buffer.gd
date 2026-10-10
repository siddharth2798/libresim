class_name ReplayBuffer
extends RefCounted
## Fixed-capacity ring buffer of replay frames in packed arrays (no per-frame objects).
## A frame = time (s, float64) + world ENU position (east, north, up; float64, so
## ±500 km stays mm-exact) + `stride` float32 channels. Each channel has a kind
## that says how to interpolate it between frames (see the K_* constants).

const K_LERP := 0  # linear
const K_STEP := 1  # held: value of the earlier frame (bools, ints, switch positions)
const K_ANG_RAD := 2  # angle in radians, shortest-way lerp
const K_ANG_DEG := 3  # angle in degrees, shortest-way lerp
const K_QUAT := 4  # first of 4 channels x, y, z, w: slerp (the next 3 are K_QUAT_REST)
const K_QUAT_REST := 5

var capacity: int
var stride: int
var kinds: PackedByteArray
var _t := PackedFloat64Array()
var _pos := PackedFloat64Array()
var _f := PackedFloat32Array()
var _head := 0  # physical index of the oldest frame
var _count := 0


func _init(channel_kinds: PackedByteArray, seconds := 600.0, rate_hz := 20.0) -> void:
	kinds = channel_kinds
	stride = kinds.size()
	capacity = maxi(int(ceil(seconds * rate_hz)), 2)
	_t.resize(capacity)
	_pos.resize(capacity * 3)
	_f.resize(capacity * stride)


func size() -> int:
	return _count


func clear() -> void:
	_head = 0
	_count = 0


## Approximate memory held by the arrays (bytes).
func memory_bytes() -> int:
	return capacity * (8 + 24 + 4 * stride)


func start_time() -> float:
	return _t[_head] if _count > 0 else 0.0


func end_time() -> float:
	return _t[_phys(_count - 1)] if _count > 0 else 0.0


func duration() -> float:
	return end_time() - start_time()


func time_at(i: int) -> float:
	return _t[_phys(i)]


## Append a frame; overwrites the oldest one when full. Times must increase.
func push(t: float, east: float, north: float, up: float, ch: PackedFloat32Array) -> void:
	var p: int
	if _count < capacity:
		p = _phys(_count)
		_count += 1
	else:
		p = _head
		_head = (_head + 1) % capacity
	_t[p] = t
	_pos[p * 3] = east
	_pos[p * 3 + 1] = north
	_pos[p * 3 + 2] = up
	var o := p * stride
	for i in stride:
		_f[o + i] = ch[i]


## Drop every frame later than t (take control from a past point).
func truncate_after(t: float) -> void:
	while _count > 0 and _t[_phys(_count - 1)] > t:
		_count -= 1


## Interpolated frame at time t (clamped to the recorded span):
## {"t": float, "pos": PackedFloat64Array [e, n, u], "ch": PackedFloat32Array}.
func sample(t: float) -> Dictionary:
	if _count == 0:
		return {}
	t = clampf(t, start_time(), end_time())
	var i := _index_before(t)
	var j := mini(i + 1, _count - 1)
	var a := _phys(i)
	var b := _phys(j)
	var span := _t[b] - _t[a]
	var u := clampf((t - _t[a]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var pos := PackedFloat64Array([0.0, 0.0, 0.0])
	for k in 3:
		pos[k] = lerpf(_pos[a * 3 + k], _pos[b * 3 + k], u)
	return {"t": t, "pos": pos, "ch": _blend(a * stride, b * stride, u)}


## World position (e, n, u) at time t, without the channels.
func position_at(t: float) -> Vector3:
	var s := sample(t)
	return Vector3(s.pos[0], s.pos[1], s.pos[2]) if not s.is_empty() else Vector3.ZERO


## Velocity (ENU, m/s) estimated by a central difference of the recorded track
## over +-h seconds (one-sided at the ends).
func velocity_estimate(t: float, h := 0.1) -> Vector3:
	if _count < 2:
		return Vector3.ZERO
	var t0 := maxf(t - h, start_time())
	var t1 := minf(t + h, end_time())
	if t1 <= t0:
		return Vector3.ZERO
	var p0: PackedFloat64Array = sample(t0).pos
	var p1: PackedFloat64Array = sample(t1).pos
	return Vector3(p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]) / (t1 - t0)


func _phys(i: int) -> int:
	return (_head + i) % capacity


## Largest logical index whose time <= t (binary search).
func _index_before(t: float) -> int:
	var lo := 0
	var hi := _count - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _t[_phys(mid)] <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _blend(oa: int, ob: int, u: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(stride)
	var i := 0
	while i < stride:
		var x: float = _f[oa + i]
		var y: float = _f[ob + i]
		match kinds[i]:
			K_LERP:
				out[i] = lerpf(x, y, u)
			K_STEP:
				out[i] = x if u < 1.0 else y
			K_ANG_RAD:
				out[i] = lerp_angle(x, y, u)
			K_ANG_DEG:
				out[i] = rad_to_deg(lerp_angle(deg_to_rad(x), deg_to_rad(y), u))
			K_QUAT:
				var qa := Quaternion(x, _f[oa + i + 1], _f[oa + i + 2], _f[oa + i + 3]).normalized()
				var qb := Quaternion(y, _f[ob + i + 1], _f[ob + i + 2], _f[ob + i + 3]).normalized()
				var q := qa.slerp(qb, u)
				out[i] = q.x; out[i + 1] = q.y; out[i + 2] = q.z; out[i + 3] = q.w
				i += 3
			_:
				out[i] = lerpf(x, y, u)
		i += 1
	return out
