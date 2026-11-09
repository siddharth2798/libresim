class_name BusyOverlay
extends Control
## A dim veil and a spinner for a wait the pilot would otherwise sit through.
## show_busy blocks clicks; hide_busy lets them through. cover() puts one over the whole window
## (it survives a scene change until dismiss()). A child overlay just covers its parent.


const GROUP := &"busy_overlay"
const _FRAMES := "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
const _Credits := preload("res://ui/credits_screen.gd")

var _label: Label
var _mark: Label
var _place: Label
var _credit: Label
var _film: LoaderFilm
var _dim: ColorRect
var _scrim: TextureRect
var _center: CenterContainer
var _scenic := false
var _spin := 0.0


func _ready() -> void:
	# Anchors AND offsets: a veil built in code under a CanvasLayer kept its 0 x 0 offsets and never drew.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	add_to_group(GROUP)
	_film = LoaderFilm.new()
	add_child(_film)
	_scrim = TextureRect.new()
	_scrim.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_scrim.offset_top = -280.0
	_scrim.mouse_filter = MOUSE_FILTER_IGNORE
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	_scrim.texture = _gradient()
	_scrim.visible = false
	add_child(_scrim)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.05, 0.72)
	_dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_dim)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_center)
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	_center.add_child(box)
	_place = Label.new()
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place.add_theme_font_override("font", MenuTheme.font("semibold"))
	_place.add_theme_font_size_override("font_size", 34)
	_place.add_theme_color_override("font_color", MenuTheme.TEXT)
	_place.visible = false
	box.add_child(_place)
	_mark = Label.new()
	_mark.text = _FRAMES[0]
	_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mark.add_theme_font_override("font", MenuTheme.font("semibold"))
	_mark.add_theme_font_size_override("font_size", 32)
	_mark.add_theme_color_override("font_color", MenuTheme.ACCENT)
	box.add_child(_mark)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", MenuTheme.font())
	_label.add_theme_font_size_override("font_size", MenuTheme.SIZE_TITLE)
	_label.add_theme_color_override("font_color", MenuTheme.TEXT)
	box.add_child(_label)
	_credit = Label.new()
	_credit.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	_credit.offset_left = 24.0
	_credit.offset_right = -24.0
	_credit.offset_top = -36.0
	_credit.offset_bottom = -6.0
	_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_credit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_credit.add_theme_font_size_override("font_size", 10)
	_credit.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_credit.mouse_filter = MOUSE_FILTER_IGNORE
	_credit.visible = false
	add_child(_credit)


func show_busy(text: String, scenic: bool = false, aircraft: String = "", airport: String = "", start: String = "") -> void:
	if _label != null:
		_label.text = text
	_scenic = scenic and _film != null and LoaderFilm.available()
	if _dim != null:
		_dim.visible = not _scenic
	if _film != null:
		_film.visible = _scenic
		if _scenic:
			if aircraft != "" or airport != "":
				_film.restart_for(aircraft, airport, start)
			else:
				_film.restart()
	if _scrim != null:
		_scrim.visible = _scenic
	if _place != null:
		_place.visible = _scenic
	if _center != null:
		if _scenic:
			_center.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
			_center.offset_top = -176.0
			_center.offset_bottom = -44.0
		else:
			_center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if _label != null:
		_label.add_theme_font_size_override("font_size", MenuTheme.SIZE_BODY if _scenic else MenuTheme.SIZE_TITLE)
		_label.add_theme_color_override("font_color", MenuTheme.DIM if _scenic else MenuTheme.TEXT)
	if _credit != null:
		_credit.visible = _scenic
		if _scenic:
			_credit.text = _Credits.attribution_line()
	_place_text()
	visible = true
	mouse_filter = MOUSE_FILTER_STOP


## Change the line under the film without starting the clip again.
func set_status(text: String) -> void:
	if _label != null:
		_label.text = text


func hide_busy() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if not visible or _mark == null:
		return
	_spin += dt * 12.0
	_mark.text = _FRAMES[int(_spin) % _FRAMES.length()]
	_place_text()


func _place_text() -> void:
	if _place == null or _film == null:
		return
	_place.text = _film.caption if _scenic else ""


func _gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.01, 0.02, 0.04, 0.88))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0.5, 0.0)
	t.fill_to = Vector2(0.5, 1.0)
	return t


## One veil on the window root. A later cover replaces it.
## Empty aircraft and airport: the film picks a clip (a menu load). A flight passes both.
static func cover(tree: SceneTree, text: String, aircraft: String = "", airport: String = "", start: String = "") -> void:
	dismiss(tree)
	var layer := CanvasLayer.new()
	layer.layer = 80
	layer.name = "BusyLayer"
	var veil := BusyOverlay.new()
	layer.add_child(veil)
	tree.root.add_child(layer)
	veil.show_busy(text, true, aircraft, airport, start)


## The veil on the window root, or null. A child veil (a page, the turntable) is not this one.
static func root_veil(tree: SceneTree) -> BusyOverlay:
	if tree == null:
		return null
	for n in tree.get_nodes_in_group(GROUP):
		if n is BusyOverlay:
			var layer := n.get_parent()
			if layer is CanvasLayer and layer.get_parent() == tree.root:
				return n
	return null


## Drops a root veil. Child veils (a page, the turntable) are left to their owner.
static func dismiss(tree: SceneTree) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group(GROUP):
		var layer := n.get_parent()
		if layer is CanvasLayer and layer.get_parent() == tree.root:
			layer.queue_free()


## Paints the veil for two frames, then changes scene. The wait lives on the window root:
## the screen that asked is freed by the change, so it must not be the thing awaiting.
## Deferred: a command-line flight calls this from the start screen's _ready, while the
## window root is still setting up its children and refuses add_child.
static func load_scene(tree: SceneTree, path: String, text: String) -> void:
	if tree == null:
		return
	_open_scene.call_deferred(tree, path, text)


static func _open_scene(tree: SceneTree, path: String, text: String) -> void:
	if tree == null or tree.root == null:
		return
	var aircraft: String = ""
	var airport: String = ""
	var start: String = ""
	if path.ends_with("/flight.tscn"):
		aircraft = str(Session.setup.get("aircraft", ""))
		airport = str(Session.setup.get("airport", ""))
		start = str(Session.setup.get("start", ""))
	cover(tree, text, aircraft, airport, start)
	var gate := Node.new()
	gate.name = "SceneGate"
	gate.process_mode = Node.PROCESS_MODE_ALWAYS
	gate.set_meta("path", path)
	gate.set_meta("left", 2)
	tree.root.add_child(gate)
	if not gate.is_inside_tree():
		return
	tree.process_frame.connect(BusyOverlay._gate_frame.bind(gate), CONNECT_ONE_SHOT)


static func _gate_frame(gate: Node) -> void:
	if not is_instance_valid(gate):
		return
	var left := int(gate.get_meta("left")) - 1
	gate.set_meta("left", left)
	var tree := gate.get_tree()
	if tree == null:
		return
	if left > 0:
		tree.process_frame.connect(BusyOverlay._gate_frame.bind(gate), CONNECT_ONE_SHOT)
		return
	var path := str(gate.get_meta("path"))
	gate.queue_free()
	tree.change_scene_to_file(path)
