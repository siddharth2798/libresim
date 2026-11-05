extends Node
## Live probe for joysticks and gamepads: prints every connected pad (index, name, guid) and then every axis and button
## change, to read a device's real numbers (used to calibrate the Thrustmaster TCA Captain Pack, core/input_profiles.gd).
## Windowed (a joystick only reaches a focused window on macOS), muted, always on top. Writes only the log file.
##
##   ~/.local/bin/godot --path game --windowed --resolution 640x360 --audio-driver Dummy res://tests/probe_pads.tscn \
##       -- --out=/path/to/log.txt [--seconds=120] [--eps=0.04] [--settle=0.5]
##
## Log lines (t = seconds since start):
##   PAD <index> <name> guid=<guid>
##   MOVE t=<s> pad=<i> axis=<n> v=<value>      first sight of a movement (axis left its rest value by > eps)
##   SETTLED t=<s> pad=<i> axis=<n> v=<value>   the axis has been still for `settle` seconds: a detent or end stop
##   RANGE pad=<i> axis=<n> min=<v> max=<v> rest=<v>   at the end, every axis that moved
##   BTN t=<s> pad=<i> button=<n> down|up
##   KEY t=<s> <key>                            a keyboard key (digits, letters, space) used as a marker: press 1 before
##                                              moving control 1, etc., so the log says which control a line belongs to
## The window shows the same lines, newest last.

var _out := ""
var _seconds := 120.0
var _eps := 0.04
var _settle := 0.5
var _t := 0.0
var _file: FileAccess
var _label: Label
var _lines: PackedStringArray = []
var _rest := {}  # "pad:axis" -> first value seen
var _last := {}  # "pad:axis" -> last logged value
var _min := {}
var _max := {}
var _still := {}  # "pad:axis" -> seconds since the value last changed
var _cur := {}
var _pending := {}  # "pad:axis" -> true while a movement has not settled yet
var _relisted := 0


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
		elif a.begins_with("--eps="):
			_eps = float(a.substr(6))
		elif a.begins_with("--settle="):
			_settle = float(a.substr(9))
	if _out != "":
		_file = FileAccess.open(_out, FileAccess.WRITE)
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)
	for p in Input.get_connected_joypads():
		_log("PAD %d %s guid=%s" % [p, Input.get_joy_name(p), Input.get_joy_guid(p)])
	if Input.get_connected_joypads().is_empty():
		_log("NO PADS CONNECTED (is the window focused? replug and rerun)")
	Input.joy_connection_changed.connect(func(d: int, on: bool): _log("PAD %s %d %s" % ["connected" if on else "disconnected", d, Input.get_joy_name(d)]))


func _input(e: InputEvent) -> void:
	if e is InputEventJoypadMotion:
		var k := "%d:%d" % [e.device, e.axis]
		var v: float = e.axis_value
		if not _rest.has(k):
			_rest[k] = v
			_last[k] = v
			_min[k] = v
			_max[k] = v
		_cur[k] = v
		_min[k] = minf(_min[k], v)
		_max[k] = maxf(_max[k], v)
		_still[k] = 0.0
		if absf(v - _last[k]) > _eps:
			if not _pending.get(k, false):
				_log("MOVE t=%.2f pad=%d axis=%d v=%.3f" % [_t, e.device, e.axis, v])
			_pending[k] = true
	elif e is InputEventKey and e.pressed and not e.echo:
		_log("KEY t=%.2f %s" % [_t, OS.get_keycode_string(e.keycode)])
	elif e is InputEventJoypadButton:
		_log("BTN t=%.2f pad=%d button=%d %s" % [_t, e.device, e.button_index, "down" if e.pressed else "up"])


func _process(dt: float) -> void:
	_t += dt
	if _relisted < 3 and _t > 2.0 * (_relisted + 1):
		_relisted += 1
		var ids := Input.get_connected_joypads()
		_log("pads at t=%.0f s: %s" % [_t, str(ids)])
		for p in ids:
			_log("PAD %d %s guid=%s" % [p, Input.get_joy_name(p), Input.get_joy_guid(p)])
	for k in _pending.keys():
		_still[k] = _still.get(k, 0.0) + dt
		if _still[k] >= _settle:
			var parts: PackedStringArray = k.split(":")
			_log("SETTLED t=%.2f pad=%s axis=%s v=%.3f" % [_t, parts[0], parts[1], _cur[k]])
			_last[k] = _cur[k]
			_pending.erase(k)
	if _t >= _seconds:
		_finish()


func _finish() -> void:
	set_process(false)
	for k in _rest:
		if _max[k] - _min[k] > 2.0 * _eps:
			var parts: PackedStringArray = k.split(":")
			_log("RANGE pad=%s axis=%s min=%.3f max=%.3f rest=%.3f" % [parts[0], parts[1], _min[k], _max[k], _rest[k]])
	_log("DONE")
	if _file:
		_file.close()
	get_tree().quit()


func _log(s: String) -> void:
	print(s)
	if _file:
		_file.store_line(s)
		_file.flush()
	_lines.append(s)
	if _lines.size() > 22:
		_lines = _lines.slice(_lines.size() - 22)
	if _label:
		_label.text = "\n".join(_lines)
