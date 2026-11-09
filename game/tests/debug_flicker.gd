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
var _aimed := false
var _t := 0.0
var _n := 0
var _phase := 0  # 0 waiting, 1 burst, 2 spaced
var _next := 0.0


func _ready() -> void:
	var view := "cockpit"
	var air := []
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"out": _out = kv[1]
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
	Session.view = view
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(load("res://world/flight.tscn").instantiate())


func _process(dt: float) -> void:
	_t += dt
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
