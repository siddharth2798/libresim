class_name CaptainMapLegend
extends VBoxContainer
## The list beside one picture of the Captain Pack map: a row per marker with its number, what the control does for the current
## bindings ("Thrust lever 1: Throttle", dim "unbound") and a small live bar for axes and levers. Each row is a button (keyboard and
## gamepad focus reach it; focusing or pressing it selects the marker: `picked(id)`). Rows redraw only when their state changes.

signal picked(id: String)

const ROW_H := 26.0

var device := ""
var rows := {}  # id -> {button, badge, label, bar, lit, bar_v, bipolar}
var _ids: Array[String] = []
var _group := ButtonGroup.new()


func build(dev: String, markers: Array) -> CaptainMapLegend:
	device = dev
	add_theme_constant_override("separation", 2)
	custom_minimum_size = Vector2(235, 0)
	size_flags_vertical = SIZE_SHRINK_BEGIN
	for i in markers.size():
		_add_row(markers[i], i + 1)
	return self


func _add_row(m: Dictionary, n: int) -> void:
	var id: String = m.id
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.clip_contents = true
	b.pressed.connect(func(): picked.emit(id))
	b.focus_entered.connect(func(): picked.emit(id))
	add_child(b)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 3)
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(h)
	var row := {"button": b, "lit": 0.0, "bar_v": null, "bipolar": str(m.get("kind", "")) == "axis", "dim": false}
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(20, 20)
	badge.size_flags_vertical = SIZE_SHRINK_CENTER
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	badge.draw.connect(_draw_badge.bind(badge, row, n, str(m.get("kind", "")) == "switch"))
	h.add_child(badge)
	var l := Label.new()
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 14)
	h.add_child(l)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(38, 8)
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.visible = str(m.get("kind", "")) in ["axis", "lever"]
	bar.draw.connect(_draw_bar.bind(bar, row))
	h.add_child(bar)
	row.merge({"badge": badge, "label": l, "bar": bar, "name": str(m.get("label", id))})
	rows[id] = row
	_ids.append(id)


func ids() -> Array[String]:
	return _ids


## What the control does now; `unbound` dims the row.
func set_text(id: String, text: String, unbound: bool, tip := "", unsure := false) -> void:
	var row: Dictionary = rows[id]
	row.dim = unbound
	row.unsure = unsure
	row.label.text = line(row.name, text) + ("  ?" if unsure else "")
	row.label.add_theme_color_override("font_color", MenuTheme.FAINT if unbound else MenuTheme.TEXT)
	row.button.tooltip_text = tip
	row.badge.queue_redraw()


## "Control: action", or just the longer of the two when one contains the other ("Roll" / "Roll", "Speed brake lever" / "Speedbrake").
static func line(control: String, action: String) -> String:
	var a := control.to_lower().replace(" ", "")
	var b := action.to_lower().replace(" ", "")
	if b == "unbound" or a == "" or not (a.contains(b) or b.contains(a)):
		return "%s: %s" % [control, action]
	return control if control.length() >= action.length() else action


## Live state: `lit` 0..1, `bar` null (no reading) or the lever fill 0..1 / stick -1..1.
func set_live(id: String, lit: float, bar: Variant) -> void:
	var row: Dictionary = rows[id]
	if not is_equal_approx(lit, row.lit):
		row.lit = lit
		row.badge.queue_redraw()
	if bar != row.bar_v and not (bar is float and row.bar_v is float and is_equal_approx(bar, row.bar_v)):
		row.bar_v = bar
		row.bar.queue_redraw()


func select(id: String) -> void:
	for k in rows:
		rows[k].button.set_pressed_no_signal(k == id)


func _draw_badge(c: Control, row: Dictionary, n: int, square: bool) -> void:
	var t: float = row.lit
	var ctr := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5 - 1.0
	var fill := CaptainMapPicture.FILL.lerp(MenuTheme.OK, t)
	var ring := MenuTheme.WARN if row.get("unsure", false) else Color(1, 1, 1, 0.5 if row.dim else 0.95)
	if square:
		var b := Rect2(ctr - Vector2(r, r) * 0.92, Vector2(r, r) * 1.84)
		c.draw_rect(b, fill)
		c.draw_rect(b, ring, false, 1.5)
	else:
		c.draw_circle(ctr, r, fill)
		c.draw_arc(ctr, r, 0.0, TAU, 24, ring, 1.5, true)
	c.draw_string(MenuTheme.font("semibold"), Vector2(0, ctr.y + 5.0), str(n), HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 13,
		MenuTheme.ACCENT_INK if t > 0.5 else Color(1, 1, 1, 0.6 if row.dim else 1.0))


func _draw_bar(c: Control, row: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0, 0, 0, 0.4))
	var v = row.bar_v
	if v != null:
		var col := Color(MenuTheme.OK, 0.95)
		if row.bipolar:
			var mid := r.size.x * 0.5
			var w: float = clampf(float(v), -1.0, 1.0) * mid
			c.draw_rect(Rect2(mid + minf(w, 0.0), 0, absf(w), r.size.y), col)
			c.draw_line(Vector2(mid, 0), Vector2(mid, r.size.y), Color(1, 1, 1, 0.5))
		else:
			c.draw_rect(Rect2(0, 0, r.size.x * clampf(float(v), 0.0, 1.0), r.size.y), col)
	c.draw_rect(r, Color(1, 1, 1, 0.2), false)
