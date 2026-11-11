extends Node
## Debug: flicker hunt. Starts a flight (optionally a saved last_flight.json), waits for the scenery to stream in,
## then saves a burst of consecutive frames and a few spaced ones, so a diff shows what blinks from frame to frame.
## Needs a display. Run:
##   godot --path game --resolution 1920x1080 res://tests/debug_flicker.tscn -- --out=<dir> [--setup=<json>]
##       [--view=cockpit] [--wait=25] [--burst=12] [--spaced=6] [--spacing=0.25] [--roll=<s>] [--opt=<key>:<on|off>]
##       [--air=<kt>:<ft>]
## --roll=<s>: full thrust and brakes off this many seconds before the burst, to see the picture while moving.
## --opt: a UserOptions switch for this run only (kept in memory), e.g. --opt=motion_blur:off.
## --push: at a stand start, release the brake and start the pushback 2 s in (the camera moves off the terminal).
## --cam=f,r,u:af,ar,au: 5 s before the burst, a free camera at [forward, right, up] m from the aircraft (heading
##   frame) aimed at [af, ar, au] (tests/showcase_camera.gd), e.g. the left engine from behind: --cam=-9,-12,-1:2,-5.8,-1.8
## --thrust=<0..1>: hold the brakes and set both thrust levers (an engine run-up: the exhaust is hot).
## --freeze: Engine.time_scale = 0 during the burst (FDM, sky, beacons stop; shader TIME does not), so a still
##   camera's frames should match: any change is render instability (tools/flicker_metric.py measures it).
## --cam implies the free camera (a chase camera would take the view back).
## --fps=N: cap the frame rate (Engine.max_fps), so a burst samples a flashing light at known phases: at the
##   uncapped rate a 2 Hz flasher captured every ~166 ms is sampled at the same phase every third frame and hides.
## --sweep: random 0-120 ms pauses between burst frames (a 35 ms flash at 2 Hz is missed by a fixed interval).
## --hide=Aircraft,AirportOps,Terminals,Buildings,Trees,Airports,Terrain: hide these children of the flight scene
##   5 s before the burst (isolation: which group blinks on its own; docs/FLICKER-PLAN.md phase 2).
## --air: start in the air at that speed and height (after --setup), e.g. --air=280:2000.
## Writes <dir>/burst_NN.png (one per rendered frame) and <dir>/spaced_NN.png, then quits.

var _out := ""
var _wait := 25.0
var _burst := 12
var _spaced := 6
var _spacing := 0.25
var _roll := -1.0
var _push := false
var _pushed := false
var _cam := {}
var _thrust := -1.0
var _freeze := false
var _sweep := false  # --sweep: a random 0-120 ms pause before each burst frame, so a brief periodic flash is sampled at every phase
var _fps := 0  # --fps=N: Engine.max_fps during the run (a fixed capture interval: a periodic source is then sampled at known phases)
var _hide: PackedStringArray = []
var _real_lights := -1  # --real-lights=N: RunwayLights.set_real_lights(N, 0) 5 s before the burst (0 = no real apron SpotLights)
var _free: PackedStringArray = []  # --free=VolumetricFog,PostFxDriver: remove these flight-scene nodes (plain Nodes have no visible)
var _tree := false  # --tree: print the flight scene's and the camera's children once (names for --hide)
var _aimed := false
var _t := 0.0
var _n := 0
var _phase := 0  # 0 waiting, 1 burst, 2 spaced
var _next := 0.0


func _ready() -> void:
	var view := "cockpit"
	var air := []
	for a in OS.get_cmdline_user_args():
		if a == "--freeze":
			_freeze = true
			continue
		if a == "--sweep":
			_sweep = true
			continue
		if a == "--tree":
			_tree = true
			continue
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
			"hide": _hide = kv[1].split(",", false)
			"free": _free = kv[1].split(",", false)
			"fps": _fps = int(kv[1])
			"real-lights": _real_lights = int(kv[1])
			"wait": _wait = float(kv[1])
			"burst": _burst = int(kv[1])
			"spaced": _spaced = int(kv[1])
			"spacing": _spacing = float(kv[1])
			"view": view = kv[1]
			"roll": _roll = float(kv[1])
			"push": _push = kv[1] != "off"
			"thrust": _thrust = float(kv[1])
			"cam":
				var parts := kv[1].split(":")
				_cam = {"cam": Array(parts[0].split(",")).map(func(x): return float(x)),
					"aim": Array(parts[1].split(",")).map(func(x): return float(x))}
			"opt":
				var o := kv[1].split(":")
				Session.interactive_override = 0
				UserOptions.set_v(o[0], o[1] == "on")
			"air":
				var a2 := kv[1].split(":")
				air = [float(a2[0]), float(a2[1])]
			"setup":
				var d = JSON.parse_string(FileAccess.get_file_as_string(kv[1]))
				for k in d:
					if Session.setup.has(k):
						Session.setup[k] = d[k]
	if not air.is_empty():
		Session.setup.start = "air"
		Session.setup.air_kt = air[0]
		Session.setup.air_kt_given = true
		Session.setup.air_ft = air[1]
		Session.setup.air_custom = true
	Session.view = "free" if not _cam.is_empty() else view
	if _fps > 0:
		Engine.max_fps = _fps
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(load("res://world/flight.tscn").instantiate())


func _process(dt: float) -> void:
	_t += dt if Engine.time_scale > 0.0 else 1.0 / 60.0
	if _thrust >= 0.0 and _t > 3.0:
		for k in ["controls/throttle", "controls/throttle_2"]:
			Props.set_v(k, _thrust)
		Props.set_v("controls/parking_brake", true)
	match _phase:
		0:
			if _push and not _pushed and _t >= 2.0:
				_pushed = true
				var fl := get_child(0)
				Props.set_v("controls/parking_brake", false)
				fl.get_node("Controls").parking_brake = false
				fl.get_node("GroundOps").start_pushback()
			if not _cam.is_empty() and not _aimed and _t >= _wait - 5.0:
				_aimed = true
				var fl2 := get_child(0)
				preload("res://tests/showcase_camera.gd").aim(fl2, fl2.get_node("Camera"), _cam)
			if _tree and _t >= _wait - 0.5:
				_tree = false
				var fl3 := get_child(0)
				print("TREE Flight: ", fl3.get_children().map(func(c): return "%s(%s)" % [c.name, c.get_class()]))
				print("TREE Camera: ", fl3.get_node("Camera").get_children().map(func(c): return "%s(%s)" % [c.name, c.get_class()]))
				for k in ["SkyTime", "Weather", "Terminals", "RunwayLights"]:
					var nd := fl3.get_node_or_null(k)
					if nd:
						print("TREE %s: " % k, nd.get_children().map(func(c): return "%s(%s)" % [c.name, c.get_class()]))
						for c in nd.get_children():
							if c.get_child_count() > 0 and c.get_child_count() < 40:
								print("TREE %s/%s: " % [k, c.name], c.get_children().map(func(cc): return "%s(%s)" % [cc.name, cc.get_class()]))
			if _real_lights >= 0 and _t >= _wait - 5.0:
				get_child(0).get_node("RunwayLights").set_real_lights(_real_lights, 0)
				_real_lights = -1
			if (not _hide.is_empty() or not _free.is_empty()) and _t >= _wait - 5.0:  # every frame: lazily built nodes too
				for n in _hide:
					if String(n) == "Camera/CanvasLayers":  # the post-effect layers under the camera (generated names)
						for c in get_child(0).get_node("Camera").get_children():
							if c is CanvasLayer:
								c.visible = false
						continue
					var node := get_child(0).get_node_or_null(String(n))
					if node != null and "visible" in node:
						node.visible = false
				for n in _free:
					var node2 := get_child(0).get_node_or_null(String(n))
					if node2 != null:
						node2.get_parent().remove_child(node2)
						node2.queue_free()
			if _roll > 0.0 and _t >= _wait - _roll:
				for k in ["controls/throttle", "controls/throttle_2"]:
					Props.set_v(k, 1.0)
				for k in ["controls/brake_left", "controls/brake_right"]:
					Props.set_v(k, 0.0)
				Props.set_v("controls/parking_brake", false)
			if _t >= _wait:
				print("FLICKER burst at %.0f kt" % (Props.get_f("fdm/cas_mps") / 0.514444))
				_phase = 1
		1:
			if _sweep:
				OS.delay_msec(randi_range(0, 120))
			_save("burst_%02d.png" % _n)
			_n += 1
			if _n >= _burst:
				_phase = 2
				_n = 0
				_next = _t
		2:
			if _t >= _next:
				_save("spaced_%02d.png" % _n)
				_n += 1
				_next = _t + _spacing
				if _n >= _spaced:
					print("FLICKER DONE fps %.0f" % Engine.get_frames_per_second())
					get_tree().quit()


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(_out.path_join(name))
