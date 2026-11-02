class_name TaxiBanner
extends Node
## The taxi / pushback instruction on screen (replaces the old centred label that never went away).
## It is one compact card in the notification stack (top-centre, under the flight-data bar), so it
## never covers the view or other cards; it stays 8-12 s and fades by itself (atc/taxi_banner_logic.gd),
## Backspace dismisses it at once, and it goes when the aircraft starts taxiing, the route ends,
## or a newer instruction replaces it. What stays is a tiny line in the radio bar (Props
## ops/taxi_hint: the route and the distance left) and a line in the radio History (the radio panel
## reads Props ops/taxi_msg). GroundOps owns this node and only calls announce / say / route_progress.

const KEY := "taxi"
const ACCENT := Color(0.3, 0.9, 0.45)

var logic := TaxiBannerLogic.new()
var text: String:
	get:
		return logic.text if logic.alive() else ""
var _panel: PanelContainer
var _label: Label
var _route_hint := ""
var _push_hint := ""
var _hold_said := false
var _serial := 0
var _advice := TaxiAdvice.new()  # taxi speed note (ground.max_taxi_kt; none for the C172)
var _max_kt := 0.0
var _hold_m := 40.0  # "hold short" call distance (ground.hold_short_m)


func _ready() -> void:
	Props.set_v("ops/taxi_msg", {})
	Props.set_v("ops/taxi_hint", "")
	_max_kt = GroundParams.max_taxi_kt()
	_hold_m = float(GroundParams.ground().hold_short_m)


## A taxi instruction (a new route): a banner of 8-12 s, 12 s the first time after landing.
func announce(txt: String) -> void:
	_hold_said = false
	var first := str(Props.get_v("atc/state", "")) in ["landed", "vacated"]
	_show(txt, TaxiBannerLogic.life_for(txt, first, false), true)
	_log(txt)


## A plain note ("No taxi route found", "Pushback complete..."); `hint` is the small bar line that
## stays while it applies (pushback), "" for none.
func say(txt: String, hint := "") -> void:
	_push_hint = hint
	_show(txt, TaxiBannerLogic.life_for(txt, false, true), false)
	_publish_hint()


## Each frame while a route is active: the small bar line with the distance left, and the one-time
## "hold short" call near the end of a runway route.
func route_progress(txt: String, rem_m: float, hold_at_end: bool) -> void:
	_route_hint = "%s  ·  %d m" % [txt, int(round(rem_m))]
	if TaxiBannerLogic.hold_short_due(rem_m, hold_at_end, _hold_said, _hold_m):
		_hold_said = true
		var t := "Hold short — contact Tower for takeoff"
		_show(t, TaxiBannerLogic.life_for(t, false, false), true)
		_log(t)
	_publish_hint()


## The route ended (arrived at the stand, or cleared with T): its banner goes, the bar line too.
func route_cleared() -> void:
	_route_hint = ""
	if logic.is_route:
		dismiss()
	_publish_hint()


func dismiss() -> void:
	if not logic.alive():
		return
	logic.dismiss()
	var notes := _notes()
	if notes != null:
		notes.dismiss(KEY)


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_BACKSPACE and not (e.ctrl_pressed or e.alt_pressed or e.shift_pressed) and logic.alive():
		dismiss()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if _route_hint != "":  # advice only while a taxi route is active
		var note := _advice.tick(dt, Props.get_f("fdm/groundspeed_mps"), _max_kt)
		if note != "":
			say(note, _push_hint)
	if logic.alive() and logic.tick(dt, Props.get_f("fdm/groundspeed_mps")) == "moving":
		var notes := _notes()
		if notes != null:
			notes.dismiss(KEY)


func _notes() -> Notifications:
	return get_tree().get_first_node_in_group("notifications") as Notifications if is_inside_tree() else null


func _show(txt: String, life: float, route: bool) -> void:
	logic.show(txt, life, Props.get_f("fdm/groundspeed_mps") < TaxiBannerLogic.STILL_SPEED, route)
	var notes := _notes()
	if notes == null:
		return
	if _panel == null or not is_instance_valid(_panel) or not notes.has(KEY):
		_build()
		_label.text = txt
		notes.adopt(_panel, life, KEY)
	else:
		_label.text = txt
		notes.touch(KEY, life)


func _build() -> void:
	_panel = PanelContainer.new()
	var st := Notifications.card_style(ACCENT)
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", st)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vb)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(412, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_label)
	var h := Label.new()
	h.text = "Backspace  dismiss"
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", Color(0.55, 0.65, 0.72))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(h)


func _publish_hint() -> void:
	Props.set_v("ops/taxi_hint", _push_hint if _push_hint != "" else _route_hint)


## The instruction goes to the radio History (the radio panel appends it as a note).
func _log(txt: String) -> void:
	_serial += 1
	Props.set_v("ops/taxi_msg", {"n": _serial, "text": txt})
