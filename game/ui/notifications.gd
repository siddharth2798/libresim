class_name Notifications
extends Control
## One place for every in-flight message, MSFS-style: a short stack of cards at the
## top-centre (below the flight-data bar). Levels: INFO (blue), CAUTION (amber),
## WARNING (red). Identical messages merge ("×3") instead of piling up; cards fade out.
## Sources polled here (modules only talk via Props): damage/events, damage/last_touchdown
## (landing debrief), failures/event. Persistent banners: STALL, ENGINE STOPPED hint.
## Other UI can call post() directly.

enum { INFO, CAUTION, WARNING }
const COLORS := [Color(0.35, 0.7, 1.0), Color(1.0, 0.72, 0.2), Color(1.0, 0.3, 0.25)]
const MAX_CARDS := 3
const LIFE := [5.0, 7.0, 8.0]

var airports: AirportBuilder
var _stack: VBoxContainer
var _cards: Array = []  # [{key, panel, title, detail, count, t, level}]
var _stall: PanelContainer
var _hint: Label
var _events_seen := 0
var _seen_td := {}
var _failed := {}  # failure id -> true while failed
var _pulse := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.custom_minimum_size = Vector2(440, 0)
	_stack.add_theme_constant_override("separation", 6)
	_stack.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(centered(_stack, PRESET_TOP_WIDE, 72))
	_stall = _banner("STALL", COLORS[WARNING])
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	add_child(centered(_hint, PRESET_BOTTOM_WIDE, -40))


## Wrap c in a CenterContainer spanning `preset` (TOP_WIDE / BOTTOM_WIDE / FULL_RECT),
## pushed down (or up, if negative) by `offset` px: robust centring whatever c's size.
static func centered(c: Control, preset: int, offset: float) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = MOUSE_FILTER_IGNORE
	cc.set_anchors_and_offsets_preset(preset)
	if preset == PRESET_TOP_WIDE:
		cc.offset_top = offset
		cc.offset_bottom = offset
		cc.grow_vertical = GROW_DIRECTION_END
	elif preset == PRESET_BOTTOM_WIDE:
		cc.offset_top = offset
		cc.offset_bottom = offset
		cc.grow_vertical = GROW_DIRECTION_BEGIN
	cc.use_top_left = false
	cc.add_child(c)
	return cc


static func card_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.1, 0.82)
	s.set_corner_radius_all(8)
	s.border_width_left = 4
	s.border_color = accent
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _banner(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := card_style(col)
	s.border_width_left = 0
	s.bg_color = Color(col.r * 0.55, col.g * 0.15, col.b * 0.12, 0.85)
	p.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	p.add_child(l)
	p.visible = false
	p.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(centered(p, PRESET_TOP_WIDE, 210))
	return p


## Show a message. Same key (default: title) within its lifetime merges into one card.
func post(title: String, detail := "", level := INFO, key := "") -> void:
	key = key if key != "" else title
	for c in _cards:
		if c.key == key:
			c.count += 1
			c.t = LIFE[level]
			c.title_l.text = title + ("   ×%d" % c.count if c.count > 1 else "")
			if detail != "":
				c.detail_l.text = detail
			return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(COLORS[level]))
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 17)
	tl.add_theme_color_override("font_color", COLORS[level].lerp(Color.WHITE, 0.35))
	vb.add_child(tl)
	var dl := Label.new()
	dl.text = detail
	dl.visible = detail != ""
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(412, 0)
	dl.add_theme_font_size_override("font_size", 14)
	dl.add_theme_color_override("font_color", Color(0.86, 0.88, 0.9))
	vb.add_child(dl)
	_stack.add_child(p)
	_cards.append({"key": key, "panel": p, "title_l": tl, "detail_l": dl, "count": 1, "t": LIFE[level], "level": level})
	while _cards.size() > MAX_CARDS:
		_drop(_cards[0])


func _drop(c: Dictionary) -> void:
	_cards.erase(c)
	c.panel.queue_free()


func _process(dt: float) -> void:
	_poll_sources()
	for c in _cards.duplicate():
		c.t -= dt
		c.panel.modulate.a = clampf(c.t / 0.6, 0.0, 1.0)
		if c.t <= 0.0:
			_drop(c)
	var crashed := Props.get_b("damage/crashed")
	_pulse += dt * 5.0
	_stall.visible = Props.get_b("fdm/stall_warning") and not crashed
	_stall.modulate.a = 0.75 + 0.25 * sin(_pulse)
	var hint := ""
	if not crashed and not Props.get_b("engine/running") and Props.get_f("engine/rpm") < 300.0 and not Props.get_b("failures/engine"):
		hint = "Engine stopped — mixture rich, magnetos BOTH (M), hold S to start"
	_hint.text = hint


func _poll_sources() -> void:
	var events: Array = Props.get_v("damage/events", [])
	if events.size() < _events_seen:
		_events_seen = 0  # reset / new flight
	for i in range(_events_seen, events.size()):
		var e := str(events[i])
		if e.begins_with("CRASH"):
			continue  # the crash card shows it
		var parts := e.split(" — ", true, 1)
		var lvl := WARNING if e.to_lower().contains("collapsed") or e.to_lower().contains("damaged") else CAUTION
		post(parts[0], parts[1] if parts.size() > 1 else "", lvl, "dmg:" + parts[0].get_slice(":", 0))  # one card per kind (numbers differ)
	_events_seen = events.size()
	var tell := bool(Session.setup.get("notify", true))  # off = find out from the instruments
	for id in FailureCatalog.all_ids():
		var f := Props.get_b("failures/" + id)
		if f and not _failed.has(id) and tell:
			post(FailureCatalog.label(id), "System failure — F9 for details", WARNING, "fail:" + id)
		if f:
			_failed[id] = true
		else:
			_failed.erase(id)
	var td: Dictionary = Props.get_v("damage/last_touchdown", {})
	if not td.is_empty() and td.get("air_time", 0.0) > 8.0 and not _seen_td.has(td.n):
		_seen_td[td.n] = true
		_touchdown(td)


func _touchdown(td: Dictionary) -> void:
	var g := CrashScreen.grade(td.sink_fpm, td.g)
	var where := ""
	var off := CrashScreen.runway_offsets(airports, td.n, td.e)
	if off.is_empty():
		where = "Off airport"
	elif off[0] > off[4] * 0.5:
		where = "Off the runway edge (%.0f m from centreline)" % off[0]
	else:
		where = "%.1f m from centreline · %.0f m past the %s threshold" % [off[0], off[1], off[3]]
	var lvl := INFO if td.sink_fpm < 600.0 and not where.begins_with("Off") else CAUTION
	post("Touchdown · %s" % g, "%.0f fpm · %.2f g · %.0f KIAS · pitch %.0f° · bank %.0f°\n%s" % [
		td.sink_fpm, td.g, td.kias, td.pitch_deg, td.bank_deg, where], lvl, "td")
