class_name SessionRecorder
extends Label
## Session recording: the whole flight, picture + sound, to
## <folder>/libresim_<date>_<time>.mkv (MJPEG + PCM, see core/mkv_writer.gd).
## Enabled on the start screen (Session.setup.record*); F8 starts / stops in flight.
## Frames are read back on the main thread and JPEG-encoded on worker threads; sound is
## tapped from the Master bus with an AudioEffectCapture. If ffmpeg is installed the
## file is converted to a much smaller MP4 when recording stops.

var recording := false
var path := ""
var _mkv: MkvWriter
var _t0 := 0
var _next_frame := 0.0
var _size := Vector2i.ZERO
var _tasks: Array = []  # [{ms, key, task}] in capture order
var _results := {}  # task id -> PackedByteArray
var _mutex := Mutex.new()
var _cap: AudioEffectCapture
var _cap_idx := -1
var _samples := 0
var _key := 0


func _ready() -> void:
	add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 5)
	add_theme_font_size_override("font_size", 18)
	set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	grow_horizontal = GROW_DIRECTION_BEGIN
	offset_top = 8
	offset_right = -16
	mouse_filter = MOUSE_FILTER_IGNORE
	if Session.setup.get("record", false):
		start.call_deferred()


static func default_dir() -> String:
	var d := Paths.docs_dir().path_join("recordings")  # the game folder
	if DirAccess.make_dir_recursive_absolute(d) == OK and FileAccess.open(d.path_join(".w"), FileAccess.WRITE) != null:
		DirAccess.remove_absolute(d.path_join(".w"))
		return d
	return OS.get_user_data_dir().path_join("recordings")  # read-only install (AppImage, .app)


static func ffmpeg_available() -> bool:
	return OS.execute("ffmpeg", ["-version"], [], false) == 0


func start() -> void:
	if recording:
		return
	var dir: String = Session.setup.get("record_dir", "")
	dir = dir if dir != "" else default_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	path = dir.path_join("libresim_%s.mkv" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_"))
	var vs := Vector2(get_viewport().get_texture().get_size())  # real pixels (the visible rect is in UI units)
	var h := int(Session.setup.get("record_height", 720))
	_size = Vector2i(vs) if h <= 0 or h >= int(vs.y) else Vector2i(int(vs.x * h / vs.y) & ~1, h)
	_mkv = MkvWriter.new()
	if not _mkv.open(path, _size.x, _size.y, AudioServer.get_mix_rate()):
		text = "recording failed: cannot write %s" % dir
		return
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 0.5
	AudioServer.add_bus_effect(0, _cap)
	_cap_idx = AudioServer.get_bus_effect_count(0) - 1
	_t0 = Time.get_ticks_msec()
	_next_frame = 0.0
	_samples = 0
	recording = true


func stop() -> void:
	if not recording:
		return
	recording = false
	_drain(true)
	_mkv.close()
	AudioServer.remove_bus_effect(0, _cap_idx)
	text = "saved %s" % path
	if Session.setup.get("record_mp4", true) and ffmpeg_available():
		var mp4 := path.get_basename() + ".mp4"
		var cmd := "ffmpeg -loglevel error -y -i '%s' -c:v libx264 -preset veryfast -crf 22 -pix_fmt yuv420p -c:a aac -b:a 160k '%s' && rm '%s'" % [path, mp4, path]
		OS.create_process("sh", ["-c", cmd])
		text = "saved %s (converting to MP4…)" % mp4


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_F8:
		if recording:
			stop()
		else:
			start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		stop()


func _process(_dt: float) -> void:
	if not recording:
		return
	var ms := Time.get_ticks_msec() - _t0
	var fps := float(Session.setup.get("record_fps", 30))
	if ms >= _next_frame:  # real-time frame pacing; a slow frame just repeats less often
		_next_frame = maxf(_next_frame + 1000.0 / fps, ms - 1000.0 / fps)
		_capture(ms)
	_audio()
	_drain(false)
	var s := ms / 1000
	text = "● REC %d:%02d  %.0f MB  (F8 stop)" % [s / 60, s % 60, _mkv.bytes_written / 1.0e6]


## Grab the frame without stalling the GPU: async read-back of the viewport texture
## (RenderingDevice), then resize + JPEG-encode on a worker thread.
func _capture(ms: int) -> void:
	var entry := {"ms": ms, "key": _key, "task": -1}
	_key += 1
	_tasks.append(entry)
	var rd := RenderingServer.get_rendering_device()
	var tex := RenderingServer.texture_get_rd_texture(get_viewport().get_texture().get_rid()) if rd else RID()
	var fmt := rd.texture_get_format(tex) if tex.is_valid() else null
	var rgba8: bool = fmt != null and fmt.format in [RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB]
	if not rgba8:  # e.g. Compatibility renderer: synchronous fallback
		_encode(entry, get_viewport().get_texture().get_image())
		return
	var w: int = fmt.width
	var h: int = fmt.height
	rd.texture_get_data_async(tex, 0, func(data: PackedByteArray):
		if recording:
			_encode(entry, Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)))


func _encode(entry: Dictionary, img: Image) -> void:
	var sz := _size
	var key: int = entry.key
	entry.task = WorkerThreadPool.add_task(func():
		if img.get_size() != sz:
			img.resize(sz.x, sz.y, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGB8)
		var jpg := img.save_jpg_to_buffer(0.72)
		_mutex.lock()
		_results[key] = jpg
		_mutex.unlock())


## Write finished frames in capture order (at stop: frames still on the GPU are dropped).
func _drain(all: bool) -> void:
	while not _tasks.is_empty():
		var t: Dictionary = _tasks[0]
		if t.task < 0:
			if not all:
				return
			_tasks.pop_front()
			continue
		if not WorkerThreadPool.is_task_completed(t.task) and not all:
			return
		WorkerThreadPool.wait_for_task_completion(t.task)
		_tasks.pop_front()
		_mutex.lock()
		var jpg: PackedByteArray = _results.get(t.key, PackedByteArray())
		_results.erase(t.key)
		_mutex.unlock()
		if not jpg.is_empty():
			_mkv.add(1, t.ms, jpg)


func _audio() -> void:
	var n := _cap.get_frames_available()
	if n <= 0:
		return
	var buf := _cap.get_buffer(n)
	var pcm := PackedByteArray()
	pcm.resize(n * 4)
	for i in n:
		var v: Vector2 = buf[i]
		pcm.encode_s16(i * 4, int(clampf(v.x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(i * 4 + 2, int(clampf(v.y, -1.0, 1.0) * 32767.0))
	_mkv.add(2, int(_samples * 1000.0 / AudioServer.get_mix_rate()), pcm)
	_samples += n
