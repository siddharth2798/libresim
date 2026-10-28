extends Node
## Debug: README screenshots. Builds one showcase scene (tests/showcase_scenes.gd), waits until
## the terrain, trees, buildings and textures have finished streaming, and saves a PNG.
##   godot --path game res://tests/debug_showcase.tscn -- --scene=<name> --quality=ultra
##   godot --path game res://tests/debug_showcase.tscn -- --list
## Env: FREESIM_SHOTS (output folder, default user://), FREESIM_SIZE (default 1920x1080).
## Run all of them, with the user's settings backed up and the JPEGs made, by tools/make_screenshots.sh.
## Flight scenes freeze the aircraft once placed (optionally after a short scripted climb), so
## streaming can finish with the camera standing still; the UI is hidden except what the scene keeps.

const Scenes := preload("res://tests/showcase_scenes.gd")
const FLIGHT := "res://world/flight.tscn"
const MENU := "res://ui/menu/start_screen.tscn"
const MAX_SETTLE_S := 120.0  # give up waiting for the streamers after this
const QUIET_S := 2.5  # streaming must stay idle this long

var f: Node  # the flight scene
var _out := ""
var _name := ""
var _fov := 0.0  # free-camera field of view override (degrees), 0 = the rig's own
## The scripted landing pilot (tests/lesson_pilots.gd) reads these from its "probe" (this node).
var ts: TrainingSession
var pl: Node
var args := {}
var t := 0.0
var st := {}
var _landing_pilot := false
var _prop_deg := -1.0  # fixed propeller angle (degrees), -1 = let it turn


func _ready() -> void:
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			_name = a.substr(8)
		elif a == "--list":
			print("SCENES ", " ".join(Scenes.SCENES.keys()))
			get_tree().quit()
			return
	if not Scenes.SCENES.has(_name):
		push_error("unknown scene '%s'; --list shows them" % _name)
		get_tree().quit(1)
		return
	AudioServer.set_bus_mute(0, true)
	await _resize()
	var def: Dictionary = Scenes.SCENES[_name]
	if def.has("menu"):
		await _menu(def)
	else:
		await _flight(def)
	get_tree().quit()


## The window manager may ignore a size asked for before the window is mapped: ask again after it.
func _resize() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	size = size if size.contains("x") else "1920x1080"
	var want := Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	await _wait(0.5)
	get_window().size = want
	await _wait(0.5)
	print("WINDOW ", get_window().size)
	if get_window().size != want:
		push_warning("window is %s, wanted %s" % [get_window().size, want])


func _physics_process(dt: float) -> void:
	if _landing_pilot:
		t += dt
		LessonPilots.tick(self, dt)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _save(suffix := "") -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(_name + suffix + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


## The start-screen pages (home, Training, the free-flight steps).
func _menu(def: Dictionary) -> void:
	Session.skip_menu = false
	Session.setup = Session.DEFAULT.duplicate(true)
	for k in def.get("setup", {}):
		Session.setup[k] = def.setup[k]
	if def.has("weather"):
		Session.apply_weather_preset(def.weather)
	var s: Control = load(MENU).instantiate()
	add_child(s)
	await _wait(1.5)
	s.go(def.menu)
	if def.has("step"):
		s.screen("flight").show_step(int(def.step))
	await _wait(1.5)
	await _save()


func _flight(def: Dictionary) -> void:
	_setup_session(def)
	f = load(FLIGHT).instantiate()
	add_child(f)
	RenderingServer.frame_pre_draw.connect(_pre_draw)
	await _frames(3)
	print("STREAMING busy right after placement: ", _busy())  # sanity check of _busy(): expect true
	_hide_ui(def.get("ui", []))
	_prop_deg = float(def.get("prop_deg", -1.0))
	for k in def.get("lights", {}):
		Props.set_v("controls/lights/" + k, def.lights[k])
	var fdm: FdmNode = f.get_node("Fdm")
	if def.has("fly"):
		await _fly(def.fly)
	if def.has("follow_me"):
		await _follow_me(def.follow_me)
	fdm.paused = true  # camera and aircraft stand still while the world streams in
	var cam: CameraRig = f.get_node("Camera")
	var views: Array = def.get("variants", [{}])  # several camera tries from one placement (look, then keep one)
	for i in views.size():
		var d := def.duplicate()
		d.merge(views[i], true)
		_aim_camera(cam, d)
		await _wait(float(d.get("wait", 5.0)) if i == 0 else 1.0)
		var t := await _settle()
		if d.get("agl", false):
			_aim_camera(cam, d)  # the ground heights under the camera are known now that the terrain has streamed in
		if d.get("map", false):
			await _show_map(d)
		if d.has("panel"):
			var pn = f.get_node("UI/Panel")
			pn.layout = int(d.panel)
			pn._build()
		if d.has("pause"):  # the full-screen pause over the frozen scene (UI/Pause was hidden by _hide_ui)
			var pm: Control = f.get_node("UI/Pause")
			pm.visible = false
			pm.open()
			pm.show_page(str(d.pause))
		if d.has("checklist"):
			await _show_checklist(d.checklist)
		await _wait(2.0)  # camera easing, cloud and shader warm-up
		print("SETTLED after %.1f s (%s)" % [t, _state()])
		if d.has("taxi_banner"):  # the taxi instruction right after landing: just issued, then after it faded
			await _taxi_banner(d.taxi_banner)
			continue
		await _save("" if views.size() == 1 else "_%d" % i)


## Follow-me car scenes: ask for taxi, optionally stand the aircraft m metres along the route (nose along
## it, brakes on), put the car ~55 m ahead of it and let it settle (it waits for the aircraft there).
func _follow_me(d: Dictionary) -> void:
	var g: GroundOps = f.get_node("GroundOps")
	g.request_taxi()
	await _wait(1.0)
	if d.has("on_route_m") and not g._route.is_empty():
		var r := g._route_at(float(d.on_route_m))
		var fd: FDM = f.get_node("Fdm").fdm
		fd.pos_e = r[0].x
		fd.pos_n = r[0].y
		var e := fd.euler()
		fd.q = FDM.euler_to_quat(e.x, e.y, r[1])
		fd.v_b = Vector3.ZERO
		fd.w_b = Vector3.ZERO
		Props.set_v("controls/parking_brake", true)
		g._follow_s = float(d.on_route_m) + 55.0
	await _wait(float(d.get("secs", 12.0)))
	if g._follow != null:  # where the car stands relative to the aircraft's nose
		var ap: Vector3 = f.get_node("Fdm").position_enu()
		var rel := Vector2(g._follow.world_enu.x - ap.x, g._follow.world_enu.y - ap.y)
		var hd := Props.get_f("fdm/heading_rad", 0.0)
		print("FOLLOW_ME car %.0f m ahead, %.0f m right of the aircraft" % [rel.dot(Vector2(sin(hd), cos(hd))), rel.dot(Vector2(cos(hd), -sin(hd)))])
	else:
		print("FOLLOW_ME no car")


func _show_map(d: Dictionary) -> void:
	var m: Control = f.get_node("UI/Map")
	m.clip_contents = true  # the map draws imagery tiles past its own edge otherwise
	var route: Array = d.get("map_route", [d.gps] if d.has("gps") else [])  # GPS direct-to, then later legs
	Props.set_v("controls/gps/target", route[0] if not route.is_empty() else "")
	Props.set_v("controls/gps/route_next", route.slice(1))
	m.set_process(true)  # _hide_ui stopped it; it redraws from _process
	m.visible = true  # opens centred on the aircraft (wider if the route needs it)
	await _wait(1.0)
	var v := {"heading_up": d.get("map_heading_up", false)}
	if d.has("map_across"):
		v["across_nm"] = d.map_across
	if d.has("map_centre_on"):
		v["centre_on"] = d.map_centre_on
	m.apply_view(v)
	await _wait(1.0)
	m.wait_imagery()  # tiles load on worker threads
	await _wait(0.5)


func _setup_session(def: Dictionary) -> void:
	Session.skip_menu = true
	Session.clean = false
	Session.shot = ""
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.end_lesson()
	if def.has("lesson"):  # the lesson shows its card and markers; "pilot_lesson" only flies it (no training UI)
		var lesson := TrainingLogic.find(def.lesson)
		TrainingLogic.begin(lesson, "full")
	elif def.has("pilot_lesson"):
		var lesson := TrainingLogic.find(def.pilot_lesson)
		TrainingLogic.begin(lesson, "off")
	if def.has("weather"):  # after the lesson, which brings its own
		Session.apply_weather_preset(def.weather)
	for k in def.get("setup", {}):
		Session.setup[k] = def.setup[k]
	Session.setup.record = false
	Session.view = def.get("view", "chase")


## Hide every UI element except `keep` (node names under $UI; "training" = the lesson card) and
## the credits node (it holds the data attribution line).
func _hide_ui(keep: Array) -> void:
	f.get_node("ControlsOverlay").visible = false
	for c in f.get_node("UI").get_children():
		var is_keep: bool = c.name in keep or c.name == "Credits" or ("training" in keep and c is TrainingHud)
		if is_keep:
			continue
		c.visible = false
		c.set_process(false)
	if "Hud" in keep:
		f.get_node("UI/Hud").visible = true


## Scripted flight for d.secs seconds before the aircraft is frozen: a climb / cruise through the
## E2E attitude pilot, or (d.landing) the landing lesson's scripted pilot: flaps, 70 kt, the glide
## path, so the shot shows a real stabilised approach (set d.lesson in the scene).
func _fly(d: Dictionary) -> void:
	for n in ["Controls", "JoystickControls"]:
		f.get_node(n).set_process(false)
		f.get_node(n).set_physics_process(false)
	pl = Node.new()
	pl.set_script(load("res://tests/e2e/e2e_pilot.gd"))
	add_child(pl)
	pl.active = true
	if d.get("landing", false):
		ts = f.get_node("Training")
		t = 0.0
		st = {}
		_landing_pilot = true
	else:
		pl.pitch_tgt = float(d.get("pitch", 0.0))
		pl.roll_tgt = float(d.get("roll", 0.0))
		Props.set_v("controls/throttle", float(d.get("throttle", 1.0)))
		Props.set_v("controls/mixture", 1.0)
		Props.set_v("controls/flaps", int(d.get("flaps", 0)))
	await _wait(float(d.get("secs", 8.0)))
	_landing_pilot = false
	pl.active = false


## Free camera at `cam` = [forward, right, up] metres from the aircraft in its heading frame,
## aimed at `aim` (same frame); or a cockpit / orbit look = [yaw_deg, pitch_deg].
func _aim_camera(cam: CameraRig, def: Dictionary) -> void:
	var p: Vector3 = f.get_node("Fdm").position_enu()
	var h := Props.get_f("fdm/heading_rad", 0.0)
	if def.has("frame_vehicle"):  # frame = the ground vehicle of that kind nearest to the aircraft (AirportOps node "<kind>")
		var best: Node3D = null
		var bd := INF
		for n in f.get_node("AirportOps").find_children(str(def.frame_vehicle), "Node3D", true, false):
			var d := (n as Node3D).global_position.distance_to(FloatingOrigin.to_render(p))
			if d < bd:
				bd = d
				best = n
		if best != null:
			p = FloatingOrigin.to_world(best.global_position)
			h = -best.global_rotation.y
	if def.get("on_follow", false) and f.get_node("GroundOps")._follow != null:  # frame = the follow-me car's
		var car: FollowMeCar = f.get_node("GroundOps")._follow
		p = car.world_enu
		h = car.heading
	var fwd := Vector2(sin(h), cos(h))
	var right := Vector2(cos(h), -sin(h))
	if def.has("mode"):  # cockpit | chase | orbit
		cam.set_mode(["cockpit", "chase", "orbit"].find(def.mode))
	if def.has("cam"):
		var c: Array = def.cam
		var a: Array = def.get("aim", [0.0, 0.0, 0.0])
		var from := Vector3(p.x, p.y, p.z) + Vector3(fwd.x * c[0] + right.x * c[1], fwd.y * c[0] + right.y * c[1], c[2])
		var to := Vector3(p.x, p.y, p.z) + Vector3(fwd.x * a[0] + right.x * a[1], fwd.y * a[0] + right.y * a[1], a[2])
		if def.get("agl", false):  # cam / aim heights are metres above the ground under each point
			var cache: TerrainTileCache = f.get_node("Terrain").cache
			from.z = cache.height_at(from.x, from.y) + c[2]
			to.z = cache.height_at(to.x, to.y) + a[2]
		var d := to - from
		if cam.mode != CameraRig.Mode.FREE:
			cam.set_mode(CameraRig.Mode.FREE)
		cam._free_enu = from
		cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))
		cam._look_goal = cam._look
	elif def.has("look"):
		cam._look = Vector2(deg_to_rad(def.look[0]), deg_to_rad(def.look[1]))
		cam._look_goal = cam._look
	if def.has("fov"):  # cockpit zoom, or a fixed field of view for the free camera
		cam._fov_cockpit = float(def.fov)
		cam._fov_goal = float(def.fov)
		_fov = float(def.fov)
	else:
		_fov = 0.0
	if def.has("dist"):
		cam._dist = float(def.dist)


## Just before drawing: the camera rig sets its own 65 degrees every frame, and the model keeps
## the propeller turning slowly (a still blade across the view), so both are set here.
func _pre_draw() -> void:
	var cam: CameraRig = f.get_node("Camera")
	if _fov > 0.0 and cam.mode == CameraRig.Mode.FREE:
		cam.fov = _fov
	var model: AircraftModel = f.get_node("Aircraft")
	if _prop_deg >= 0.0 and model._pivots.has("prop"):
		model._pivots.prop[0].transform.basis = model._pivots.prop[1] * Basis(Vector3.RIGHT, deg_to_rad(_prop_deg))


## True while any streamer still has work: terrain tiles / textures, trees, buildings.
func _busy() -> bool:
	var c: TerrainTileCache = f.get_node("Terrain").cache
	if not c._tasks.is_empty() or not c._done.is_empty():
		return true
	var tr: Trees = f.get_node("Trees")
	if tr.visible and (tr._in_flight > 0 or not tr._queue.is_empty() or not tr._done.is_empty() or tr._chunks.values().has(null)):
		return true
	var b: Buildings = f.get_node("Buildings")
	return b.visible and (not b._done.is_empty() or b._tiles.values().has(null))


func _state() -> String:
	var tr: Trees = f.get_node("Trees")
	var n_bb := 0
	for mi in tr._chunks.values():
		n_bb += mi.multimesh.instance_count if mi != null else 0
	var lod: TreeLod = tr.get_node("Lod")
	return "terrain nodes %d, tree chunks %d (%d billboards, %d LOD0 meshes within %.0f m), building tiles %d" % [f.get_node("Terrain").visible_nodes, tr._chunks.size(), n_bb, lod.instance_count(), lod.covered, f.get_node("Buildings")._tiles.size()]


## Waits until the streamers have been idle for QUIET_S in a row; returns the seconds waited.
func _settle() -> float:
	var t := 0.0
	var quiet := 0.0
	while quiet < QUIET_S and t < MAX_SETTLE_S:
		var dt := get_process_delta_time()
		t += dt
		quiet = 0.0 if _busy() else quiet + dt
		await get_tree().process_frame
	if t >= MAX_SETTLE_S:
		push_warning("streaming did not settle in %.0f s" % MAX_SETTLE_S)
	return t


## Just after landing (the aircraft stands on the runway): ATC gives "taxi to the apron". Saves the
## screen 1.5 s after the instruction (<scene>_a) and again once it has faded (<scene>_b).
func _taxi_banner(d: Dictionary) -> void:
	var atc: Control = f.get_node("UI/Atc")
	atc.session.c.set_state("landed")
	if d.get("stack", false):  # the cards that usually come with a landing
		var notes := get_tree().get_first_node_in_group("notifications") as Notifications
		notes.post("Touchdown \u00b7 Smooth", "420 fpm \u00b7 1.2 g \u00b7 63 KIAS", Notifications.INFO, "td")
	var txt: String = f.get_node("GroundOps").request_taxi_to_stand()
	print("TAXI instruction: ", txt)
	await _wait(1.5)
	await _save("_a")
	await _wait(float(d.get("fade_s", 15.0)))
	await _save("_b")


## The floating checklist (F2) in a given state: {frac: [x, y] (omit = default dock), size: [w, h],
## opacity, collapsed, list, ticks (items ticked by hand)}.
func _show_checklist(d: Dictionary) -> void:
	var cl: ChecklistPanel = f.get_node("UI/Checklist")
	cl.persist = false
	cl.current = int(d.get("list", 0))
	cl._rebuild()
	for i in int(d.get("ticks", 0)):
		cl._manual["%d/%d" % [cl.current, i]] = true
	cl.visible = true
	if d.has("frac"):
		cl.set_placement(Vector2(d.frac[0], d.frac[1]), Vector2(d.size[0], d.size[1]), float(d.get("opacity", 0.9)), bool(d.get("collapsed", false)))
	else:
		cl.set_opacity(float(d.get("opacity", 0.9)), false)
		if d.get("collapsed", false):
			cl.set_collapsed(true)
	await _frames(3)
