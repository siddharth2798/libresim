class_name CrashScreen
extends Control
## Crash card: dims the scene and shows one clean, centred card with what happened,
## the impact numbers and what to do next (Restart · Watch replay · New flight).
## Non-fatal damage, landing debriefs and failures go to the Notifications stack
## (ui/notifications.gd), created here as a child so the scene needs no extra node.

var airports: AirportBuilder:
	set(v):
		airports = v
		if _notes:
			_notes.airports = v
var _notes: Notifications
var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _reason: Label
var _stats: Label
var _details: Label
var _shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_notes = Notifications.new()
	_notes.airports = airports
	add_child(_notes)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(PRESET_FULL_RECT)
	_dim.mouse_filter = MOUSE_FILTER_STOP
	add_child(_dim)
	_card = PanelContainer.new()
	var st := Notifications.card_style(Notifications.COLORS[Notifications.WARNING])
	st.border_width_left = 0
	st.border_width_top = 4
	st.content_margin_left = 28
	st.content_margin_right = 28
	st.content_margin_top = 20
	st.content_margin_bottom = 20
	st.bg_color = Color(0.06, 0.07, 0.09, 0.94)
	_card.add_theme_stylebox_override("panel", st)
	_card.custom_minimum_size = Vector2(520, 0)
	add_child(Notifications.centered(_card, PRESET_FULL_RECT, 0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_card.add_child(vb)
	_title = _label(vb, 30, Notifications.COLORS[Notifications.WARNING])
	_title.text = "CRASHED"
	_reason = _label(vb, 19, Color.WHITE)
	_stats = _label(vb, 15, Color(0.75, 0.8, 0.85))
	_details = _label(vb, 14, Color(1.0, 0.8, 0.55))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	for b in [["Restart  (F5)", _restart], ["Watch replay  (R)", _replay], ["New flight", _new_flight]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(150, 40)
		btn.pressed.connect(b[1])
		hb.add_child(btn)
	_set_shown(false)


func _label(parent: Control, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(464, 0)
	parent.add_child(l)
	return l


func _set_shown(on: bool) -> void:
	_shown = on
	_dim.visible = on
	_card.visible = on


func _process(_dt: float) -> void:
	var crashed := Props.get_b("damage/crashed") and not Props.get_b("replay/active")
	if crashed and not _shown:
		_fill()
	if crashed != _shown:
		_set_shown(crashed)


func _fill() -> void:
	var reason := str(Props.get_v("damage/reason", "")).strip_edges()
	_reason.text = reason.substr(0, 1).to_upper() + reason.substr(1) if reason != "" else "The aircraft was destroyed."
	_stats.text = "%.0f KIAS  ·  %+.0f fpm  ·  %.1f g" % [Units.mps_to_kt(Props.get_f("fdm/cas_mps")),
		Units.mps_to_fpm(Props.get_f("fdm/vs_mps")), Props.get_f("fdm/load_factor")]
	var seen := {}
	var lines := []
	for e in Props.get_v("damage/events", []):
		var s := str(e)
		if s.begins_with("CRASH") or seen.has(s):
			continue
		seen[s] = true
		lines.append("• " + s)
	_details.text = "\n".join(lines.slice(maxi(lines.size() - 4, 0)))
	_details.visible = not lines.is_empty()


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


func _restart() -> void:
	_press(KEY_F5)


func _replay() -> void:
	var r := get_tree().current_scene.get_node_or_null("Replay")
	if r:
		r.start_replay(30.0)


func _new_flight() -> void:
	Session.skip_menu = false
	get_tree().change_scene_to_file("res://ui/menu/start_screen.tscn")


static func grade(fpm: float, g: float) -> String:
	if fpm < 120.0 and g < 1.3:
		return "BUTTER"
	if fpm < 300.0:
		return "SMOOTH"
	if fpm < 600.0:
		return "FIRM"
	if fpm < 900.0:
		return "HARD — gear inspection"
	return "DAMAGED"


## [distance from centreline m, along-track from threshold m, airport, ident, width] or [].
static func runway_offsets(ab: AirportBuilder, n: float, e: float) -> Array:
	if ab == null or ab.data == null:
		return []
	var best := []
	var bd := INF
	for r in ab.data.runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var u := (b - a).normalized()
		var p := Vector2(e, n)
		var along := (p - a).dot(u)
		if along < -100.0 or along > a.distance_to(b) + 100.0:
			continue
		var cross := absf((p - a).cross(u))
		if cross < bd:
			bd = cross
			best = [cross, along, r.airport, r.ends[0].ident, float(r.width)]
	return best
