class_name LoaderFilm
extends TextureRect
## Scenic frames behind a loading screen, the way a flight sim plays a film while the
## world streams in. The clips are short camera moves shot at the Max preset
## (tests/debug_showcase.gd --film=). One JPEG is decoded at a time.


const FPS := 15.0
const CLIPS := [
	{"dir": "res://ui/loader/a320_final", "title": "Mumbai  ·  evening final"},
	{"dir": "res://ui/loader/ghats_chase", "title": "The Western Ghats"},
	{"dir": "res://ui/loader/coast_juhu", "title": "The Juhu coast"},
]

var caption := ""
var _clip := 0
var _frame := 0
var _acc := 0.0
var _count := 0
var _tex: ImageTexture


static func available() -> bool:
	return ResourceLoader.exists(CLIPS[0].dir + "/00.jpg") or FileAccess.file_exists(CLIPS[0].dir + "/00.jpg")


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	expand_mode = EXPAND_IGNORE_SIZE
	stretch_mode = STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_tex = ImageTexture.new()
	texture = _tex


## Start at a clip (a different one each time the loader appears).
func restart() -> void:
	if CLIPS.is_empty():
		return
	_clip = randi() % CLIPS.size()
	_show_frame(0)


func _process(dt: float) -> void:
	if not visible or _count < 2:
		return
	_acc += dt
	if _acc < 1.0 / FPS:
		return
	_acc = 0.0
	_frame += 1
	if _frame >= _count:
		_clip = (_clip + 1) % CLIPS.size()
		_show_frame(0)
	else:
		_show_frame(_frame)


func _show_frame(i: int) -> void:
	var dir := ""
	var hops := 0
	while hops < CLIPS.size():
		dir = str(CLIPS[_clip].dir)
		_count = _frames(dir)
		if _count > 0:
			break
		_clip = (_clip + 1) % CLIPS.size()
		hops += 1
	if _count == 0:
		return
	_frame = i % _count
	var img := Image.new()
	if img.load("%s/%02d.jpg" % [dir, _frame]) != OK:
		return
	if _tex.get_width() != img.get_width() or _tex.get_height() != img.get_height():
		_tex.set_image(img)
	else:
		_tex.update(img)
	caption = str(CLIPS[_clip].title)
	texture = _tex


func _frames(dir: String) -> int:
	var n := 0
	while FileAccess.file_exists("%s/%02d.jpg" % [dir, n]):
		n += 1
	return n
