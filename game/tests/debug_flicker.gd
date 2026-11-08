extends Node
## Debug: flicker hunt. Starts a flight (optionally a saved last_flight.json), waits for the scenery to stream in,
## then saves a burst of consecutive frames and a few spaced ones, so a diff shows what blinks from frame to frame.
## Needs a display. Run:
##   godot --path game --resolution 1920x1080 res://tests/debug_flicker.tscn -- --out=<dir> [--setup=<json>]
##       [--view=cockpit] [--wait=25] [--burst=12] [--spaced=6] [--spacing=0.25] [--roll=<s>]
## --roll=<s>: full thrust and brakes off this many seconds before the burst, to see the picture while moving.
## Writes <dir>/burst_NN.png (one per rendered frame) and <dir>/spaced_NN.png, then quits.

var _out := ""
var _wait := 25.0
var _burst := 12
var _spaced := 6
var _spacing := 0.25
var _roll := -1.0
var _t := 0.0
var _n := 0
var _phase := 0  # 0 waiting, 1 burst, 2 spaced
var _next := 0.0


func _ready() -> void:
	var view := "cockpit"
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
			"setup":
				var d = JSON.parse_string(FileAccess.get_file_as_string(kv[1]))
				for k in d:
					if Session.setup.has(k):
						Session.setup[k] = d[k]
	Session.view = view
	DirAccess.make_dir_recursive_absolute(_out)
	add_child(load("res://world/flight.tscn").instantiate())


func _process(dt: float) -> void:
	_t += dt
	match _phase:
		0:
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
