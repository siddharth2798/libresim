extends Node
## The floating checklist window: geometry rules (ui/checklist_geom.gd), then the window itself
## (ui/checklist_window.gd, checklist_panel.gd) inside a SubViewport of a real screen size.

const SIZES := [Vector2(1280, 720), Vector2(1707, 720), Vector2(1920, 1080), Vector2(1920, 1080)]  # UI units at Auto: 720p, 2560x1080, 1080p, 4K


func _inside(r: Rect2, vp: Vector2) -> bool:
	return r.position.x >= -0.01 and r.position.y >= -0.01 and r.end.x <= vp.x + 0.01 and r.end.y <= vp.y + 0.01


func test_checklist_clamp_keeps_the_window_on_screen_at_every_size() -> String:
	for vp in SIZES:
		for r in [Rect2(-50, -50, 340, 400), Rect2(5000, 5000, 340, 400), Rect2(10, 10, 9000, 9000), Rect2(0, 0, 1, 1)]:
			var c := ChecklistGeom.clamp_rect(r, vp)
			if not _inside(c, vp):
				return "%s at %s clamped to %s" % [r, vp, c]
			if c.size.x < ChecklistGeom.MIN_SIZE.x - 0.01 or c.size.y < ChecklistGeom.MIN_SIZE.y - 0.01:
				return "clamped below the minimum size: %s" % c.size
	return ""


func test_checklist_default_dock_is_right_centred_and_compact() -> String:
	for vp in SIZES:
		var s := ChecklistGeom.default_size(vp)
		var r := ChecklistGeom.default_rect(s, vp, [])
		if absf(r.end.x - (vp.x - ChecklistGeom.MARGIN)) > 0.5 or absf(r.get_center().y - vp.y * 0.5) > 0.5:
			return "not docked right and centred at %s: %s" % [vp, r]
		if r.size.x > vp.x * 0.3 or r.size.y > vp.y * 0.65:
			return "default window too big at %s: %s" % [vp, r.size]
	return ""


func test_checklist_default_dock_dodges_busy_rects() -> String:
	var vp := Vector2(1280, 720)
	var s := ChecklistGeom.default_size(vp)
	var busy := [Rect2(1000, 30, 270, 290), Rect2(1000, 420, 270, 290)]  # panel pieces on the right edge
	var r := ChecklistGeom.default_rect(s, vp, busy)
	for b: Rect2 in busy:
		if r.intersects(b):
			return "default window %s overlaps %s" % [r, b]
	if not _inside(r, vp):
		return "default window left the screen: %s" % r
	return ""


func test_checklist_snap_goes_to_the_margin_only_when_close() -> String:
	var vp := Vector2(1920, 1080)
	var r := ChecklistGeom.snap(Rect2(14, 600, 300, 300), vp)
	if r.position.x != ChecklistGeom.MARGIN:
		return "left edge did not snap: %s" % r.position.x
	r = ChecklistGeom.snap(Rect2(1920 - 300 - 15, 1080 - 300 - 3, 300, 300), vp)
	if absf(r.end.x - (vp.x - ChecklistGeom.MARGIN)) > 0.01 or absf(r.end.y - (vp.y - ChecklistGeom.MARGIN)) > 0.01:
		return "right / bottom did not snap: %s" % r
	r = ChecklistGeom.snap(Rect2(400, 300, 300, 300), vp)
	if r.position != Vector2(400, 300):
		return "a window far from the edges moved: %s" % r.position
	return ""


func test_checklist_fraction_round_trip_and_aspect_change() -> String:
	var vp := Vector2(1920, 1080)
	var r := Rect2(700, 200, 340, 400)
	var f := ChecklistGeom.fraction_of(r, vp)
	var back := ChecklistGeom.from_fraction(f, r.size, vp)
	if back.position.distance_to(r.position) > 0.5:
		return "round trip moved the window: %s -> %s" % [r.position, back.position]
	var docked := ChecklistGeom.from_fraction(Vector2(1, 0.5), r.size, Vector2(2560, 1080))
	if absf(docked.end.x - (2560 - ChecklistGeom.MARGIN)) > 0.5:
		return "a right-docked window should stay docked on an ultrawide: %s" % docked
	var small := ChecklistGeom.from_fraction(f, r.size, Vector2(1280, 720))
	if not _inside(small, Vector2(1280, 720)):
		return "restored window off a smaller screen: %s" % small
	return ""


func test_checklist_resize_respects_min_max_and_the_screen() -> String:
	var vp := Vector2(1280, 720)
	var start := Rect2(900, 100, 340, 400)
	var r := ChecklistGeom.resize(start, Vector2i(-1, 0), Vector2(900, 0), vp)  # drag the left edge far right
	if r.size.x != ChecklistGeom.MIN_SIZE.x or absf(r.end.x - start.end.x) > 0.01:
		return "left-edge shrink: %s" % r
	r = ChecklistGeom.resize(start, Vector2i(-1, 0), Vector2(-5000, 0), vp)  # far left
	if r.size.x > ChecklistGeom.max_size(vp).x + 0.01 or r.position.x < 0.0:
		return "left-edge grow went past the limits: %s" % r
	r = ChecklistGeom.resize(start, Vector2i(1, 1), Vector2(5000, 5000), vp)  # bottom-right corner off the screen
	if not _inside(r, vp) or r.position != start.position:
		return "corner grow left the screen or moved the anchor: %s" % r
	r = ChecklistGeom.resize(start, Vector2i(1, 1), Vector2(-5000, -5000), vp)
	if r.size != ChecklistGeom.MIN_SIZE:
		return "corner shrink should stop at the minimum: %s" % r.size
	return ""


func test_checklist_zones_and_cursors() -> String:
	var s := Vector2(340, 400)
	var cases := {Vector2(170, 15): Vector2i(0, 0), Vector2(2, 200): Vector2i(-1, 0), Vector2(338, 200): Vector2i(1, 0),
		Vector2(170, 398): Vector2i(0, 1), Vector2(335, 395): Vector2i(1, 1), Vector2(4, 4): Vector2i(-1, -1), Vector2(335, 4): Vector2i(1, -1)}
	for p in cases:
		if ChecklistGeom.zone_at(p, s) != cases[p]:
			return "zone at %s is %s, wanted %s" % [p, ChecklistGeom.zone_at(p, s), cases[p]]
	if ChecklistWindow.cursor_for(Vector2i(1, 1)) != Control.CURSOR_FDIAGSIZE or ChecklistWindow.cursor_for(Vector2i(1, -1)) != Control.CURSOR_BDIAGSIZE \
			or ChecklistWindow.cursor_for(Vector2i(-1, 0)) != Control.CURSOR_HSIZE or ChecklistWindow.cursor_for(Vector2i(0, 1)) != Control.CURSOR_VSIZE:
		return "wrong resize cursor shapes"
	return ""


func test_checklist_opacity_is_limited() -> String:
	if ChecklistGeom.clamp_opacity(0.0) != ChecklistGeom.OPACITY_MIN or ChecklistGeom.clamp_opacity(5.0) != ChecklistGeom.OPACITY_MAX:
		return "opacity not clamped"
	return ""


func test_checklist_user_option_defaults_exist() -> String:
	for k in ["x", "y", "w", "h", "opacity", "collapsed"]:
		if not UserOptions.DEFAULTS.has("checklist_" + k):
			return "missing option checklist_" + k
	if UserOptions.DEFAULTS.checklist_x >= 0.0:
		return "a fresh install must start undocked-by-default (x < 0 = auto dock)"
	return ""


# --- the window itself ---------------------------------------------------------------------------

func _make(vp: Vector2) -> Array:
	var sv := SubViewport.new()
	sv.size = Vector2i(vp)
	add_child(sv)
	var ui := Control.new()
	sv.add_child(ui)
	var p := ChecklistPanel.new()
	p.persist = false
	ui.add_child(p)
	return [sv, p]


func _key(code: int, shift := false, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	return e


func _click(p: Control, local: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = local
	e.global_position = p.position + local
	p._gui_input(e)


func _move(p: Control, local: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = local
	e.global_position = p.position + local
	p._gui_input(e)


func test_checklist_window_docks_right_and_passes_the_mouse_through() -> String:
	for vp in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1707, 720)]:
		var a := _make(vp)
		var p: ChecklistPanel = a[1]
		var r := p.get_rect()
		var err := ""
		if absf(r.end.x - (vp.x - ChecklistGeom.MARGIN)) > 0.5 or absf(r.get_center().y - vp.y * 0.5) > 1.0:
			err = "default dock at %s is %s" % [vp, r]
		elif p.mouse_filter != Control.MOUSE_FILTER_STOP or p.size.x > vp.x * 0.3:
			err = "the window must be only its own small rectangle (so the rest of the screen gets the mouse): %s" % p.size
		a[0].queue_free()
		if err != "":
			return err
	return ""


func test_checklist_drag_snaps_and_resize_keeps_limits() -> String:
	var vp := Vector2(1280, 720)
	var a := _make(vp)
	var p: ChecklistPanel = a[1]
	var err := ""
	_click(p, Vector2(100, 15), true)  # grab the title bar
	if Props.get_b("ui/checklist_grab") == false:
		err = "dragging should hold the mouse yoke"
	_move(p, Vector2(100 - 1000, 15 - 400))  # drag far up-left, off the screen
	if not _inside(p.get_rect(), vp):
		err = "dragged window left the screen: %s" % p.get_rect()
	_click(p, Vector2(0, 0), false)
	if err == "" and (p.position.x != ChecklistGeom.MARGIN or p.position.y != ChecklistGeom.MARGIN):
		err = "released at the top-left corner should snap to the margin: %s" % p.position
	if err == "":  # resize from the bottom-right corner, beyond every limit
		_click(p, p.size - Vector2(4, 4), true)
		_move(p, p.size + Vector2(4000, 4000))
		_click(p, Vector2.ZERO, false)
		if not _inside(p.get_rect(), vp) or p.size.x > ChecklistGeom.max_size(vp).x + 0.01:
			err = "resized window broke the limits: %s" % p.get_rect()
	if err == "":  # an on-screen window stays on screen when the screen shrinks
		var small := Vector2(900, 500)
		a[0].size = Vector2i(small)
		p.relayout()
		if not _inside(p.get_rect(), small):
			err = "window off a smaller screen: %s" % p.get_rect()
	a[0].queue_free()
	return err


func test_checklist_collapse_shows_one_line_and_expands_back() -> String:
	var a := _make(Vector2(1280, 720))
	var p: ChecklistPanel = a[1]
	var full := p.size.y
	p.visible = true
	p.set_collapsed(true)
	var err := ""
	if p.size.y >= full * 0.4 or p.size.y != ChecklistWindow.COLLAPSED_H:
		err = "collapsed height %.0f (full %.0f)" % [p.size.y, full]
	p.set_collapsed(false)
	if absf(p.size.y - full) > 0.5:
		err = "expanded height %.0f, wanted %.0f" % [p.size.y, full]
	a[0].queue_free()
	return err


func test_checklist_keys_toggle_tick_and_switch_lists() -> String:
	var a := _make(Vector2(1280, 720))
	var p: ChecklistPanel = a[1]
	var err := ""
	if p.visible:
		err = "starts hidden"
	p._unhandled_key_input(_key(KEY_F2))
	if not p.visible:
		err = "F2 should open it"
	var c0 := p.current_item()
	p._unhandled_key_input(_key(KEY_ENTER))
	if p.current_item() == c0 and p.lists[0].items.size() > 1 and not p.is_done(c0):
		err = "Enter should tick the current item"
	p._unhandled_key_input(_key(KEY_ENTER, true))
	if p.current_item() != c0:
		err = "Shift+Enter should take it back (item %d, was %d)" % [p.current_item(), c0]
	p._unhandled_key_input(_key(KEY_PAGEDOWN, false, true))
	if p.current != 1:
		err = "Ctrl+PgDn should go to the next list"
	p._unhandled_key_input(_key(KEY_F2, true))
	if not p.collapsed:
		err = "Shift+F2 should collapse"
	p._unhandled_key_input(_key(KEY_F2))
	if p.visible:
		err = "F2 should close it"
	a[0].queue_free()
	return err


func test_checklist_auto_items_tick_themselves_and_current_moves_on() -> String:
	var a := _make(Vector2(1280, 720))
	var p: ChecklistPanel = a[1]
	var err := ""
	var idx := -1
	for i in p.lists[0].items.size():
		if p.lists[0].items[i].has("prop"):
			idx = i
			break
	var item: Dictionary = p.lists[0].items[idx]
	var old = Props.get_v(item.prop)
	Props.set_v(item.prop, item.eq)
	if not p.is_done(idx):
		err = "an item whose property matches should count as done"
	Props.set_v(item.prop, (not item.eq) if item.eq is bool else float(item.eq) + 1.0)
	if p.is_done(idx):
		err = "an item whose property no longer matches is open again"
	Props.set_v(item.prop, old)
	a[0].queue_free()
	return err
