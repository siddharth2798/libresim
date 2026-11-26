class_name CaptainMapPicture
extends Control
## One device of the Captain Pack map: its photo (or the drawn outline when the picture is missing) fitted into the control with a
## numbered marker on each control (positions: captain_map/map.json, 0..1 of the picture). A marker glows green while its control is
## held or moving (`lit`, 0..1), is dim when nothing is bound to it, and has an amber ring when selected. Controls that are not
## visible in the photo sit in a strip under it. Redraws only when the state changes. Click a marker: `marker_clicked(id)`.

signal marker_clicked(id: String)

const FILL := Color(0.02, 0.05, 0.09, 0.9)
const CAPTION := "Not in the photo:"

var device := ""
var title := ""
var texture: Texture2D  # null = drawn outline
var markers: Array = []  # map.json markers, their order is the number
var aspect := 1.0  # width / height of the picture
var tips := {}  # id -> tooltip text
var lit := {}  # id -> 0..1 glow
var dim := {}  # id -> true when nothing is bound
var selected := ""
var unsure := {}  # id -> true when a number of the marker is unconfirmed: dashed amber ring and a "?"
var _pos := {}  # id -> centre, rebuilt by _layout()
var _r := 11.0
var _strip_y := 0.0  # centre line of the "not in the photo" markers


## The picture file as a texture, or null when it is not there.
static func load_texture(file: String) -> Texture2D:
	var path := CaptainMap.PATH.get_base_dir().path_join(file)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func setup(dev: String, tex: Texture2D, ms: Array, asp: float) -> CaptainMapPicture:
	device = dev
	texture = tex
	markers = ms
	aspect = asp
	custom_minimum_size = Vector2(150, 300)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # drawn at about half size
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	return self


## Marker colours: lit (id -> 0..1), dim (id -> true, nothing bound), selected id.
func set_state(new_lit: Dictionary, new_dim: Dictionary, new_selected: String) -> void:
	if new_lit == lit and new_dim == dim and new_selected == selected:
		return
	lit = new_lit.duplicate()
	dim = new_dim.duplicate()
	selected = new_selected
	queue_redraw()


func set_unsure(new_unsure: Dictionary) -> void:
	if new_unsure != unsure:
		unsure = new_unsure.duplicate()
		queue_redraw()


func _off(m: Dictionary) -> bool:
	return not m.has("x")


## Picture rectangle and marker centres for the current size.
func _layout() -> Rect2:
	var area := Rect2(Vector2.ZERO, size).grow(-6.0)
	var offs := markers.filter(func(m): return _off(m))
	var strip := 0.0
	if not offs.is_empty():
		strip = 2.0 * _r + 12.0
	var avail := Rect2(area.position, area.size - Vector2(0, strip))
	var w := minf(avail.size.x, avail.size.y * aspect)
	var img := Rect2(avail.position + Vector2((avail.size.x - w) * 0.5, 0.0), Vector2(w, w / aspect))  # at the top: a tall row leaves room below
	_r = clampf(img.size.y * 0.03, 8.0, 12.0)
	_strip_y = img.end.y + _r + 8.0
	_pos.clear()
	for m in markers:
		if not _off(m):
			_pos[m.id] = img.position + Vector2(float(m.x) * img.size.x, float(m.y) * img.size.y)
	var x := area.position.x + 8.0 + MenuTheme.font().get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0 + _r
	for m in offs:
		_pos[m.id] = Vector2(x, _strip_y)
		x += 2.0 * _r + 8.0
	return img


func _draw() -> void:
	draw_style_box(MenuTheme.box(Color(0.17, 0.23, 0.31, 0.96), 10, MenuTheme.LINE, 0.0), Rect2(Vector2.ZERO, size))
	var img := _layout()
	draw_string(MenuTheme.font("semibold"), Vector2(12.0, 24.0), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MenuTheme.ACCENT)
	if texture != null:
		draw_texture_rect(texture, img, false)
	else:
		CaptainMapOutline.draw(self, device, img)
	if markers.any(func(m): return _off(m)):
		var f := MenuTheme.font()
		draw_string(f, Vector2(14.0, _strip_y + 4.0), CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM)
	for i in markers.size():
		_marker(markers[i], i + 1)


func _marker(m: Dictionary, n: int) -> void:
	var c: Vector2 = _pos[m.id]
	var t: float = lit.get(m.id, 0.0)
	var faint: bool = dim.get(m.id, false)
	var fill := FILL.lerp(Color(MenuTheme.OK, 1.0), t)
	var ring := Color(1, 1, 1, 0.5 if faint else 0.95).lerp(Color.WHITE, t)
	var square := str(m.get("kind", "")) == "switch"
	if t > 0.0:
		var g := Color(MenuTheme.OK, 0.38 * t)
		draw_circle(c, _r + 7.0, g)
		draw_circle(c, _r + 3.5, g)
	if m.id == selected:
		draw_arc(c, _r + 5.0, 0.0, TAU, 32, MenuTheme.WARN, 2.5, true)
	if square:
		var b := Rect2(c - Vector2(_r, _r) * 0.92, Vector2(_r, _r) * 1.84)
		draw_rect(b, fill)
		draw_rect(b, ring, false, 2.0)
	else:
		draw_circle(c, _r, fill)
		draw_arc(c, _r, 0.0, TAU, 24, ring, 2.0, true)
	if unsure.get(m.id, false):  # amber dashes over the ring and a "?" badge: a number of this control is not confirmed
		for i in 4:
			draw_arc(c, _r + 1.0, i * TAU / 4.0, i * TAU / 4.0 + TAU / 8.0, 6, MenuTheme.WARN, 3.0, true)
		draw_string(MenuTheme.font("bold"), c + Vector2(_r * 0.55, -_r * 0.55), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(_r * 1.2), MenuTheme.WARN)
	var col := MenuTheme.ACCENT_INK if t > 0.5 else Color(1, 1, 1, 0.55 if faint else 1.0)
	var fs := int(_r * 1.15)
	draw_string(MenuTheme.font("semibold"), c + Vector2(-_r, fs * 0.36), str(n), HORIZONTAL_ALIGNMENT_CENTER, _r * 2.0, fs, col)


## The marker under a point of this control, or null.
func _marker_at(p: Vector2) -> Variant:
	_layout()
	var best: Variant = null
	var bd := _r + 5.0
	for m in markers:
		var d: float = p.distance_to(_pos[m.id])
		if d <= bd:
			bd = d
			best = m
	return best


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var m: Variant = _marker_at(e.position)
		if m != null:
			marker_clicked.emit(m.id)
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var m: Variant = _marker_at(at)
	return tips.get(m.id, "") if m != null else ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
