extends HBoxContainer
## Start screen page 5: session recording. Records the whole flight (picture + sound)
## to a folder you choose (default: recordings/ in the game folder). F8 in flight
## starts / stops it at any time.

signal changed

var _dir: Label
var _dialog: FileDialog
var _size_note: Label


func _ready() -> void:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var s: Dictionary = Session.setup
	v.add_child(MenuTheme.heading("Session recording"))
	var en := CheckBox.new()
	en.text = "Record this flight (video + sound)"
	en.button_pressed = bool(s.record)
	en.toggled.connect(func(on):
		s.record = on
		changed.emit())
	v.add_child(en)
	var fh := HBoxContainer.new()
	v.add_child(fh)
	var fl := Label.new()
	fl.text = "Save to:"
	fh.add_child(fl)
	_dir = Label.new()
	_dir.size_flags_horizontal = SIZE_EXPAND_FILL
	_dir.clip_text = true
	fh.add_child(_dir)
	var choose := Button.new()
	choose.text = "Choose folder…"
	choose.pressed.connect(func(): _dialog.popup_centered_ratio(0.6))
	fh.add_child(choose)
	var reset := Button.new()
	reset.text = "Game folder"
	reset.pressed.connect(func():
		s.record_dir = ""
		_update())
	fh.add_child(reset)
	var open := Button.new()
	open.text = "Open folder"
	open.pressed.connect(func():
		var d := _folder()
		DirAccess.make_dir_recursive_absolute(d)
		OS.shell_open(d))
	fh.add_child(open)
	var g := GridContainer.new()
	g.columns = 2
	v.add_child(g)
	_option(g, "Resolution", [["720p", 720], ["1080p", 1080], ["Native window", 0]], "record_height")
	_option(g, "Frame rate", [["30 fps", 30], ["24 fps", 24], ["60 fps", 60]], "record_fps")
	var mp4 := CheckBox.new()
	mp4.text = "Convert to MP4 when the recording stops (needs ffmpeg)"
	mp4.button_pressed = bool(s.record_mp4)
	mp4.toggled.connect(func(on): s.record_mp4 = on)
	v.add_child(mp4)
	var ff := MenuTheme.note("ffmpeg found: recordings become small MP4 files (H.264 + AAC)." if SessionRecorder.ffmpeg_available()
		else "ffmpeg not found: recordings stay as .mkv (MJPEG + PCM), which plays in VLC / mpv and opens in any editor. Install ffmpeg for small MP4 files.")
	v.add_child(ff)
	_size_note = MenuTheme.note("")
	v.add_child(_size_note)
	v.add_child(MenuTheme.note("Recording starts when the flight starts. In flight: F8 starts / stops, and a red ● REC shows the time and size. The file is free-sim_<date>_<time>.mkv and stays playable even if the game is closed abruptly. Capturing costs some frame rate (mostly at 1080p / 60 fps)."))
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Folder for recordings"
	_dialog.dir_selected.connect(func(d):
		s.record_dir = d
		_update())
	add_child(_dialog)
	_update()


func _folder() -> String:
	var d: String = Session.setup.record_dir
	return d if d != "" else SessionRecorder.default_dir()


func _option(g: GridContainer, label: String, items: Array, key: String) -> void:
	var l := Label.new()
	l.text = label
	g.add_child(l)
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(it[0])
		if int(Session.setup[key]) == it[1]:
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i):
		Session.setup[key] = items[i][1]
		_update())
	g.add_child(ob)


func _update() -> void:
	_dir.text = _folder() + ("" if Session.setup.record_dir != "" else "   (game folder)")
	var h := int(Session.setup.record_height)
	var mb_s: float = {720: 5.0, 1080: 10.0, 0: 10.0}.get(h, 6.0) * float(Session.setup.record_fps) / 30.0
	_size_note.text = "Raw .mkv size ≈ %.0f MB per minute (≈ %.0f GB per hour); the MP4 is about 10–20x smaller." % [mb_s * 60.0, mb_s * 3.6]
	changed.emit()
