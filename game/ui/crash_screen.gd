extends Control
## Landing debrief toast after each touchdown, damage warnings, and the crash screen.
## Reads Props "damage/*" (Damage via FdmNode). F5 restarts (handled by flight.gd).

var airports: AirportBuilder
var _toast: Label
var _toast_t := 0.0
var _crash: Label
var _seen_td := {}
var _events_seen := 0


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_toast = _label(18, Color(1, 1, 1))
	_toast.set_anchors_preset(PRESET_CENTER_TOP)
	_toast.position = Vector2(-330, 70)
	_toast.custom_minimum_size = Vector2(660, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash = _label(26, Color(1, 0.3, 0.25))
	_crash.set_anchors_preset(PRESET_CENTER)
	_crash.position = Vector2(-380, -120)
	_crash.custom_minimum_size = Vector2(760, 0)
	_crash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crash.visible = false


func _label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(l)
	return l


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


## Distance (m) from the nearest runway centreline and along-track from its threshold.
func _runway_offsets(n: float, e: float) -> Array:
	if airports == null or airports.data == null:
		return []
	var best := []
	var bd := INF
	for r in airports.data.runways:
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


func _process(dt: float) -> void:
	var crashed := Props.get_b("damage/crashed")
	_crash.visible = crashed
	if crashed:
		var ev: Array = Props.get_v("damage/events", [])
		_crash.text = "CRASHED — %s\n\n%s\n\nPress F5 to try again" % [Props.get_v("damage/reason", ""), "\n".join(ev.slice(maxi(ev.size() - 4, 0)))]
	var td: Dictionary = Props.get_v("damage/last_touchdown", {})
	if not td.is_empty() and td.get("air_time", 0.0) > 8.0 and not _seen_td.has(td.n):
		_seen_td[td.n] = true
		var off := _runway_offsets(td.n, td.e)
		var where := "off runway!"
		if not off.is_empty():
			where = "%.1f m %s of centreline, %.0f m past the %s threshold" % [off[0], "off" if off[0] > off[4] * 0.5 else "", off[1], off[3]]
			if off[0] > off[4] * 0.5:
				where = "OFF THE RUNWAY EDGE (%.0f m from centreline)" % off[0]
		_toast.text = "Touchdown: %s\n%.0f fpm  ·  %.2f g  ·  %.0f KIAS  ·  pitch %.0f°  bank %.0f°\n%s" % [
			grade(td.sink_fpm, td.g), td.sink_fpm, td.g, td.kias, td.pitch_deg, td.bank_deg, where]
		_toast_t = 9.0
	var events: Array = Props.get_v("damage/events", [])
	if events.size() > _events_seen and not crashed:
		_toast.text = (_toast.text + "\n" if _toast_t > 0.0 else "") + str(events[-1])
		_toast_t = 7.0
	_events_seen = events.size()
	_toast_t -= dt
	_toast.visible = _toast_t > 0.0
