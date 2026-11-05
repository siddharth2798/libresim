extends HBoxContainer
## Start screen step 6 (optional): session recording. Records the whole flight (picture + sound) to a folder you
## choose (default: recordings/ in the game folder). F8 in flight starts / stops it at any time. Left: the "Record
## this flight" switch, the folder, resolution and frame rate (segmented), the MP4 switch and a size line; right: a
## "What you get" card. The options stay usable while recording is off (F8 can still start it in flight), they are
## only dimmed. Setup keys (unchanged): record, record_dir, record_height, record_fps, record_mp4.

signal changed

const RESOLUTIONS := [[720, "720p"], [1080, "1080p"], [0, "Native window"]]
const RATES := [[24, "24 fps"], [30, "30 fps"], [60, "60 fps"]]
const GET_CARD := [
	"Files are named libresim_<date>_<time>.mkv (MJPEG video, 16-bit PCM sound), written by the game itself: no extra software needed.",
	"Crash-safe: the file is written as a stream, so it stays playable even if the game is killed.",
	"Frames are encoded on worker threads: frame rate is barely affected.",
	"Read-only installs fall back to the game's user-data folder, in recordings/.",
]

var record_switch: SwitchRow
var mp4_switch: SwitchRow
var resolution: Segmented
var rate: Segmented
var _dir: Label
var _dialog: FileDialog
var _size_note: Label
var _options: VBoxContainer
var _ffmpeg := false  # looked up once: it starts a process


## MB per minute of the .mkv for a height (720 / 1080 / 0 = native) and frame rate (about 5 MB/s at 720p30).
static func mb_per_minute(height: int, fps: int) -> float:
	return {720: 5.0, 1080: 10.0, 0: 10.0}.get(height, 6.0) * float(fps) / 30.0 * 60.0


func _ready() -> void:
	_ffmpeg = SessionRecorder.ffmpeg_available()
	add_theme_constant_override("separation", 20)
	var s: Dictionary = Session.setup
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(380, 0)
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	record_switch = SwitchRow.new().setup("Record this flight (video + sound)",
		"Starts with the flight. In flight F8 starts / stops it and a red REC shows the time and size. Capturing costs some frame rate, mostly at 1080p / 60 fps.",
		bool(s.record))
	record_switch.tooltip_text = "Recording starts when the flight starts. In flight, F8 starts / stops it."
	record_switch.toggled.connect(func(on):
		s.record = on
		_dim()
		changed.emit())
	left.add_child(record_switch)
	left.add_child(HSeparator.new())
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 12)
	left.add_child(_options)
	_build_folder(_options)
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	_options.add_child(g)
	resolution = _choice(g, "Resolution", RESOLUTIONS, "record_height")
	rate = _choice(g, "Frame rate", RATES, "record_fps")
	mp4_switch = SwitchRow.new().setup("Convert to MP4 when the recording stops",
		"Needs ffmpeg. " + ("ffmpeg found: small MP4 files (H.264 + AAC)." if _ffmpeg
		else "ffmpeg not found: recordings stay .mkv (MJPEG + PCM), which plays in VLC / mpv. Install ffmpeg for small MP4 files."),
		bool(s.record_mp4))
	mp4_switch.toggled.connect(func(on): s.record_mp4 = on)
	_options.add_child(mp4_switch)
	_size_note = MenuTheme.note("")
	_options.add_child(_size_note)
	add_child(_card())
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Folder for recordings"
	_dialog.dir_selected.connect(func(d):
		s.record_dir = d
		_update())
	add_child(_dialog)
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	refresh()


## Repaint from Session.setup (shown again after the setup was replaced, e.g. Fly again).
func refresh() -> void:
	var s: Dictionary = Session.setup
	record_switch.set_on(bool(s.record))
	mp4_switch.set_on(bool(s.record_mp4))
	resolution.select(int(s.record_height))
	rate.select(int(s.record_fps))
	_dim()
	_update()


## "Where it is saved": the folder in a dark box, then Choose folder, Game folder, Open folder.
func _build_folder(parent: Control) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	col.add_child(MenuTheme.heading("Where it is saved"))
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", PageStyles.inset())
	col.add_child(box)
	_dir = Label.new()
	_dir.clip_text = true
	_dir.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_dir)
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	col.add_child(bar)
	for item in [["Choose folder…", _choose_folder], ["Game folder", _game_folder], ["Open folder", _open_folder]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		bar.add_child(b)


func _choose_folder() -> void:
	_dialog.popup_centered_ratio(0.6)


func _game_folder() -> void:
	Session.setup.record_dir = ""
	_update()


func _open_folder() -> void:
	var d := _folder()
	DirAccess.make_dir_recursive_absolute(d)
	OS.shell_open(d)


func _choice(parent: Control, title: String, items: Array, key: String) -> Segmented:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	col.add_child(MenuTheme.heading(title))
	var seg := Segmented.new()
	seg.set_options(items, int(Session.setup[key]))
	seg.selected.connect(func(v):
		Session.setup[key] = int(v)
		_update())
	col.add_child(seg)
	return seg


func _card() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(300, 0)
	p.size_flags_vertical = SIZE_SHRINK_BEGIN
	p.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.35, 0.75, 1.0, 0.07), 12, Color(MenuTheme.ACCENT, 0.35), 16.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(MenuTheme.heading("What you get"))
	for t in GET_CARD:
		var l := Label.new()
		l.text = "•  " + t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(260, 0)
		v.add_child(l)
	return p


func _folder() -> String:
	var d: String = Session.setup.record_dir
	return d if d != "" else SessionRecorder.default_dir()


func _dim() -> void:
	_options.modulate.a = 1.0 if bool(Session.setup.record) else 0.6


func _update() -> void:
	_dir.text = _folder() + ("" if Session.setup.record_dir != "" else "   (game folder)")
	_size_note.text = "About %.0f MB per minute as .mkv%s." % [mb_per_minute(int(Session.setup.record_height), int(Session.setup.record_fps)),
		"; the MP4 is 10-20x smaller" if _ffmpeg else " (no ffmpeg: no MP4 conversion)"]
	changed.emit()
