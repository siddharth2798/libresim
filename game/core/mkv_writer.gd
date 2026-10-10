class_name MkvWriter
extends RefCounted
## Minimal streaming Matroska (.mkv) writer: one MJPEG video track + one 16-bit PCM
## stereo audio track. The Segment has "unknown" size and there is no index, so the
## file is playable at any moment (even if the game crashes mid-recording).
## Blocks are buffered per ~1 s cluster and written in timestamp order.

const UNKNOWN_SIZE := [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
const CLUSTER_MS := 1000

var _f: FileAccess
var _blocks: Array = []  # [ms, track, PackedByteArray]
var _cluster_t := 0
var bytes_written := 0


func open(path: String, width: int, height: int, mix_rate: float) -> bool:
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		return false
	var ebml := _el(0x4286, _uint(1)) + _el(0x42F7, _uint(1)) + _el(0x42F2, _uint(4)) + _el(0x42F3, _uint(8)) \
		+ _el(0x4282, "matroska".to_ascii_buffer()) + _el(0x4287, _uint(4)) + _el(0x4285, _uint(2))
	_write(_el(0x1A45DFA3, ebml))
	_write(_id(0x18538067) + PackedByteArray(UNKNOWN_SIZE))  # Segment, open-ended
	var info := _el(0x2AD7B1, _uint(1000000)) + _el(0x4D80, "free-sim".to_ascii_buffer()) + _el(0x5741, "free-sim".to_ascii_buffer())
	_write(_el(0x1549A966, info))
	var video := _el(0xD7, _uint(1)) + _el(0x73C5, _uint(1)) + _el(0x83, _uint(1)) + _el(0x9C, _uint(0)) \
		+ _el(0x86, "V_MJPEG".to_ascii_buffer()) + _el(0xE0, _el(0xB0, _uint(width)) + _el(0xBA, _uint(height)))
	var audio := _el(0xD7, _uint(2)) + _el(0x73C5, _uint(2)) + _el(0x83, _uint(2)) + _el(0x9C, _uint(0)) \
		+ _el(0x86, "A_PCM/INT/LIT".to_ascii_buffer()) \
		+ _el(0xE1, _el(0xB5, _float(mix_rate)) + _el(0x9F, _uint(2)) + _el(0x6264, _uint(16)))
	_write(_el(0x1654AE6B, _el(0xAE, video) + _el(0xAE, audio)))
	return true


## Queue a frame (track 1 = video JPEG, 2 = audio PCM) at ms since the start.
func add(track: int, ms: int, data: PackedByteArray) -> void:
	_blocks.append([ms, track, data])
	if ms - _cluster_t >= CLUSTER_MS * 2:
		_flush(ms - CLUSTER_MS)  # keep the last second open for late blocks


func close() -> void:
	if _f == null:
		return
	_flush(1 << 40)
	_f.close()
	_f = null


func _flush(before_ms: int) -> void:
	var out: Array = _blocks.filter(func(b): return b[0] < before_ms)
	if out.is_empty():
		return
	_blocks = _blocks.filter(func(b): return b[0] >= before_ms)
	out.sort_custom(func(a, b): return a[0] < b[0])
	var t0: int = out[0][0]
	var body := _el(0xE7, _uint(t0))
	for b in out:
		var rel: int = clampi(b[0] - t0, -32768, 32767)
		var head := PackedByteArray([0x80 | b[1], (rel >> 8) & 0xFF, rel & 0xFF, 0x80])  # keyframe
		if rel > 30000:  # start a new cluster rather than overflow the 16-bit offset
			_write(_el(0x1F43B675, body))
			t0 = b[0]
			body = _el(0xE7, _uint(t0))
			head = PackedByteArray([0x80 | b[1], 0, 0, 0x80])
		body += _el(0xA3, head + b[2])
	_write(_el(0x1F43B675, body))
	_cluster_t = before_ms


func _write(b: PackedByteArray) -> void:
	_f.store_buffer(b)
	bytes_written += b.size()


static func _id(id: int) -> PackedByteArray:
	var b := PackedByteArray()
	var n := 4 if id > 0xFFFFFF else (3 if id > 0xFFFF else (2 if id > 0xFF else 1))
	for i in range(n - 1, -1, -1):
		b.append((id >> (8 * i)) & 0xFF)
	return b


static func _el(id: int, data: PackedByteArray) -> PackedByteArray:
	var size := data.size()
	var sz := PackedByteArray([0x01])  # 8-byte size vint
	for i in range(6, -1, -1):
		sz.append((size >> (8 * i)) & 0xFF)
	return _id(id) + sz + data


static func _uint(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	var n := 1
	while n < 8 and v >> (8 * n) != 0:
		n += 1
	for i in range(n - 1, -1, -1):
		b.append((v >> (8 * i)) & 0xFF)
	return b


static func _float(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	b.reverse()  # Matroska floats are big-endian
	return b
