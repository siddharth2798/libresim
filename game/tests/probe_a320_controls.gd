extends Node
## Live check of the Thrustmaster Captain Pack mapping through the game's real input code: loads the profile
## (core/input_profiles.gd) for an aircraft, runs a JoystickControls node on the live pads and prints a line whenever a
## control property changes, with the hardware values that caused it. Windowed (on macOS a joystick reaches only the active
## window unless SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS is set), muted, always on top. Writes nothing except the optional --out
## log; the table is the profile, never the saved input_bindings.json.
##   SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 ~/.local/bin/godot --path game --windowed \
##       --resolution 960x540 --audio-driver Dummy res://tests/probe_a320_controls.tscn \
##       -- [--aircraft=a320|c172] [--seconds=60] [--air] [--out=/path/log.txt]
## Line format:   t=<s> <property> <old> -> <new>  [<detail>]  | hw: pad0 axis0=-0.485 pad0 btn20=down
##   detail = lever position and detent name for a thrust lever, the flap setting name for the flaps.
##   hw = pad axes (moved by more than 0.004) and buttons that changed in that frame; empty = start-up sync.
##   --air starts with the wheels off the ground (fdm/wow false): the A320 flaps lever notch 1 then gives CONF 1, not 1+F.

const WATCH := ["throttle", "throttle_1", "throttle_2", "reverse_1", "reverse_2", "mixture", "flaps", "speedbrake",
	"engine_mode", "engine_master_1", "engine_master_2", "gear", "autobrake", "parking_brake", "magnetos", "starter",
	"brake_left", "brake_right", "pitch", "roll", "yaw", "pitch_trim", "joystick_active"]
const EPS := 0.004

var _id := "a320"
var _seconds := 60.0
var _air := false
var _t := 0.0
var _file: FileAccess
var _label: Label
var _lines: PackedStringArray = []
var _ctl: AircraftControls
var _joy: JoystickControls
var _flap_names: Array = []
var _prop_last := {}  # watched name -> last printed value
var _hw_prev := {}  # "pad:axis:n" / "pad:btn:n" -> value
var _relisted := 0


func _ready() -> void:
	process_priority = 100  # after JoystickControls: its properties of this frame are ours to read
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aircraft="):
			_id = a.substr(11)
		elif a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--air":
			_air = true
	if out != "":
		_file = FileAccess.open(out, FileAccess.WRITE)
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_font_size_override("font_size", 13)
	add_child(_label)
	Session.save_path = "user://probe_a320_unused.json"  # never the real saved setup (and it is not saved anyway)
	Session.setup["aircraft"] = _id
	var def := AircraftDef.load_def(_id)
	_ctl = AircraftControls.for_def(def)
	_ctl.seed_props()
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/%s/config.json" % _id))
	var fl = cfg.get("controls", {}).get("flaps") if cfg is Dictionary else null
	var dets = fl.get("detents", []) if fl is Dictionary else (fl if fl is Array else [])
	for i in dets.size():
		_flap_names.append(str(dets[i].get("lever", i)) if dets[i] is Dictionary else str(i))
	Props.set_v("fdm/flap_detents", maxi(dets.size(), 4))
	Props.set_v("fdm/wow", not _air)
	_joy = JoystickControls.new()
	add_child(_joy)
	_joy.table = InputBindings.defaults(InputProfiles.CAPTAIN_PACK)  # the profile, not the saved file
	_joy._rev = int(Props.get_v("input/bindings_rev", 0))
	_log("probe: aircraft %s (%s), profile captain_pack on %s, wheels %s, %.0f s" % [
		_id, def.id, OS.get_name(), "off the ground" if _air else "on the ground", _seconds])
	_list_pads()
	Input.joy_connection_changed.connect(func(d: int, on: bool): _log("PAD %s %d %s" % ["connected" if on else "disconnected", d, Input.get_joy_name(d)]))
	_log("offered axes: %s" % [_ctl.axes()])
	_log("offered buttons: %s" % [_ctl.buttons()])


func _list_pads() -> void:
	var ids := Input.get_connected_joypads()
	if ids.is_empty():
		_log("NO PADS CONNECTED (macOS: start with SDL_JOYSTICK_MFI=0, keep the window active or set SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1)")
	for p in ids:
		_log("PAD %d %s guid=%s" % [p, Input.get_joy_name(p), Input.get_joy_guid(p)])
	if _relisted == 0:
		for a in ["throttle", "throttle_2", "speedbrake", "flaps_lever", "roll", "pitch", "yaw"]:
			var b: Dictionary = _joy.table[a]
			_log("  %s -> %s axis %d (%s)" % [a, "pad %d" % InputBindings.resolve_device(b) if InputBindings.resolve_device(b) >= 0 else "NO PAD", b.axis, b.name])
		for a in ["gear_switch", "engine_master_1_switch", "engine_mode_crank", "engine_mode_ign", "autobrake_btv", "autobrake_hi", "parking_brake_switch"]:
			var b: Dictionary = _joy.table[a]
			_log("  %s -> %s button %d (%s)" % [a, "pad %d" % InputBindings.resolve_device(b) if InputBindings.resolve_device(b) >= 0 else "NO PAD", b.button, b.name])


## The hardware that changed this frame: pad axes beyond EPS, buttons toggled.
func _hw_changes() -> PackedStringArray:
	var out: PackedStringArray = []
	for p in Input.get_connected_joypads():
		for ax in range(0, 8):
			var v := Input.get_joy_axis(p, ax)
			var k := "%d:axis:%d" % [p, ax]
			if absf(v - float(_hw_prev.get(k, 0.0))) > EPS:
				out.append("pad%d axis%d=%.3f" % [p, ax, v])
				_hw_prev[k] = v
		for bt in range(0, 32):
			var down := Input.is_joy_button_pressed(p, bt)
			var k := "%d:btn:%d" % [p, bt]
			if down != bool(_hw_prev.get(k, false)):
				out.append("pad%d btn%d=%s" % [p, bt, "down" if down else "up"])
				_hw_prev[k] = down
	return out


func _value(name: String) -> Variant:
	if name == "throttle_1" and _ctl.levers.count < 2:
		return null
	return Props.get_v("controls/" + name) if Props.has("controls/" + name) else null


func _detail(name: String, v: Variant) -> String:
	if name == "flaps" and not _flap_names.is_empty():
		return "flap setting %s" % _flap_names[clampi(int(v), 0, _flap_names.size() - 1)]
	var lever := {"throttle_1": 0, "throttle_2": 1, "reverse_1": 0, "reverse_2": 1}
	if lever.has(name) and _ctl.levers.count >= 2:
		var pos := _ctl.levers.pos(lever[name])
		return "lever %d at %.3f %s" % [lever[name] + 1, pos, LeverDetents.name_at(pos, _ctl.levers.detents, 0.01)]
	return ""


func _process(dt: float) -> void:
	_t += dt
	var hw := _hw_changes()
	for name in WATCH:
		var v: Variant = _value(name)
		if v == null:
			continue
		var last: Variant = _prop_last.get(name)
		var changed: bool = last == null or (absf(float(v) - float(last)) > 0.005 if (typeof(v) == TYPE_FLOAT and typeof(last) == TYPE_FLOAT) else v != last)
		if not changed:
			continue
		_prop_last[name] = v
		var d := _detail(name, v)
		_log("t=%.2f %s %s -> %s%s  | hw: %s" % [_t, name, "-" if last == null else _fmt(last), _fmt(v), "  [%s]" % d if d != "" else "", " ".join(hw)])
	if _relisted < 3 and _t > 2.0 * (_relisted + 1):
		_relisted += 1
		_list_pads()
	if _t >= _seconds:
		_log("DONE")
		if _file:
			_file.close()
		get_tree().quit()


func _fmt(v: Variant) -> String:
	return "%.3f" % v if typeof(v) == TYPE_FLOAT else str(v)


func _log(s: String) -> void:
	print(s)
	if _file:
		_file.store_line(s)
		_file.flush()
	_lines.append(s)
	if _lines.size() > 30:
		_lines = _lines.slice(_lines.size() - 30)
	if _label:
		_label.text = "\n".join(_lines)
