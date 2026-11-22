class_name LoaderFilm
extends TextureRect
## Scenic frames behind a loading screen, the way a flight sim plays a film while the
## world streams in. The clips are short camera moves shot at the Max preset
## (tests/debug_showcase.gd --film=). Each frame is its JPG, decoded on a worker one frame
## ahead (LoaderFrames) into one ImageTexture, so only a frame or two stay in memory.


const FPS := 24.0  # the clips are shot at this rate with game time locked to it (tools/shoot_loader_films.sh)
const AIRCRAFT: Array[String] = ["a320", "c172"]
const PLACES: Array[String] = ["ghats", "gate"]
const TITLES := {"ghats": "The Western Ghats", "gate": "At the gate  ·  Kochi"}
## One clip per aircraft and place, aircraft-major: index = aircraft * PLACES.size() + place.
static var CLIPS: Array = _clips()
## A stand start plays the gate, everything else the Ghats (the Mumbai and Cochin approach clips were dropped).

var caption := ""
var _clip := 0
var _frame := 0
var _acc := 0.0
var _count := 0
var _hold: bool = false  # a flight stays with its aircraft's clips; either way the next clip plays when one ends
var _src := LoaderFrames.new()
var _tex: ImageTexture


static func available() -> bool:
	return FileAccess.file_exists(LoaderFrames.path(CLIPS[0].dir, 0))


static func _clips() -> Array:
	var out := []
	for a in AIRCRAFT:
		for p in PLACES:
			out.append({"dir": "res://ui/loader/%s_%s" % [a, p], "title": TITLES[p], "aircraft": a, "place": p})
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	expand_mode = EXPAND_IGNORE_SIZE
	stretch_mode = STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


## Which clip a flight opens on: the aircraft's own clips (an A320, else the Cessna's), by how it starts.
## `airport` is kept for callers; no clip depends on it now.
static func clip_for(aircraft: String, _airport: String, start: String = "") -> int:
	var a := 0 if aircraft.to_lower().begins_with("a320") else 1
	var place := "gate" if start == "stand" else "ghats"
	return a * PLACES.size() + PLACES.find(place)


## The clip after `clip`. A clip never repeats at once: a flight load moves on within its own aircraft's clips,
## a menu load through all of them.
static func next_clip(clip: int, same_aircraft: bool) -> int:
	if not same_aircraft:
		return (clip + 1) % CLIPS.size()
	var n := PLACES.size()
	return (clip / n) * n + (clip % n + 1) % n


## Menu load, or any wait with no flight: a different clip each time, then the next when it ends.
func restart() -> void:
	if CLIPS.is_empty():
		return
	_hold = false
	_clip = randi() % CLIPS.size()
	_show_frame(0)


## Flight load: the clip for this aircraft and airport, held for the whole wait.
func restart_for(aircraft: String, airport: String, start: String = "") -> void:
	if CLIPS.is_empty():
		return
	_hold = true
	_clip = clip_for(aircraft, airport, start) % CLIPS.size()
	_show_frame(0)


func _process(dt: float) -> void:
	if not visible or _count < 2:
		return
	_acc += dt
	if _acc < 1.0 / FPS:
		return
	var clip := _clip
	var nxt := _frame + 1
	if nxt >= _count:
		clip = next_clip(_clip, _hold)
		nxt = 0
	var img := _src.take(LoaderFrames.path(str(CLIPS[clip].dir), nxt))
	if img == null and nxt > 0:  # still decoding (a busy machine): hold this frame, never wait for it
		_acc = minf(_acc, 1.0 / FPS)
		_src.prefetch(LoaderFrames.path(str(CLIPS[clip].dir), nxt))
		return
	_acc = 0.0
	_clip = clip
	_show_frame(nxt, img)


func _exit_tree() -> void:
	_src.release()


## Frame i of the current clip (the next clip that has frames). img: already decoded, else decoded here.
func _show_frame(i: int, img: Image = null) -> void:
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
	if img == null:
		img = LoaderFrames.decode(LoaderFrames.path(dir, _frame))
	if img == null:
		return
	if _tex != null and _tex.get_size() == Vector2(img.get_size()) and _tex.get_format() == img.get_format():
		_tex.update(img)
	else:
		_tex = ImageTexture.create_from_image(img)
	texture = _tex
	caption = str(CLIPS[_clip].title)
	var last := _frame + 1 >= _count
	_src.prefetch(LoaderFrames.path(str(CLIPS[next_clip(_clip, _hold)].dir) if last else dir, 0 if last else _frame + 1))


func _frames(dir: String) -> int:
	return LoaderFrames.count(dir)
