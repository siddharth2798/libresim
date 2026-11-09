class_name LoaderFilm
extends TextureRect
## Scenic frames behind a loading screen, the way a flight sim plays a film while the
## world streams in. The clips are short camera moves shot at the Max preset
## (tests/debug_showcase.gd --film=). Each frame is the imported texture, loaded
## on its own so an export can play it and only one frame stays in memory.


const FPS := 24.0  # the clips are shot at this rate with game time locked to it (tools/shoot_loader_films.sh)
const AIRCRAFT: Array[String] = ["a320", "c172"]
const PLACES: Array[String] = ["ghats", "cochin", "gate"]
const TITLES := {"ghats": "The Western Ghats", "cochin": "Cochin  ·  approach", "gate": "At the gate  ·  Kochi"}
## One clip per aircraft and place, aircraft-major: index = aircraft * PLACES.size() + place.
static var CLIPS: Array = _clips()
## Kochi (VOCI, VOCC) plays the Cochin approach, a stand start the gate, everywhere else the Ghats (the Mumbai
## approach clips were dropped).
const COCHIN_AIRPORTS: Array[String] = ["VOCI", "VOCC"]

var caption := ""
var _clip := 0
var _frame := 0
var _acc := 0.0
var _count := 0
var _hold: bool = false  # a flight keeps its clip; a menu load moves on when the clip ends


static func available() -> bool:
	return ResourceLoader.exists(CLIPS[0].dir + "/000.jpg")


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


## Which clip a flight opens on: the aircraft's own clips (an A320, else the Cessna's), at the place it starts.
static func clip_for(aircraft: String, airport: String, start: String = "") -> int:
	var a := 0 if aircraft.to_lower().begins_with("a320") else 1
	var place := "ghats"
	if start == "stand":
		place = "gate"
	elif COCHIN_AIRPORTS.has(airport.to_upper()):
		place = "cochin"
	return a * PLACES.size() + PLACES.find(place)


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
	_acc = 0.0
	_frame += 1
	if _frame >= _count:
		if not _hold:
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
	var res: Resource = ResourceLoader.load("%s/%03d.jpg" % [dir, _frame], "", ResourceLoader.CACHE_MODE_IGNORE)
	var tex := res as Texture2D
	if tex == null:
		return
	texture = tex
	caption = str(CLIPS[_clip].title)


func _frames(dir: String) -> int:
	var n := 0
	while ResourceLoader.exists("%s/%03d.jpg" % [dir, n]):
		n += 1
	return n
