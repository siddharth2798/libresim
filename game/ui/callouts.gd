class_name Callouts
extends Control
## Optional training callouts (Options page, or K in flight): shows each call as large text
## above the hint line and, if "Speak callouts" is on and the system has a voice, says it
## with the OS text-to-speech (core/speech_service.gd; nothing speech-related runs at start-up
## while that option is off). Logic is in systems/callout_logic.gd. Off by default.

var _state := CalloutLogic.new_state()
var _label: Label
var _t := 0.0
var _limits := {}  # the aircraft's speeds (aircraft.json limits)
var _own := {}  # aircraft.json "callouts": alive_kt, rotate_kt, v1_kt, low_kt, heights (override the limits-derived inputs)


func _ready() -> void:
	_limits = AircraftDef.current().section("limits")
	_own = AircraftDef.current().section("callouts")
	add_to_group("callouts")
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 34)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 8)
	_label.visible = false
	add_child(Notifications.centered(_label, PRESET_BOTTOM_WIDE, -170))
	if _voice_on():
		SpeechService.request()  # saved setting: start the voice probe now so the first call is heard


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
	if _voice_on():
		SpeechService.status()  # lets the one-time voice probe finish early (about 0.4 s of work)
	_label.visible = _t > 0.0
	_label.modulate.a = clampf(_t / 0.4, 0.0, 1.0)
	var on := bool(UserOptions.get_v("callouts")) or (Session.training != "" and Session.assist != "off")  # lessons always call
	if not on or Props.get_b("replay/active") or Props.get_b("damage/crashed"):
		return
	var calls := CalloutLogic.step(_state, {
		"ias": Units.mps_to_kt(Props.get_f("fdm/cas_mps")), "agl": Units.m_to_ft(Props.get_f("fdm/agl_m")),
		"vs": Units.mps_to_fpm(Props.get_f("fdm/vs_mps")), "wow": Props.get_b("fdm/wow"),
		"bank": rad_to_deg(Props.get_f("fdm/roll_rad")), "throttle": Props.get_f("controls/throttle"),
		"alive_kt": float(_limits.get("vs0_kias", CalloutLogic.ALIVE_KT)), "rotate_kt": float(_limits.get("vr_kias", CalloutLogic.ROTATE_KT))}.merged(_own),
		Time.get_ticks_msec() / 1000.0)
	for c in calls:
		_show(c[0], int(c[1]))


static func _voice_on() -> bool:
	return bool(UserOptions.get_v("callouts_voice"))


## Say a line with the system voice (if "Speak callouts" is on and a voice exists).
func speak(text: String) -> void:
	if _voice_on():
		SpeechService.speak(text, SpeechService.Kind.CALLOUT, false, 1.05)


func _show(text: String, level: int) -> void:
	_label.text = text.to_upper()
	_label.add_theme_color_override("font_color", Notifications.COLORS[Notifications.CAUTION] if level == 1 else Color(1, 1, 1))
	_t = 1.6
	if _voice_on():
		SpeechService.speak(text, SpeechService.Kind.CALLOUT, true, 1.15)
