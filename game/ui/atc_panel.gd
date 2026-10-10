extends PanelContainer
## Text ATC (phase A; voice comes with M9). Backquote (`) opens the radio menu; while
## it is open, 1-6 pick a call (the menu swallows the keys, so camera views don't change).
## Phraseology follows ICAO/Indian AIP style; values come from the sim:
## airport, into-wind runway (GroundOps), taxi route via OSM taxiway refs, weather
## wind/QNH, a squawk code. The log shows the last few transmissions.

var ground_ops: GroundOps
var fdm_node: FdmNode
var _menu: Label
var _log: Label
var _lines: Array[String] = []
var _open := false
var _squawk := ""
var _callsign := "VT-FSM"


func _ready() -> void:
	set_anchors_preset(PRESET_TOP_RIGHT)
	position = Vector2(-470, 120)
	custom_minimum_size = Vector2(460, 0)
	modulate = Color(1, 1, 1, 0.92)
	var vb := VBoxContainer.new()
	add_child(vb)
	_log = Label.new()
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD
	_log.add_theme_font_size_override("font_size", 14)
	vb.add_child(_log)
	_menu = Label.new()
	_menu.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vb.add_child(_menu)
	visible = false
	_squawk = "%d%d%d%d" % [randi_range(2, 6), randi_range(0, 7), randi_range(0, 7), randi_range(0, 7)]


func _apt() -> String:
	return ground_ops._airport_here() if ground_ops else ""


func _rwy() -> String:
	var a := _apt()
	if a == "":
		return "??"
	var e: Dictionary = ground_ops._best_runway_end(a)
	return str(e.get("ident", "??"))


func _wind() -> String:
	var dir := Props.get_f("weather/wind_dir_deg")
	var kt := Props.get_f("weather/wind_kt")
	return "calm" if kt < 3.0 else "%03d degrees %d knots" % [int(round(dir / 10.0) * 10.0) % 360, int(kt)]


func _qnh() -> String:
	return "%d" % int(round(Props.get_f("weather/qnh_hpa", 1013.0)))


func _say(who: String, text: String) -> void:
	_lines.append("%s: %s" % [who, text])
	_lines = _lines.slice(maxi(_lines.size() - 6, 0))
	_log.text = "\n".join(_lines)
	visible = true


func _calls() -> Array:
	var a := _apt()
	var r := _rwy()
	var on_ground := Props.get_b("fdm/wow")
	return [
		["Listen to ATIS", func():
			_say(a + " ATIS", "Information Alpha. Runway %s in use. Wind %s. Visibility %d km. QNH %s. Temperature %d. Acknowledge Alpha on first contact." % [
				r, _wind(), int(Props.get_f("weather/visibility_m") / 1000.0), _qnh(), int(Props.get_f("weather/temp_c"))])],
		["Clearance delivery: request VFR departure", func():
			_say("You", "%s Delivery, %s, Cessna 172 at %s, information Alpha, request VFR departure." % [a, _callsign, Props.get_v("ops/stand", "the apron")])
			_say(a + " Delivery", "%s, cleared VFR, departure runway %s, climb not above 2000 feet, squawk %s." % [_callsign, r, _squawk])],
		["Ground: request taxi", func():
			if not on_ground:
				_say(a + " Ground", "%s, you appear airborne, contact Tower." % _callsign)
				return
			ground_ops.request_taxi()
			var route: String = Props.get_v("ops/taxi_route", "")
			_say("You", "%s Ground, %s, ready to taxi." % [a, _callsign])
			_say(a + " Ground", "%s, %s, QNH %s." % [_callsign, route.replace("Taxi", "taxi") if route != "" else "taxi to holding point runway " + r, _qnh()])],
		["Tower: ready for departure", func():
			_say("You", "%s Tower, %s, holding point runway %s, ready for departure." % [a, _callsign, r])
			_say(a + " Tower", "%s, wind %s, runway %s, cleared for takeoff." % [_callsign, _wind(), r])],
		["Tower: inbound / request landing", func():
			var alt := int(Units.m_to_ft(Props.get_f("fdm/alt_m")) / 100.0) * 100
			_say("You", "%s Tower, %s, Cessna 172, %d feet, inbound for landing." % [a, _callsign, alt])
			_say(a + " Tower", "%s, join final runway %s, report final. QNH %s." % [_callsign, r, _qnh()])],
		["Tower: on final", func():
			_say("You", "%s, final runway %s." % [_callsign, r])
			_say(a + " Tower", "%s, wind %s, runway %s, cleared to land." % [_callsign, _wind(), r])],
	]


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_QUOTELEFT:
		_open = not _open
		visible = _open or not _lines.is_empty()
		_update_menu()
		get_viewport().set_input_as_handled()
	elif _open and e.keycode >= KEY_1 and e.keycode <= KEY_6:
		var c: Array = _calls()[e.keycode - KEY_1]
		c[1].call()
		_open = false
		_update_menu()
		get_viewport().set_input_as_handled()


func _update_menu() -> void:
	if not _open:
		_menu.text = "` radio"
		return
	var t := "RADIO — press 1-6 (` to close)\n"
	var calls := _calls()
	for i in calls.size():
		t += "%d  %s\n" % [i + 1, calls[i][0]]
	_menu.text = t
