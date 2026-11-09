extends Node
## Debug: README screenshots. Builds one showcase scene (tests/showcase_scenes.gd), waits until terrain, trees, buildings and
## textures have streamed in, and saves a PNG.
##   godot --path game res://tests/debug_showcase.tscn -- --scene=<name> --quality=ultra
##   godot --path game res://tests/debug_showcase.tscn -- --list
## Env: FREESIM_SHOTS (output folder, default user://), FREESIM_SIZE (default 1920x1080).
## tools/make_screenshots.sh runs them all (user settings backed up, JPEGs made).
## Flight scenes freeze the aircraft once placed (optionally after a short scripted climb) so streaming finishes with the
## camera still; the UI is hidden except what the scene keeps.
## Split: showcase_setup.gd (session, menu pages, UI, scripted flight), showcase_camera.gd (aiming), showcase_stream.gd
## (streaming settle), showcase_views.gd (follow-me, map, panel, pause, checklist, taxi banner).

const Scenes := preload("res://tests/showcase_scenes.gd")
const CloudScenes := preload("res://tests/showcase_cloud_scenes.gd")
const LightScenes := preload("res://tests/showcase_light_scenes.gd")
const VehicleScenes := preload("res://tests/showcase_vehicle_scenes.gd")
const JetwayScenes := preload("res://tests/showcase_jetway_scenes.gd")
const FlybyScenes := preload("res://tests/showcase_flyby_scenes.gd")
const FogScenes := preload("res://tests/showcase_fog_scenes.gd")
const TerminalScenes := preload("res://tests/showcase_terminal_scenes.gd")
const FilmScenes := preload("res://tests/showcase_film_scenes.gd")
const Setup := preload("res://tests/showcase_setup.gd")
const Views := preload("res://tests/showcase_views.gd")
const Aim := preload("res://tests/showcase_camera.gd")
const Stream := preload("res://tests/showcase_stream.gd")
const FLIGHT := "res://world/flight.tscn"

var f: Node  # the flight scene
var _all: Dictionary = Scenes.SCENES.merged(CloudScenes.scenes()).merged(LightScenes.scenes()).merged(VehicleScenes.scenes()).merged(JetwayScenes.scenes()).merged(FlybyScenes.scenes()).merged(FogScenes.scenes()).merged(TerminalScenes.scenes()).merged(FilmScenes.scenes())  # every scene by name
var _out := ""
var _name := ""
var _fov := 0.0  # free-camera field of view override (degrees), 0 = the rig's own
## The scripted landing pilot (tests/lesson_pilots.gd) reads these from its "probe" (this node).
var ts: TrainingSession
var pl: Node
var args := {}
var t := 0.0
var st := {}
var landing_pilot := false
var _prop_deg := -1.0  # fixed propeller angle (degrees), -1 = let it turn
var _bench := 0.0  # --bench=<s>: measure frame times this long before the shot (tools/bench.sh)
var _film := 0.0  # --film=<s>: after the shot settles, save a short camera move as JPEGs (loader clips)
var _film_fps := 24  # run with --fixed-fps at the same rate: each saved frame is then exactly 1 / fps of game time
var _film_w := 1600  # saved frame width (px)


func _ready() -> void:
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_name = a.substr(8)
		elif a.begins_with("--bench="):
			_bench = float(a.substr(8))
		elif a.begins_with("--film="):
			_film = float(a.substr(7))
		elif a.begins_with("--film-fps="):
			_film_fps = maxi(int(a.substr(11)), 1)
		elif a == "--list":
			print("SCENES ", " ".join(_all.keys()))
			get_tree().quit()
			return
	if not _all.has(_name):
		push_error("unknown scene '%s'; --list shows them" % _name)
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	await _resize()
	var def: Dictionary = _all[_name]
	if def.has("menu"):
		await Setup.menu(self, def)
	else:
		await _flight(def)
	await _close()
	get_tree().quit()


## Free the flight scene before quitting and give the audio thread a moment: a sound still playing at quit
## (the engine, with --audio-driver Dummy) otherwise leaks its AudioStreamWAV / playback at exit.
func _close() -> void:
	if f == null:
		return
	RenderingServer.frame_pre_draw.disconnect(_pre_draw)
	f.queue_free()
	f = null
	await wait(0.25)
	await frames(2)


## The window manager may ignore a size asked for before the window is mapped: ask again after it.
func _resize() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	size = size if size.contains("x") else "1920x1080"
	var want := Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	await wait(0.5)
	get_window().size = want
	await wait(0.5)
	print("WINDOW ", get_window().size)
	if get_window().size != want:
		push_warning("window is %s, wanted %s" % [get_window().size, want])


func _physics_process(dt: float) -> void:
	if landing_pilot:
		t += dt
		LessonPilots.tick(self, dt)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func save(suffix := "") -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(_name + suffix + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _flight(def: Dictionary) -> void:
	Setup.setup_session(def)
	f = load(FLIGHT).instantiate()
	add_child(f)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await frames(3)
	print("STREAMING busy right after placement: ", Stream.busy(f))  # sanity check of busy(): expect true
	Setup.hide_ui(f, def.get("ui", []))
	_prop_deg = float(def.get("prop_deg", -1.0))
	for k in def.get("lights", {}):
		Props.set_v("controls/lights/" + k, def.lights[k])
	for k in def.get("props", {}):  # any property-tree value, e.g. "controls/gear": 1.0
		Props.set_v(k, def.props[k])
	var fdm: FdmNode = f.get_node("Fdm")
	if def.has("fly"):
		await Setup.fly(self, def.fly)
	if def.has("follow_me"):
		await Views.follow_me(self, def.follow_me)
	fdm.paused = true  # camera and aircraft stand still while the world streams in
	if def.has("att"):  # [roll_deg, pitch_deg]: the attitude to show (a stalled start-up frame can leave the aircraft pitched up)
		var fd: FDM = fdm.fdm
		fd.q = FDM.euler_to_quat(deg_to_rad(def.att[0]), deg_to_rad(def.att[1]), fd.euler().z)
	var cam: CameraRig = f.get_node("Camera")
	var views: Array = def.get("variants", [{}])  # several camera tries from one placement (look, then keep one)
	for i in views.size():
		var d := def.duplicate()
		d.merge(views[i], true)
		_fov = Aim.aim(f, cam, d)
		await wait(float(d.get("wait", 5.0)) if i == 0 else 1.0)
		var settled := await Stream.settle(self, f)
		if d.get("agl", false):
			_fov = Aim.aim(f, cam, d)  # the ground heights under the camera are known now that the terrain has streamed in
		await Views.overlays(self, d)
		await wait(2.0)  # camera easing, cloud and shader warm-up
		print("SETTLED after %.1f s (%s)" % [settled, Stream.state(f)])
		if _film > 0.0:
			# no depth of field on a film: in the free camera it focuses on the aircraft and blurs the whole place
			Session.interactive_override = 0  # options stay in memory: the player's own file is not touched
			UserOptions.set_v("depth_of_field", false)
			PostFx.apply(f, Graphics.preset)
			await wait(1.0)
			if d.has("cam_end"):
				await _follow(d)
			else:
				await _roll()
			break
		if d.has("taxi_banner"):  # the taxi instruction right after landing: just issued, then after it faded
			await Views.taxi_banner(self, d.taxi_banner)
			continue
		var tag := "" if views.size() == 1 else "_%d" % i
		if _bench > 0.0:
			print(BenchProbe.line(_name, Graphics.preset, Graphics.renderer(), await BenchProbe.measure(self, _bench)))
			tag += "_%s_%s" % [Graphics.preset, Graphics.renderer()]
		await save(tag)


## A slow orbit of the settled camera, one JPEG per frame. The loader plays these back.
## The pivot sits ahead along the view, so the move keeps the subject in frame instead of flying through it.
func _roll() -> void:
	var credits := f.get_node_or_null("UI/Credits")
	if credits != null:
		credits.visible = false  # the loader draws the same attribution line over the film
	# An occluded window stops presenting, and the next frame grab then waits forever.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	var cam: CameraRig = f.get_node("Camera")
	var n := maxi(int(_film * _film_fps), 1)
	var dir := _out.path_join(_name.trim_prefix("film_"))  # film_<aircraft>_<place> -> ui/loader/<aircraft>_<place>
	DirAccess.make_dir_recursive_absolute(dir)
	var heading := -cam._look.x
	var fwd := Vector3(sin(heading), cos(heading), 0.0)
	var pivot := cam._free_enu + fwd * 48.0
	var arm := cam._free_enu - pivot
	var height := cam._free_enu.z
	var pitch := cam._look.y
	var arc := deg_to_rad(14.0)
	for i in n:
		var a := arc * float(i) / float(maxi(n - 1, 1))
		var c := cos(a)
		var s := sin(a)
		var rv := Vector3(arm.x * c - arm.y * s, arm.x * s + arm.y * c, 0.0)
		cam._free_enu = Vector3(pivot.x + rv.x, pivot.y + rv.y, height)
		var to := pivot - cam._free_enu
		cam._look = Vector2(-atan2(to.x, to.y), pitch)
		cam._look_goal = cam._look
		await frames(1)
		await RenderingServer.frame_post_draw
		_film_frame(dir, i)
	print("FILM %d %s" % [n, dir])


## A flying clip: the aircraft flies on (the FDM runs again) and the free camera holds an offset from it that drifts
## from `cam` to `cam_end` (and `aim` to `aim_end`), so the ground moves under a live aircraft instead of a pan
## around a frozen one. Run with --fixed-fps <film fps>: game time then advances 1 / fps per saved frame.
func _follow(d: Dictionary) -> void:
	var credits := f.get_node_or_null("UI/Credits")
	if credits != null:
		credits.visible = false
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	var cam: CameraRig = f.get_node("Camera")
	var n := maxi(int(_film * _film_fps), 1)
	var dir := _out.path_join(_name.trim_prefix("film_"))  # film_<aircraft>_<place> -> ui/loader/<aircraft>_<place>
	DirAccess.make_dir_recursive_absolute(dir)
	(f.get_node("Fdm") as FdmNode).paused = false
	var c0: Array = d.cam
	var c1: Array = d.cam_end
	var a0: Array = d.get("aim", [0.0, 0.0, 0.0])
	var a1: Array = d.get("aim_end", a0)
	for i in n:
		var k := smoothstep(0.0, 1.0, float(i) / float(maxi(n - 1, 1)))
		var dd := d.duplicate()
		dd.cam = [lerpf(c0[0], c1[0], k), lerpf(c0[1], c1[1], k), lerpf(c0[2], c1[2], k)]
		dd.aim = [lerpf(a0[0], a1[0], k), lerpf(a0[1], a1[1], k), lerpf(a0[2], a1[2], k)]
		await get_tree().process_frame  # before the rig's _process: it places the camera from _free_enu
		Aim.aim(f, cam, dd)
		await RenderingServer.frame_post_draw
		_film_frame(dir, i)
	print("FILM %d %s" % [n, dir])


## Saves the frame just drawn (the caller awaits frame_post_draw first).
func _film_frame(dir: String, i: int) -> void:
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > _film_w:
		img.resize(_film_w, int(img.get_height() * float(_film_w) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var path := dir.path_join("%03d.jpg" % i)
	img.save_jpg(path, 0.86)
	print("FRAME %d %s" % [i, path])


func _pre_draw() -> void:
	Aim.pre_draw(f, _fov, _prop_deg)
