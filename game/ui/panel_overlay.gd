extends Control
## 2D instrument panel for outside views, built from pieces (AtlasTexture regions) of the live panel SubViewport, in switchable
## layouts. Tab / Shift+Tab cycle them: Full (whole panel along the bottom), Split (six-pack bottom-left, tach + engine strip on the
## right edge), Compact (small six-pack bottom-left), Minimal (top row ASI, AI, ALT small, top-right), Custom (the player's own,
## from Options > Screen layout, ui/screen_layout.gd), Off.
## Hidden in the cockpit view (the 3D panel is used). Clicks are forwarded to the SubViewport, so knobs and switches work in every
## layout. The choice is saved by name. A piece whose items are ["minimap"] is the round mini-map (ui/mini_map.gd) drawn from the
## full moving map, not a panel region; in the presets it keeps its own place once the player drags it, in Custom a drag moves it
## in the Custom layout. Props ui/layout_rev (bumped by ScreenLayout) rebuilds the pieces.

const LAYOUTS := ["Full", "Split", "Compact", "Minimal", "Custom", "Off"]
const OLD_LAYOUTS := ["Full", "Split", "Compact", "Minimal", "Off"]  # the saved index before Custom existed

var cockpit: Cockpit
var cam: CameraRig
var layout := 1
var _acc := 0.0
var _rev := -1
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
	layout = saved_layout()
	_rev = int(Props.get_v("ui/layout_rev", 0))
	get_viewport().size_changed.connect(_build)
	_build()


## The layout index in ui.cfg: [panel] layout_name, else the old index (4 was Off), else Split.
static func saved_layout() -> int:
	var cf := ConfigFile.new()
	if cf.load(ScreenLayout.cfg_path) != OK:
		return 1
	var by_name := LAYOUTS.find(str(cf.get_value("panel", "layout_name", "")))
	if by_name >= 0:
		return by_name
	var old := int(cf.get_value("panel", "layout", 1))
	return maxi(LAYOUTS.find(OLD_LAYOUTS[clampi(old, 0, OLD_LAYOUTS.size() - 1)]), 0)


## Union of the panel items in `names` that this aircraft's panel has (empty Rect2 if none).
func _region(names: Array) -> Rect2:
	return ScreenLayout.region(AircraftDef.current(), names)


## Where each piece of the current layout goes on a vs screen: [[items], Rect2 px]. Presets come from the
## aircraft's panel.json "overlay" (layout name -> [{items, anchor, height}]), Custom from ScreenLayout.
func placements(vs: Vector2) -> Array:
	var def := AircraftDef.current()
	var out := []
	if LAYOUTS[layout] == "Custom":
		var pieces := ScreenLayout.load_pieces(def)
		for c in ScreenLayout.catalog(def):
			if pieces[c.id].on:
				out.append([c.items, ScreenLayout.rect_px(pieces[c.id], ScreenLayout.aspect(def, c.items), vs)])
		return out
	for piece in InstrumentPanel.layout().get("overlay", {}).get(LAYOUTS[layout], []):
		var asp := ScreenLayout.aspect(def, piece.items)
		var h: float = vs.y * float(piece.height)
		var w := h * asp
		if w > vs.x:
			w = vs.x
			h = w / asp
		out.append([piece.items, Rect2(ScreenLayout.anchor_pos(piece.anchor, w, h, vs), Vector2(w, h))])
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
	for s in placements(vs):
		if s[0] == [ScreenLayout.MINIMAP]:
			_add_minimap(s[1])
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
		tr.position = s[1].position
		tr.size = s[1].size
		tr.mouse_filter = MOUSE_FILTER_STOP
		tr.modulate = Color(1, 1, 1, 0.95)
		tr.gui_input.connect(_forward.bind(tr, reg))
		add_child(tr)
		_pieces.append([tr, reg])


func _add_minimap(r: Rect2) -> void:
	if map == null:
		return
	if _minimap == null:
		_minimap = MiniMap.new()
		_minimap.source = map
		_minimap.arranged.connect(_on_minimap_arranged)
		add_child(_minimap)
	_minimap.custom = LAYOUTS[layout] == "Custom"
	_minimap.place(r)
	_minimap_on = true
	_pieces.append([_minimap, Rect2()])


## A drag or resize of the mini-map in the Custom layout: store it there (no rebuild, it is already in place).
func _on_minimap_arranged(r: Rect2) -> void:
	var def := AircraftDef.current()
	var pieces := ScreenLayout.load_pieces(def)
	if not pieces.has(ScreenLayout.MINIMAP) or not Session.interactive():
		return
	var vs := get_viewport().get_visible_rect().size
	pieces[ScreenLayout.MINIMAP].merge({"x": r.position.x / vs.x, "y": r.position.y / vs.y, "h": r.size.y / vs.y}, true)
	ScreenLayout.save_pieces(def, pieces, false)


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
			cf.load(ScreenLayout.cfg_path)  # keep the other sections
			cf.set_value("panel", "layout_name", LAYOUTS[layout])
			cf.save(ScreenLayout.cfg_path)
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
	var rev := int(Props.get_v("ui/layout_rev", 0))
	if rev != _rev:  # Options > Screen layout changed something
		_rev = rev
		layout = saved_layout()
		_build()
	visible = cam.mode != CameraRig.Mode.COCKPIT and not _pieces.is_empty()
	if _minimap != null:
		_minimap.visible = _minimap_on and not bool(Props.get_v("ui/map_open", false))  # not under the full map
	_acc += _dt
	if visible and _acc >= 1.0 / 30.0:
		_acc = 0.0
		cockpit.panel_ui.refresh()
		cockpit.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
