class_name Callouts
extends Control
## Optional training callouts (Options page, or K in flight): shows each call as large text
## above the hint line and, if "Speak callouts" is on and the system has a voice, says it
## with the OS text-to-speech. Logic is in systems/callout_logic.gd. Off by default.

var _state := CalloutLogic.new_state()
var _label: Label
var _t := 0.0
var _voice := ""


func _ready() -> void:
	add_to_group("callouts")
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 8)
	_label.visible = false
	add_child(Notifications.centered(_label, PRESET_BOTTOM_WIDE, -170))
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if not voices.is_empty():
			_voice = voices[0]


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_K and not e.ctrl_pressed and not e.alt_pressed:
		var on := not bool(UserOptions.get_v("callouts"))
		UserOptions.set_v("callouts", on)
		_state = CalloutLogic.new_state()
		var n := get_parent()
		if n is Notifications:
			n.post("Training callouts " + ("on" if on else "off"), "K toggles. Speech and options: start screen → Options.", Notifications.INFO, "callouts")


func _process(dt: float) -> void:
	_t -= dt
	_label.visible = _t > 0.0
	_label.modulate.a = clampf(_t / 0.4, 0.0, 1.0)
	var on := bool(UserOptions.get_v("callouts")) or (Session.training != "" and Session.assist != "off")  # lessons always call
	if not on or Props.get_b("replay/active") or Props.get_b("damage/crashed"):
		return
	var calls := CalloutLogic.step(_state, {
		"ias": Units.mps_to_kt(Props.get_f("fdm/cas_mps")), "agl": Units.m_to_ft(Props.get_f("fdm/agl_m")),
		"vs": Units.mps_to_fpm(Props.get_f("fdm/vs_mps")), "wow": Props.get_b("fdm/wow"),
		"bank": rad_to_deg(Props.get_f("fdm/roll_rad")), "throttle": Props.get_f("controls/throttle")},
		Time.get_ticks_msec() / 1000.0)
	for c in calls:
		_show(c[0], int(c[1]))


## Say a line with the system voice (if "Speak callouts" is on and a voice exists).
func speak(text: String) -> void:
	if _voice != "" and bool(UserOptions.get_v("callouts_voice")):
		DisplayServer.tts_speak(text, _voice, 70, 1.0, 1.05, 0, false)


func _show(text: String, level: int) -> void:
	_label.text = text.to_upper()
	_label.add_theme_color_override("font_color", Notifications.COLORS[Notifications.CAUTION] if level == 1 else Color(1, 1, 1))
	_t = 1.6
	if _voice != "" and bool(UserOptions.get_v("callouts_voice")):
		DisplayServer.tts_speak(text, _voice, 70, 1.0, 1.15, 0, true)
