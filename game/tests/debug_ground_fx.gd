extends Node
## Debug (graphics Phase 3): screenshots of the ground particle effects in the real flight scene. One scenario per run:
##   GFX_SHOT=rain      C172 on VABB 27 in heavy rain, free camera low over the runway (rain splashes and rings)
##   GFX_SHOT=c172_wet  C172 takeoff roll on a wet VABB 27, chase view           GFX_SHOT=a320_wet  the same, A320
##   GFX_SHOT=runup     C172 at full power, brakes on, on a wet apron stand (propeller wash mist)
##   GFX_SHOT=grass     C172 rolling on the dry grass beside the VAJJ runway (dust)   GFX_SHOT=dry  dry takeoff roll
##   GFX_SHOT=night     C172 wet takeoff roll at night (the spray must not glow)
## GFX_OFF=1 turns the Phase 3 effects off for a "before" shot (no ground particles, no rain rings).
## GFX_BENCH=<s> (takeoff shots): measures frame times for that long from 8 m/s instead (BenchProbe; prints a BENCH line).
## Needs a display; always muted:
##   godot --path game res://tests/debug_ground_fx.tscn --audio-driver Dummy [-- --quality=high]
## GFX_OUT=<dir> for the screenshots (<shot>[_before].png).

var f: Node3D
var _shot := ""
var _off := false
var _out := ""
var _t := 0.0
var _full := false  # full power from now on
var _brakes := false
var _hdg0 := NAN  # runway heading held on a takeoff roll


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)  # always silent (also run with --audio-driver Dummy)
	process_priority = 1000  # after WeatherFx: a "before" shot can switch the rain rings off
	_shot = OS.get_environment("GFX_SHOT") if OS.get_environment("GFX_SHOT") != "" else "rain"
	_off = OS.get_environment("GFX_OFF") == "1"
	_out = OS.get_environment("GFX_OUT") if OS.get_environment("GFX_OUT") != "" else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	Session.interactive_override = 0
	Session.setup = Session.DEFAULT.duplicate(true)
	var s: Dictionary = Session.setup
	s.aircraft = "a320" if _shot == "a320_wet" else "c172"
	Session.apply_payload_defaults(AircraftDef.load_def(s.aircraft))  # fuel and payload of that aircraft
	s.airport = "VAJJ" if _shot == "grass" else "VABB"
	s.runway = "08" if _shot == "grass" else "27"
	s.start = "stand" if _shot == "runup" else "runway"
	Session.apply_weather_preset("Clear" if _shot in ["grass", "dry"] else "Overcast")
	s.precip = 0.0 if _shot in ["grass", "dry"] else (0.85 if _shot == "rain" else 0.45)
	s.visibility_m = 8000.0
	s.wind_kt = 0.0
	s.time_h = 22.0 if _shot == "night" else 11.0
	s.time_rate = 0.0
	s.live_weather = false
	Session.clean = true
	Session.view = "chase"
	get_window().size = Vector2i(1600, 900)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _physics_process(_dt: float) -> void:
	if f == null:
		return
	if _full:
		var lv = AircraftControls.current().levers
		for i in lv.count:
			lv.write_pos(i, 1.0)  # the lever keys move levers from their own positions: set those, not only the props
	if _full and not _brakes and _hdg0 == _hdg0:  # keep straight down the runway (rudder / nose wheel on heading error)
		var err := wrapf(f.fdm_node.fdm.euler().z - _hdg0, -PI, PI)
		Props.set_v("controls/yaw", clampf(-3.0 * err, -1.0, 1.0))
	elif f.fdm_node and f.fdm_node.fdm:
		_hdg0 = f.fdm_node.fdm.euler().z
	var b := 1.0 if _brakes else 0.0
	Props.set_v("controls/brake_left", b)
	Props.set_v("controls/brake_right", b)


func _process(_dt: float) -> void:
	if _off:
		RenderingServer.global_shader_parameter_set("precip", 0.0)  # no rain rings (the streaks keep their own rate)
		var g := f.get_node_or_null("TouchdownFx/Ground") if f else null
		if g:
			g.set_counts(GroundFxQuality.counts("low"))


func _run() -> void:
	await _wait(5.0)  # terrain, runway bakes
	var fd: FDM = f.fdm_node.fdm
	var pfx := f.get_node_or_null("PostFxDriver")
	if pfx:
		pfx.flags["depth_of_field"] = false  # sharp near ground
	var gfx: GroundFx = f.get_node("TouchdownFx/Ground")
	print("GFX %s: preset %s, counts %s, wetness %.2f, precip %.2f" % [_shot, Graphics.preset, gfx.counts,
		Props.get_f("environment/wetness"), Props.get_f("environment/precip")])
	match _shot:
		"rain":
			_low_camera(fd)
			await _wait(3.0)
		"runup":
			for u in fd.units:
				u.warm_start(false)
				u.engine.running = true
			Props.set_v("controls/magnetos", 3)
			Props.set_v("controls/mixture", 1.0)
			_brakes = true
			_full = true
			await _wait(6.0)
			if OS.get_environment("GFX_SIDE") == "1":
				_side_camera(fd)
			await _wait(3.5)  # the camera-mode card has gone
		"grass":
			var key := Vector2i(floori(fd.pos_e / gfx.surface.tile_m), floori(fd.pos_n / gfx.surface.tile_m))
			for i in 30:  # the pavement mask tile is read on a worker
				gfx.surface.paved(fd.pos_e, fd.pos_n)
				if gfx.surface._tiles.has(key):
					break
				await _wait(0.5)
			await _to_grass(fd, gfx)
			await _wait(1.0)
			_full = true
			await _roll_until(fd, 14.0, 20.0)
		_:
			_full = true
			var bench := float(OS.get_environment("GFX_BENCH")) if OS.get_environment("GFX_BENCH") != "" else 0.0
			if bench > 0.0:  # frame cost over the roll from 8 m/s (the same path with the effects on or off)
				Graphics.set_render_frac(minf(float(Graphics.PRESETS[Graphics.preset].scale), 1.0))  # no auto scaling while measuring
				await _roll_until(fd, 8.0, 40.0)
				var r := await BenchProbe.measure(self, bench, 10)
				print(BenchProbe.line(_shot + ("_off" if _off else "_on"), Graphics.preset, Graphics.renderer(), r))
				get_tree().quit()
				return
			await _roll_until(fd, 28.0 if _shot != "a320_wet" else 38.0, 40.0)
	await _save(_shot + ("_before" if _off else ""))
	if gfx.splash:
		print("GFX splash rate %.2f" % gfx.splash.rate())
	for w in gfx.washes:
		var src: Vector3 = FloatingOrigin.to_world(w.position + w.proc.emission_shape_offset)
		print("GFX wash src ENU %s, aircraft ENU (%.1f, %.1f), heading %.0f deg, dir %s" % [src, fd.pos_e, fd.pos_n,
			rad_to_deg(fd.euler().z), w.proc.direction])
	print("GFX thrust %s, throttle %s, park %s, athr %s, brakes %.2f %.2f" % [fd.units.map(func(u): return int(u.thruster.thrust)),
		fd.units.map(func(u): return snappedf(u.engine.throttle, 0.01)), Props.get_v("controls/parking_brake", null),
		Props.get_v("ap/athr_active", null), fd.gear.brake_left, fd.gear.brake_right])
	print("GFX %s: gs %.1f m/s, emitting %s" % [_shot, Vector2(fd.velocity_ned().x, fd.velocity_ned().y).length(),
		gfx.find_children("*", "GPUParticles3D", true, false).filter(func(p): return p.emitting).map(func(p): return str(p.get_parent().name) + "/" + p.name)])
	get_tree().quit()


func _roll_until(fd: FDM, gs: float, limit_s: float) -> void:
	var t := 0.0
	while t < limit_s and Vector2(fd.velocity_ned().x, fd.velocity_ned().y).length() < gs:
		await get_tree().process_frame
		t += get_process_delta_time()


## Free camera 1.8 m over the runway beside the aircraft, looking down the runway and a little down.
func _low_camera(fd: FDM) -> void:
	var cam: CameraRig = f.cam
	cam.set_mode(CameraRig.Mode.FREE)
	var hdg := fd.euler().z
	var fwd := Vector2(sin(hdg), cos(hdg))
	var rt := Vector2(fwd.y, -fwd.x)
	var p := Vector2(fd.pos_e, fd.pos_n) + fwd * 25.0 + rt * 6.0
	cam._free_enu = Vector3(p.x, p.y, f.terrain.height_at(p.x, p.y) + 1.8)
	cam._look = Vector2(-hdg, deg_to_rad(-12.0))


## Free camera off the aircraft's left rear quarter, looking at the wash behind it.
func _side_camera(fd: FDM) -> void:
	var cam: CameraRig = f.cam
	cam.set_mode(CameraRig.Mode.FREE)
	var hdg := fd.euler().z
	var fwd := Vector2(sin(hdg), cos(hdg))
	var rt := Vector2(fwd.y, -fwd.x)
	var p := Vector2(fd.pos_e, fd.pos_n) - fwd * 4.0 - rt * 11.0
	cam._free_enu = Vector3(p.x, p.y, f.terrain.height_at(p.x, p.y) + 2.2)
	var at := Vector2(fd.pos_e, fd.pos_n) - fwd * 6.0
	var d := at - p
	cam._look = Vector2(-atan2(d.x, d.y), deg_to_rad(-8.0))


## Puts the aircraft on the first unpaved ground beside the runway (either side), parallel to it, with 100 m of grass ahead.
func _to_grass(fd: FDM, gfx: GroundFx) -> void:
	for attempt in 20:  # the mask tiles of the points tried arrive on a worker: try again until they are in
		if _try_grass(fd, gfx):
			return
		await _wait(0.5)
	print("GFX grass: no unpaved strip found")


func _try_grass(fd: FDM, gfx: GroundFx) -> bool:
	var hdg := fd.euler().z
	var fwd := Vector2(sin(hdg), cos(hdg))
	var rt := Vector2(fwd.y, -fwd.x)
	for along in [150.0, 400.0, 700.0]:
		for i in 30:
			for side in [1.0, -1.0]:
				var off: float = (30.0 + i * 5.0) * side
				var p: Vector2 = Vector2(fd.pos_e, fd.pos_n) + fwd * along + rt * off
				var ok := true
				for k in range(-1, 8):  # a clear strip ahead of it too
					var q: Vector2 = p + fwd * (k * 15.0)
					ok = ok and not gfx.surface.paved(q.x, q.y)
				if ok:
					f.fdm_node.place_on_ground(p.x, p.y, rad_to_deg(hdg))
					print("GFX grass: placed %.0f m along, %.0f m right of the centreline" % [along, off])
					return true
	return false


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("GFX saved ", _out.path_join(name + ".png"))
