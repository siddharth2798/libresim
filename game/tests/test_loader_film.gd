extends Node
## The full-screen loader plays a scenic clip and names the place. A short wait stays a dim veil.


const TITLES := ["The Western Ghats", "At the gate  ·  Kochi"]


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
		return "missing res://ui/loader/a320_ghats/000.jpg"
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


## Each aircraft has its own two clips, chosen by how the flight starts (Kochi air and runway starts play the Ghats).
func test_clip_follows_the_flight() -> String:
	var cases := [["a320", "VAPO", "runway", "a320_ghats"], ["a320", "VABB", "air", "a320_ghats"], ["a320", "VAJJ", "runway", "a320_ghats"],
		["A320", "voci", "air", "a320_ghats"], ["a320", "VOCC", "runway", "a320_ghats"], ["a320", "VOCI", "stand", "a320_gate"],
		["c172", "VAPO", "air", "c172_ghats"], ["c172", "VAJJ", "runway", "c172_ghats"], ["c172", "VOCI", "runway", "c172_ghats"],
		["c172", "VABB", "stand", "c172_gate"], ["", "VANM", "", "c172_ghats"]]
	for c in cases:
		var i := LoaderFilm.clip_for(c[0], c[1], c[2])
		var dir: String = LoaderFilm.CLIPS[i].dir if i >= 0 and i < LoaderFilm.CLIPS.size() else ""
		if not dir.ends_with("/" + c[3]):
			return "%s at %s (%s): got %s, want %s" % [c[0], c[1], c[2], dir, c[3]]
	return ""


## Every clip is shot (tools/shoot_loader_films.sh): 24 fps for at least 3 s, at 1600 px wide or more.
func test_every_clip_is_shot() -> String:
	if LoaderFilm.CLIPS.size() != 4:
		return "%d clips, want 4 (two aircraft x two places)" % LoaderFilm.CLIPS.size()
	for c in LoaderFilm.CLIPS:
		if str(c.dir).contains("juhu") or str(c.dir).contains("cochin"):
			return "the Mumbai and Cochin approach clips are gone: %s" % c.dir
	for gone in ["a320_cochin", "c172_cochin"]:
		if DirAccess.dir_exists_absolute("res://ui/loader/" + gone):
			return "the Cochin approach frames are still shipped: ui/loader/%s" % gone
	for c in LoaderFilm.CLIPS:
		var n := LoaderFrames.count(c.dir)
		if n < int(LoaderFilm.FPS * 3.0):
			return "%s has %d frames" % [c.dir, n]
		var img := LoaderFrames.decode(LoaderFrames.path(c.dir, 0))
		if img == null or img.get_width() < 1600:
			return "%s frames are %s px wide" % [c.dir, img.get_width() if img else 0]
	return ""


## The frames ship as their JPGs (import "keep", 73 MB), not as lossless textures (308 MB, decoded on the main thread):
## every frame's .import keeps the file.
func test_loader_frames_ship_as_jpgs() -> String:
	for c in LoaderFilm.CLIPS:
		for i in LoaderFrames.count(c.dir):
			var imp := FileAccess.get_file_as_string(LoaderFrames.path(c.dir, i) + ".import")
			if not imp.contains('importer="keep"'):
				return "%s is imported as a texture (tools/shoot_loader_films.sh writes keep imports)" % LoaderFrames.path(c.dir, i)
	return ""


## The next frame is decoded on a worker: the film takes it when it is ready and holds the current frame until then.
func test_loader_film_decodes_the_next_frame_on_a_worker() -> String:
	var src := LoaderFrames.new()
	var dir: String = LoaderFilm.CLIPS[0].dir
	var a := LoaderFrames.path(dir, 1)
	if src.take(a) != null:
		return "nothing was asked for yet"
	src.prefetch(a)
	var img: Image = null
	var t := Time.get_ticks_msec()
	while img == null and Time.get_ticks_msec() - t < 3000:
		OS.delay_msec(2)
		img = src.take(a)
	src.prefetch(LoaderFrames.path(dir, 2))
	var other := src.take(LoaderFrames.path(dir, 3))  # not the frame being decoded
	src.release()
	if img == null or img.get_width() < 1600:
		return "the worker did not decode frame 1"
	if other != null:
		return "take() handed out a frame that was not asked for"
	var film := LoaderFilm.new()
	add_child(film)
	film.restart_for("c172", "VABB", "runway")
	film.visible = true
	var first := film.get("_frame") as int
	film._process(1.0 / LoaderFilm.FPS + 0.001)  # the prefetch may still run: the film holds or moves on, never blocks
	t = Time.get_ticks_msec()
	while film.get("_frame") == first and Time.get_ticks_msec() - t < 3000:
		OS.delay_msec(2)
		film._process(1.0 / LoaderFilm.FPS + 0.001)
	if film.get("_frame") != first + 1:
		return "the film did not move to the next frame (%d -> %d)" % [first, film.get("_frame")]
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


## A long load moves on to the next clip instead of replaying the one that ended.
func test_loader_film_moves_on_instead_of_repeating() -> String:
	for c in LoaderFilm.CLIPS.size():
		for same in [true, false]:
			var n := LoaderFilm.next_clip(c, same)
			if n == c:
				return "clip %d repeats" % c
			if same and n / LoaderFilm.PLACES.size() != c / LoaderFilm.PLACES.size():
				return "flight clip %d left its aircraft" % c
	return ""


## The game's sound stays off behind the loader film and comes back when the veil goes.
func test_loader_silences_the_game_until_it_lifts() -> String:
	BusyOverlay.cover(get_tree(), "Loading…", "c172", "VOCI")
	var held := AudioServer.is_bus_mute(AudioServer.get_bus_index("Engine"))
	BusyOverlay.dismiss(get_tree())
	var freed := not AudioServer.is_bus_mute(AudioServer.get_bus_index("Engine"))
	AudioSettings.hold_game(false)
	if not held:
		return "engine bus should be muted behind the film"
	if not freed:
		return "engine bus should be live once the veil is dropped"
	return ""


## The credit line never shows squeezed into a column at the left: hidden while the veil is narrow (its first frames,
## a window still settling), shown full width and centred once the window is laid out.
func test_credit_line_waits_for_a_wide_veil() -> String:
	var host := Control.new()
	host.size = Vector2(64, 64)
	add_child(host)
	var veil := BusyOverlay.new()
	host.add_child(veil)
	veil.show_busy("Loading the flight…", true)
	var c: Label = veil.get("_credit")
	var narrow := c.visible
	host.size = Vector2(1280, 720)
	veil._process(0.016)
	var wide := c.visible
	var w := c.size.x
	var centred := c.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
	host.free()
	if narrow:
		return "credit shown in a 64 px veil (it wraps into a column at the left)"
	if not wide or w < 1000.0 or not centred:
		return "credit at 1280 px: visible %s, width %.0f, centred %s" % [wide, w, centred]
	return ""
