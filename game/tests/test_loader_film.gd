extends Node
## The full-screen loader plays a scenic clip and names the place. A short wait stays a dim veil.


const TITLES := ["Mumbai  ·  evening final", "The Western Ghats", "The Juhu coast"]


func teardown() -> void:
	for n in get_children():
		n.free()


func test_flight_loader_stays_until_the_airfield_is_in() -> String:
	var flight: GDScript = load("res://world/flight.gd")
	if not flight.loader_holds(0, 0, true, 0.2, false):
		return "the film should cover a flight whose airfield is still building"
	if flight.loader_holds(3, 0, false, 1.0, false):
		return "the film should lift once the ground and the airfield are in"
	if flight.loader_holds(0, 0, true, 0.2, true) or flight.loader_holds(0, 0, true, 13.0, false):
		return "a blocked run, and a wait past 12 s, should not hold the film"
	return ""


## The first coarse terrain node is not the ground: the film lifted at 11 nodes with 32 tiles still loading and the
## terrain popped in for the next 3.5 s.
func test_flight_loader_waits_for_the_finer_tiles() -> String:
	var flight: GDScript = load("res://world/flight.gd")
	if not flight.loader_holds(11, 32, false, 0.5, false):
		return "the film should stay while the view still waits for terrain tiles"
	if flight.loader_holds(476, 0, false, 4.0, false):
		return "the film should lift once no tile is pending"
	if flight.load_percent(0, 0, 0.0) != 0 or flight.load_percent(476, 0, 1.0) != 99 or flight.load_percent(10, 10, 1.0) != 75:
		return "percent %d %d %d" % [flight.load_percent(0, 0, 0.0), flight.load_percent(476, 0, 1.0), flight.load_percent(10, 10, 1.0)]
	return ""


## The window veil lives under a CanvasLayer. Anchors alone left it, and the film in it, 0 x 0: nothing was drawn.
func test_window_veil_covers_the_window() -> String:
	# Built the way BusyOverlay.cover builds it (the root refuses add_child while the runner sets up).
	var layer := CanvasLayer.new()
	var veil := BusyOverlay.new()
	layer.add_child(veil)
	add_child(layer)
	veil.show_busy("Loading scenery…", true, "a320", "VOCI")
	var win := get_viewport().get_visible_rect().size
	if veil.size.distance_to(win) > 1.0:
		return "veil %s, window %s" % [veil.size, win]
	if _film(veil).size.distance_to(win) > 1.0:
		return "film %s, window %s" % [_film(veil).size, win]
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


func test_clip_follows_the_flight() -> String:
	if _clip_title("a320", "VAPO") != TITLES[0] or _clip_title("a320", "VAJJ") != TITLES[0] or _clip_title("A320", "VABB") != TITLES[0]:
		return "an A320 should play the evening final, including at Juhu"
	if _clip_title("c172", "VAJJ") != TITLES[2] or _clip_title("c172", "vajj") != TITLES[2] or _clip_title("c172", "VABB") != TITLES[2]:
		return "a Cessna at Juhu or Mumbai should play the coast"
	if _clip_title("c172", "VAPO") != TITLES[1] or _clip_title("c172", "VANM") != TITLES[1] or _clip_title("c172", "VOCI") != TITLES[1]:
		return "anywhere else, including Navi Mumbai, should play the Ghats"
	return ""


func test_flight_loader_opens_on_that_clip() -> String:
	var veil := BusyOverlay.new()
	add_child(veil)
	veil.show_busy("Loading scenery…", true, "c172", "VAJJ")
	var film := _film(veil)
	if film == null or film.caption != TITLES[2]:
		return "Juhu caption '%s'" % ("" if film == null else film.caption)
	if film.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		return "the film should stay full-bleed"
	veil.show_busy("Loading scenery…", true, "a320", "VAJJ")
	if film.caption != TITLES[0]:
		return "A320 at Juhu caption '%s'" % film.caption
	veil.show_busy("Loading the menu…", true)
	if not TITLES.has(film.caption):
		return "a menu load should still name a clip, got '%s'" % film.caption
	return ""


func _clip_title(aircraft: String, airport: String) -> String:
	var i := LoaderFilm.clip_for(aircraft, airport)
	if i < 0 or i >= LoaderFilm.CLIPS.size():
		return ""
	return str(LoaderFilm.CLIPS[i].title)


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
