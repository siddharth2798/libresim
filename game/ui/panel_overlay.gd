extends Control
## 2D instrument panel for outside views, built from pieces (AtlasTexture regions) of the live panel SubViewport, in switchable
## layouts. Tab / Shift+Tab cycle them: Full (whole panel along the bottom), Split (six-pack bottom-left, tach + engine strip on the
## right edge), Compact (small six-pack bottom-left), Minimal (top row ASI, AI, ALT small, top-right), Off.
## Hidden in the cockpit view (the 3D panel is used). Clicks are forwarded to the SubViewport, so knobs and switches work in every
## layout. The choice is saved. A piece whose items are ["minimap"] is the round mini-map (ui/mini_map.gd) drawn from the full
## moving map, not a panel region; it keeps its own place once the player drags it.

const CFG := "user://ui.cfg"
const LAYOUTS := ["Full", "Split", "Compact", "Minimal", "Off"]

var cockpit: Cockpit
var cam: CameraRig
var layout := 1
var _acc := 0.0
var map: Control  # the full moving map (N, ui/moving_map.gd): the mini-map piece draws from it
var _pieces: Array = []  # [TextureRect, Rect2 region (panel px)]; the mini-map is [MiniMap, Rect2()]
var _minimap: MiniMap
var _minimap_on := false


func setup(c: Cockpit, rig: CameraRig, full_map: Control = null) -> void:
	cockpit = c
	cam = rig
	map = full_map
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		layout = cf.get_value("panel", "layout", layout)
	get_viewport().size_changed.connect(_build)
	_build()


## Union of the panel items in `names` that this aircraft's panel has (empty Rect2 if none).
func _region(names: Array) -> Rect2:
	var r := InstrumentPanel.rects()
	var out := Rect2()
	var first := true
	for n in names:
		if not r.has(n):
			continue
		out = r[n] if first else out.merge(r[n])
		first = false
	return Rect2() if first else out.grow(6)


## Layout spec: [[region names], anchor ("bl","br","bc","tr","rc"), height as fraction of screen],
## from the aircraft's panel.json "overlay" (layout name -> pieces).
func _spec() -> Array:
	var out := []
	for piece in InstrumentPanel.layout().get("overlay", {}).get(LAYOUTS[layout], []):
		out.append([piece.items, piece.anchor, piece.height])
	return out


func _build() -> void:
	for p in _pieces:
		if p[0] != _minimap:
			p[0].queue_free()
	_pieces.clear()
	_minimap_on = false
	if _minimap != null:
		_minimap.visible = false
	if cockpit == null:
		return
	var vs := get_viewport().get_visible_rect().size
	for s in _spec():
		if s[0] == ["minimap"]:
			_add_minimap(s, vs)
			continue
		var reg := _region(s[0])
		if reg.size.x <= 0.0:
			continue  # none of these items on this aircraft's panel
		var tex := AtlasTexture.new()
		tex.atlas = cockpit.viewport.get_texture()
		tex.region = reg
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		var h: float = vs.y * s[2]
		var w := h * reg.size.x / reg.size.y
		if w > vs.x:
			w = vs.x
			h = w * reg.size.y / reg.size.x
		tr.position = _anchor_pos(s[1], w, h, vs)
		tr.size = Vector2(w, h)
		tr.mouse_filter = MOUSE_FILTER_STOP
		tr.modulate = Color(1, 1, 1, 0.95)
		tr.gui_input.connect(_forward.bind(tr, reg))
		add_child(tr)
		_pieces.append([tr, reg])


static func _anchor_pos(anchor: String, w: float, h: float, vs: Vector2) -> Vector2:
	match anchor:
		"bl": return Vector2(8, vs.y - h - 8)
		"br": return Vector2(vs.x - w - 8, vs.y - h - 8)
		"bc": return Vector2((vs.x - w) * 0.5, vs.y - h)
		"tr": return Vector2(vs.x - w - 8, 30)
		"rc": return Vector2(vs.x - w - 8, (vs.y - h) * 0.5)
	return Vector2.ZERO


func _add_minimap(s: Array, vs: Vector2) -> void:
	if map == null:
		return
	if _minimap == null:
		_minimap = MiniMap.new()
		_minimap.source = map
		add_child(_minimap)
	var d: float = vs.y * s[2]
	_minimap.place(Rect2(_anchor_pos(s[1], d, d, vs), Vector2(d, d)))
	_minimap_on = true
	_pieces.append([_minimap, Rect2()])


func _forward(e: InputEvent, tr: TextureRect, reg: Rect2) -> void:
	if not (e is InputEventMouse):
		return
	var ev: InputEventMouse = e.duplicate()
	ev.position = reg.position + e.position / tr.size * reg.size
	ev.global_position = ev.position
	cockpit.viewport.push_input(ev)
	tr.accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if visible and MCDU.wants_key(e) and _type_on_mcdu(e):
		get_viewport().set_input_as_handled()
		return
	if e.pressed and not e.echo and e.keycode == KEY_TAB:
		layout = posmod(layout + (-1 if e.shift_pressed else 1), LAYOUTS.size())
		if Session.interactive():
			var cf := ConfigFile.new()
			cf.load(CFG)  # keep the mini-map's section
			cf.set_value("panel", "layout", layout)
			cf.save(CFG)
		Props.set_v("view/panel_layout", LAYOUTS[layout])
		_build()
		get_viewport().set_input_as_handled()


## The outside-view MCDU card takes scratchpad keys while the pointer is over it.
func _type_on_mcdu(e: InputEvent) -> bool:
	var rects := InstrumentPanel.rects()
	if cockpit == null or not rects.has("mcdu"):
		return false
	var mouse := get_viewport().get_mouse_position()
	var mcdu: Rect2 = rects.mcdu
	for piece in _pieces:
		if not piece[0] is TextureRect:
			continue
		var tr: TextureRect = piece[0]
		var reg: Rect2 = piece[1]
		if not tr.get_global_rect().has_point(mouse) or not reg.intersects(mcdu):
			continue
		var at := reg.position + (mouse - tr.global_position) / tr.size * reg.size
		if not mcdu.has_point(at):
			continue
		var unit := cockpit.panel_ui.get_node_or_null("mcdu")
		return unit != null and unit.has_method("type_key") and unit.type_key(e)
	return false


func _process(_dt: float) -> void:
	if cam == null:
		return
	visible = cam.mode != CameraRig.Mode.COCKPIT and not _pieces.is_empty()
	if _minimap != null:
		_minimap.visible = _minimap_on and not bool(Props.get_v("ui/map_open", false))  # not under the full map
	_acc += _dt
	if visible and _acc >= 1.0 / 30.0:
		_acc = 0.0
		cockpit.panel_ui.refresh()
		cockpit.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
