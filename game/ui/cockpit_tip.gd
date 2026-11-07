class_name CockpitTip
extends CanvasLayer
## Cockpit hover note, near the pointer: what the lever or switch is, which key moves it, and its
## position. The card ignores the mouse, so a click still reaches the control underneath.

const Text = preload("res://ui/cockpit_tip_text.gd")
const Row = preload("res://ui/gauges/switch_row.gd")
const DELAY := 0.15

var _root: Control
var _panel: PanelContainer
var _title: Label
var _keys: Label
var _state: Label
var _plain := ""
var _hold_id := ""
var _hold := 0.0


func _ready() -> void:
	layer = 8
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.92)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	_panel.add_child(box)
	_title = _line(box, 15, Color(0.95, 0.96, 0.97))
	_keys = _line(box, 13, Color(0.62, 0.74, 0.86))
	_state = _line(box, 14, Color(1.0, 0.86, 0.45))
	_root.add_child(_panel)


func _line(box: VBoxContainer, size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


## The three lines _process shows. Empty when the pointer is on nothing operable.
func text_for(lever_id: String, drive: String, value: Variant, switch_i: int, switch_value: Variant, bindings: Dictionary) -> String:
	return Text.compose(lever_id, drive, value, switch_i, switch_value, bindings)


func present(text: String) -> void:
	_plain = text
	var parts := text.split("\n")
	_title.text = parts[0] if parts.size() > 0 and text != "" else ""
	_keys.text = parts[1] if parts.size() > 1 else ""
	_state.text = parts[2] if parts.size() > 2 else ""
	_panel.visible = text != ""
	if text != "":
		_place()


func shown() -> String:
	return _plain if _panel.visible else ""


func blocks_clicks() -> bool:
	return _blocks(self)


func _process(dt: float) -> void:
	var cam := get_parent() as CameraRig
	if cam == null or cam.mode != CameraRig.Mode.COCKPIT or cam.aircraft == null or cam.aircraft.cockpit == null:
		_clear()
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or cam._grab == "look":
		_clear()
		return
	var vp := get_viewport()
	if cam._grab != "lever" and vp != null and CockpitPick.gui_blocks(vp):
		_clear()
		return
	var screen := vp.get_mouse_position() if vp else Vector2.ZERO
	var found: Dictionary = _from_item(cam._grab_item) if cam._grab == "lever" else _find(cam, screen)
	var id := str(found.id)
	if id != _hold_id:
		_hold_id = id
		_hold = 0.0
	if id == "":
		present("")
		return
	_hold += dt
	if _hold < DELAY and not _panel.visible:
		return
	present(text_for(str(found.lever), str(found.drive), found.value, int(found.switch_i), found.switch_value, KeyBindings.load_from()))


func _from_item(it: Dictionary) -> Dictionary:
	var drive := str(it.get("drive", ""))
	var id := Text.lever_id(it)
	if id == "" or drive == "":
		return {"id": "", "lever": "", "drive": "", "value": null, "switch_i": -1, "switch_value": null}
	return {"id": "lv:" + id, "lever": id, "drive": drive, "value": CockpitPick.read_current(drive), "switch_i": -1, "switch_value": null}


func _find(cam: CameraRig, screen: Vector2) -> Dictionary:
	var none := {"id": "", "lever": "", "drive": "", "value": null, "switch_i": -1, "switch_value": null}
	var pit: Cockpit = cam.aircraft.cockpit
	var hit = pit.panel_hit(cam, screen)
	var sw: Rect2 = InstrumentPanel.rects().get("switches", Rect2())
	var count: int = Row.ITEMS.size()
	var at := Vector2.ZERO
	var kind := "none"
	if hit != null:
		at = hit.at
		kind = "switches" if Text.switch_index(at, sw, count) >= 0 and (hit.rect as Rect2).intersects(sw) else "glass"
	var lever_id := ""
	var drive := ""
	var value = null
	if kind == "none":
		var it := CockpitPick.pick(pit.lever_items(), cam.project_ray_origin(screen), cam.project_ray_normal(screen))
		lever_id = Text.lever_id(it)
		drive = str(it.get("drive", ""))
		if drive != "":
			value = CockpitPick.read_current(drive)
	var picked: Dictionary = Text.choice(kind, at, sw, count, lever_id)
	var si: int = int(picked.switch)
	if si >= 0:
		var prop := str(Row.ITEMS[si][1])
		return {"id": "sw:%d" % si, "lever": "", "drive": prop, "value": null, "switch_i": si, "switch_value": Props.get_v(prop, null)}
	if str(picked.lever) == "":
		return none
	return {"id": "lv:" + str(picked.lever), "lever": str(picked.lever), "drive": drive, "value": value, "switch_i": -1, "switch_value": null}


func _clear() -> void:
	_hold_id = ""
	_hold = 0.0
	present("")


func _place() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var m := vp.get_mouse_position()
	var sz := _panel.get_combined_minimum_size()
	var p := m + Vector2(18, 22)
	var view := vp.get_visible_rect().size
	if p.x + sz.x > view.x - 8.0:
		p.x = m.x - sz.x - 12.0
	if p.y + sz.y > view.y - 8.0:
		p.y = m.y - sz.y - 12.0
	_panel.position = Vector2(maxf(8.0, p.x), maxf(8.0, p.y))


func _blocks(n: Node) -> bool:
	if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	for c in n.get_children():
		if _blocks(c):
			return true
	return false
