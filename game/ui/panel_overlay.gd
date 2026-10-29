extends Control
## 2D instrument panel for outside views, built from pieces (AtlasTexture regions) of
## the live panel SubViewport, in switchable layouts. Tab / Shift+Tab cycle layouts:
##   Full     - whole panel along the bottom
##   Split    - six-pack bottom-left, tach + engine strip on the right edge
##   Compact  - small six-pack bottom-left only
##   Minimal  - top row (ASI, AI, ALT) small, top-right
##   Off
## Hidden in the cockpit view (the 3D panel is used there). Clicks are forwarded to
## the SubViewport, so knobs and switches work in every layout. Choice is saved.

const CFG := "user://ui.cfg"
const LAYOUTS := ["Full", "Split", "Compact", "Minimal", "Off"]

var cockpit: Cockpit
var cam: CameraRig
var layout := 1
var _acc := 0.0
var _pieces: Array = []  # [TextureRect, Rect2 region (panel px)]


func setup(c: Cockpit, rig: CameraRig) -> void:
	cockpit = c
	cam = rig
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
		p[0].queue_free()
	_pieces.clear()
	if cockpit == null:
		return
	var vs := get_viewport().get_visible_rect().size
	for s in _spec():
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
		var pos := Vector2.ZERO
		match s[1]:
			"bl": pos = Vector2(8, vs.y - h - 8)
			"br": pos = Vector2(vs.x - w - 8, vs.y - h - 8)
			"bc": pos = Vector2((vs.x - w) * 0.5, vs.y - h)
			"tr": pos = Vector2(vs.x - w - 8, 30)
			"rc": pos = Vector2(vs.x - w - 8, (vs.y - h) * 0.5)
		tr.position = pos
		tr.size = Vector2(w, h)
		tr.mouse_filter = MOUSE_FILTER_STOP
		tr.modulate = Color(1, 1, 1, 0.95)
		tr.gui_input.connect(_forward.bind(tr, reg))
		add_child(tr)
		_pieces.append([tr, reg])


func _forward(e: InputEvent, tr: TextureRect, reg: Rect2) -> void:
	if not (e is InputEventMouse):
		return
	var ev: InputEventMouse = e.duplicate()
	ev.position = reg.position + e.position / tr.size * reg.size
	ev.global_position = ev.position
	cockpit.viewport.push_input(ev)
	tr.accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_TAB:
		layout = posmod(layout + (-1 if e.shift_pressed else 1), LAYOUTS.size())
		if Session.interactive():
			var cf := ConfigFile.new()
			cf.set_value("panel", "layout", layout)
			cf.save(CFG)
		Props.set_v("view/panel_layout", LAYOUTS[layout])
		_build()
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	if cam == null:
		return
	visible = cam.mode != CameraRig.Mode.COCKPIT and not _pieces.is_empty()
	_acc += _dt
	if visible and _acc >= 1.0 / 30.0:
		_acc = 0.0
		cockpit.panel_ui.refresh()
		cockpit.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
