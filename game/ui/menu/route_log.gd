class_name RouteLog
extends VBoxContainer
## The nav log of the Route step: a header, one row per leg (to, magnetic course, distance, time at cruise speed,
## distance so far, planned altitude) and the totals. Waypoint rows have an altitude box and move up / down / remove
## buttons; the destination row shows the altitude it inherits. Pressing a row's name selects it (the map rings it).
## Rows are rebuilt only when the waypoints change (so typing an altitude keeps the focus); otherwise refreshed in place.
## It owns no route: show() takes RouteEdit.legs(), the signals go to the page. Under the totals, the fuel line
## (show_fuel, RouteFuel): amber when the margin is thin, red when the fuel on board is short of trip + reserve.

signal row_selected(wp: int)  # wps index, -2 = the destination
signal alt_changed(wp: int, alt_ft: float)
signal move_requested(wp: int, delta: int)
signal remove_requested(wp: int)

const COLS := [["TO", 70], ["CRS", 42], ["DIST", 48], ["ETE", 48], ["TOTAL", 50], ["ALT ft", 92]]
const ROW_H := 34

var rows: Array = []  # [{panel, ident, crs, dist, ete, cum, alt, up, down, del, wp}]
var total: Label
var fuel: Label
var empty_note: Label
var _list: VBoxContainer
var _sig := ""


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var pad := MarginContainer.new()  # the rows' panels have a 4 px margin: the header lines up with their cells
	pad.add_theme_constant_override("margin_left", 4)
	add_child(pad)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	for c in COLS:
		var l := Label.new()
		l.text = c[0]
		l.custom_minimum_size = Vector2(c[1], 0)
		l.add_theme_color_override("font_color", MenuTheme.FAINT)
		MenuTheme.use_font(l, "semibold", 11)
		head.add_child(l)
	pad.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	empty_note = MenuTheme.note("No route yet. Pick a destination, choose an auto-route, type one, or click the map.")
	_list.add_child(empty_note)
	total = Label.new()
	MenuTheme.use_font(total, "semibold", 14)
	add_child(total)
	fuel = Label.new()
	fuel.add_theme_font_size_override("font_size", 13)
	fuel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(fuel)


## Show `legs` (RouteEdit.legs); `sel` is the selected wps index; `n_wps` the number of waypoints; `tas_kt` the speed of
## the times.
func show_legs(legs: Array, sel: int, n_wps: int, tas_kt: float) -> void:
	var sig := JSON.stringify(legs.map(func(l): return [l.ident, l.wp]))
	if sig != _sig:
		_sig = sig
		_rebuild(legs, n_wps)
	for i in rows.size():
		_fill(rows[i], legs[i], sel)
	empty_note.visible = legs.is_empty()
	if legs.is_empty():
		total.text = ""
	else:
		var last: Dictionary = legs.back()
		total.text = "Total  %.1f nm  ·  %s  at %d kt" % [last.cum_m / RouteEdit.NM, RoutePlan.format_ete(last.cum_s), roundi(tas_kt)]
	total.tooltip_text = "Still air, at the aircraft's cruise true airspeed."


## The fuel line of RouteFuel.for_setup ({} hides it).
func show_fuel(f: Dictionary) -> void:
	fuel.visible = not f.is_empty()
	if f.is_empty():
		return
	fuel.text = "Fuel  " + RouteFuel.text(f)
	fuel.add_theme_color_override("font_color", {"bad": MenuTheme.BAD, "warn": MenuTheme.WARN}.get(f.level, MenuTheme.DIM))
	var verdict := {"bad": "Not enough: on board is less than trip + reserve.", "warn": "Thin: you would land with less than twice the reserve."}
	fuel.tooltip_text = "%s%s at %s per hour, still air, at the cruise speed. Change the fuel on the Aircraft step." % [
		verdict.get(f.level, "") + ("\n" if f.level != "ok" else ""), RoutePlan.format_ete(float(f.hours) * 3600.0),
		RouteFuel.amount(f.burn, f.unit)]


func _rebuild(legs: Array, n_wps: int) -> void:
	var focus_at := Vector2i(-1, -1)  # (row, column) of a log control that had the focus
	for i in rows.size():
		var cells: Array = _cells(rows[i])
		for j in cells.size():
			if cells[j] != null and _focused(cells[j]):
				focus_at = Vector2i(i, j)
		_list.remove_child(rows[i].panel)
		rows[i].panel.queue_free()
	rows.clear()
	for l in legs:
		var r := _row(l, n_wps)
		_list.add_child(r.panel)
		rows.append(r)
	if focus_at.x >= 0 and not rows.is_empty():
		var cells: Array = _cells(rows[mini(focus_at.x, rows.size() - 1)])
		var c = cells[focus_at.y] if cells[focus_at.y] != null else cells[0]
		if c is SpinBox:
			c = c.get_line_edit()
		if c is Control and c.is_inside_tree() and not (c is BaseButton and c.disabled):
			c.grab_focus()


func _cells(r: Dictionary) -> Array:
	return [r.ident, r.alt if r.alt is SpinBox else null, r.up, r.down, r.del]


func _focused(c: Control) -> bool:
	return c.has_focus() or (c is SpinBox and c.get_line_edit().has_focus())


func _row(l: Dictionary, n_wps: int) -> Dictionary:
	var wp: int = int(l.wp)
	var panel := PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	panel.add_child(hb)
	var r := {"panel": panel, "wp": wp}
	r.ident = Button.new()
	r.ident.custom_minimum_size = Vector2(COLS[0][1], ROW_H - 4)
	r.ident.alignment = HORIZONTAL_ALIGNMENT_LEFT
	r.ident.clip_text = true
	r.ident.flat = true
	MenuTheme.use_font(r.ident, "semibold", 14)
	r.ident.pressed.connect(func(): row_selected.emit(wp))
	hb.add_child(r.ident)
	for k in ["crs", "dist", "ete", "cum"]:
		var lab := Label.new()
		lab.custom_minimum_size = Vector2(COLS[["crs", "dist", "ete", "cum"].find(k) + 1][1], 0)
		lab.add_theme_font_size_override("font_size", 14)
		hb.add_child(lab)
		r[k] = lab
	if wp >= 0:
		var sb := SpinBox.new()
		sb.min_value = 0.0
		sb.max_value = 45000.0
		sb.step = 100.0
		sb.custom_minimum_size = Vector2(COLS[5][1], 0)
		sb.tooltip_text = "Planned altitude (ft) of the leg to this waypoint"
		sb.value_changed.connect(func(v): alt_changed.emit(wp, v))
		hb.add_child(sb)
		r.alt = sb
	else:
		var al := Label.new()
		al.custom_minimum_size = Vector2(COLS[5][1], 0)
		al.add_theme_color_override("font_color", MenuTheme.DIM)
		al.add_theme_font_size_override("font_size", 14)
		al.tooltip_text = "The leg into the destination is flown at the last waypoint's altitude (or the cruise altitude)."
		al.mouse_filter = Control.MOUSE_FILTER_PASS
		hb.add_child(al)
		r.alt = al
	r.up = _small("▲", "Move up (earlier in the route)", wp >= 1, func(): move_requested.emit(wp, -1))
	r.down = _small("▼", "Move down (later in the route)", wp >= 0 and wp < n_wps - 1, func(): move_requested.emit(wp, 1))
	r.del = _small("×", "Remove this waypoint", wp >= 0, func(): remove_requested.emit(wp))
	for k in ["up", "down", "del"]:
		hb.add_child(r[k])
		r[k].visible = wp >= 0
	return r


func _small(text: String, tip: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.disabled = not on
	b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE  # Tab skips a greyed button
	b.custom_minimum_size = Vector2(26, ROW_H - 4)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b


func _fill(r: Dictionary, l: Dictionary, sel: int) -> void:
	var here := int(l.wp) == sel and sel != -1
	r.panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(MapStyle.ROUTE, 0.28) if here else Color(1, 1, 1, 0.03), 6,
		Color(MapStyle.ROUTE, 0.8) if here else Color(0, 0, 0, 0), 4.0))
	r.ident.text = str(l.ident)
	r.ident.tooltip_text = "%s (%s): select it on the map" % [str(l.ident), "destination" if int(l.wp) == -2 else str(l.kind)]
	r.crs.text = "%03d°" % (roundi(float(l.course_mag)) % 360)
	r.dist.text = "%.1f" % (float(l.dist_m) / RouteEdit.NM)
	r.ete.text = RoutePlan.format_ete(float(l.ete_s))
	r.cum.text = "%.1f" % (float(l.cum_m) / RouteEdit.NM)
	if r.alt is SpinBox:
		if not _focused(r.alt):
			r.alt.set_value_no_signal(float(l.alt_ft))
	else:
		r.alt.text = "%d" % roundi(float(l.alt_ft))
