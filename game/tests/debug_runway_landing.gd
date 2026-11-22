extends Node
## Debug (realistic runways, Stage 2): a real touchdown in the flight scene leaves tyre marks. Starts the C172 a few
## feet above the runway centreline just before the aiming point (air start), lets it settle onto the runway, then
## photographs the marks from a free camera, checks F5 clears them and that a captured situation brings them back.
## Needs a display; mute it:
##   godot --path game res://tests/debug_runway_landing.tscn --audio-driver Dummy [-- --quality=low]
## RWPV_OUT=<dir> for the screenshots (landing_marks.png, landing_after_f5.png, landing_after_load.png).

var f: Node3D
var _out := ""


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)  # always silent (also run with --audio-driver Dummy)
	Session.interactive_override = 0
	Session.setup = Session.DEFAULT.duplicate(true)
	var s: Dictionary = Session.setup
	s.airport = "VABB"
	s.runway = "27"
	s.start = "air"
	s.air_ft = 12.0
	s.air_nm = -0.12  # past the threshold: over the runway
	s.air_kt = 62.0
	s.air_custom = true
	s.air_kt_given = true
	Session.apply_weather_preset("Clear")
	s.wind_kt = 0.0
	s.time_rate = 0.0
	s.live_weather = false
	Session.clean = true
	_out = OS.get_environment("RWPV_OUT") if OS.get_environment("RWPV_OUT") != "" else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	get_window().size = Vector2i(1600, 900)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _run() -> void:
	for i in 14:
		await get_tree().create_timer(1.0).timeout
		Props.set_v("controls/throttle", 0.0)  # idle: it settles out of ground effect onto the runway
		print("RWLD t %d s: agl %.1f m, %.0f kt, paused %s" % [i + 1, Props.get_f("fdm/agl_m"), Props.get_f("fdm/cas_mps") / 0.5144, f.fdm_node.paused])
	var tm: TouchdownMarks = f.get_node("TouchdownFx/Marks")
	print("RWLD marks after landing: ", tm.marks, "  baked runways: ", f.airports.baked_runways())
	var key := "VABB/27"
	if tm.marks.has(key) and not tm.marks[key].is_empty():
		var m: Vector4 = tm.marks[key][0]
		await _shoot_mark(m, "landing_marks")
	var saved := Situation.capture(f)
	f._reset()  # F5
	await get_tree().create_timer(2.0).timeout
	print("RWLD marks after F5: ", tm.marks)
	if not saved.is_empty():
		await _shoot_mark(_first(saved), "landing_after_f5")
		Situation.apply(f, saved)
		await get_tree().create_timer(1.0).timeout
		print("RWLD marks after load: ", tm.marks)
		await _shoot_mark(_first(saved), "landing_after_load")
	get_tree().quit()


func _first(saved: Dictionary) -> Vector4:
	var m: Dictionary = saved.get("systems", {}).get(TouchdownMarks.KEY, {}).get("marks", {})
	for k in m:
		var v: Array = m[k][0]
		return Vector4(v[0], v[1], v[2], v[3])
	return Vector4(300.0, 0.0, 0.0, 0.5)


## Free camera 4 m up, 12 m short of the mark, looking at it (no depth of field).
func _shoot_mark(m: Vector4, name: String) -> void:
	var r: Dictionary = f.airports.data.runways.filter(func(x): return x.airport == "VABB" and x.ends[0].ident == "27")[0]
	var a := Vector2(r.ends[0].x, r.ends[0].y)
	var u := (Vector2(r.ends[1].x, r.ends[1].y) - a).normalized()
	var rt := Vector2(u.y, -u.x)
	var at := a + u * m.x + rt * m.y
	var from := at - u * 12.0 + rt * 1.5
	var cam: CameraRig = f.cam
	cam.set_mode(CameraRig.Mode.FREE)
	var h: float = f.terrain.height_at(from.x, from.y)
	cam._free_enu = Vector3(from.x, from.y, h + 4.0)
	var d := Vector3(at.x - from.x, at.y - from.y, f.terrain.height_at(at.x, at.y) - h - 4.0)
	cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))
	var fx := f.get_node_or_null("PostFxDriver")
	if fx:
		fx.flags["depth_of_field"] = false
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("RWLD saved ", name)
