extends Node
## The full-screen loader plays a scenic clip and names the place. A short wait stays a dim veil.


const TITLES := ["Mumbai  ·  evening final", "The Western Ghats", "The Juhu coast"]


func teardown() -> void:
	for n in get_children():
		n.free()


func test_flight_loader_stays_until_the_airfield_is_in() -> String:
	var flight: GDScript = load("res://world/flight.gd")
	if not flight.loader_holds(0, true, 0.2, false):
		return "the film should cover a flight whose airfield is still building"
	if flight.loader_holds(3, false, 1.0, false):
		return "the film should lift once the ground and the airfield are in"
	if flight.loader_holds(0, true, 0.2, true) or flight.loader_holds(0, true, 13.0, false):
		return "a blocked run, and a wait past 12 s, should not hold the film"
	return ""


func test_ffmpeg_probe_does_not_need_a_working_binary() -> String:
	var ok := SessionRecorder.ffmpeg_available()
	if SessionRecorder.ffmpeg_available() != ok:
		return "the ffmpeg probe should be cached"
	return ""


func test_loader_film_decodes_a_frame() -> String:
	if not LoaderFilm.available():
		return "missing res://ui/loader/a320_final/00.jpg"
	var film := LoaderFilm.new()
	add_child(film)
	film.restart()
	if not TITLES.has(film.caption):
		return "caption '%s'" % film.caption
	var tex := film.texture as Texture2D
	if tex == null or tex.get_width() < 640 or tex.get_height() < 360:
		return "frame did not decode"
	return ""


func test_scenic_loader_names_the_place() -> String:
	var veil := BusyOverlay.new()
	add_child(veil)
	veil.show_busy("Loading the flight…", true)
	var film := _film(veil)
	if film == null or not film.visible:
		return "a full-screen load should play the film"
	if _dim(veil).visible:
		return "the dim veil should step aside for the film"
	if not TITLES.has(film.caption):
		return "place '%s'" % film.caption
	var credit := ""
	for n in veil.get_children():
		if n is Label and str(n.text).contains("OpenStreetMap"):
			credit = n.text
	if credit == "":
		return "the data attribution should stay on the film"
	veil.show_busy("Painting the aircraft…")
	if film.visible or _dim(veil) == null or not _dim(veil).visible:
		return "a short wait stays a plain veil"
	return ""


func _film(veil: Node) -> LoaderFilm:
	for n in veil.get_children():
		if n is LoaderFilm:
			return n
	return null


func _dim(veil: Node) -> ColorRect:
	for n in veil.get_children():
		if n is ColorRect:
			return n
	return null
