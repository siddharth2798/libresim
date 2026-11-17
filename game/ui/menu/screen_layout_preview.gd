class_name ScreenLayoutPreview
extends Control
## Options > Screen layout: a small 16:9 picture of the game screen with a box for every shown piece of the
## aircraft's Custom layout (ui/screen_layout.gd) and the flight-data bar. Drag a box to move it; drag its
## bottom-right corner, or turn the wheel over it, to resize it (the shape is kept). Every change is saved on
## release and `edited` is emitted. The mini-map is a disc, the bar a pill; the other boxes keep their panel shape.

signal edited

const HANDLE := 14.0  # px of the corner that resizes
const WHEEL_STEP := 1.08
const HUD := "hud"

var def: AircraftDef
var pieces := {}  # id -> {on, x, y, h}
var hud := {}  # {x, y, scale}
var hud_on := true

var _cat: Array = []
var _asp := {}  # id -> width / height
var _labels := {}  # id -> label
var _drag := ""  # id being dragged ("hud" for the bar)
var _resize := false
var _grab := Vector2.ZERO  # pointer minus the box's top-left when the drag began
var _hover := ""


func _init() -> void:
	custom_minimum_size = Vector2(480, 270)
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true


func set_aircraft(d: AircraftDef) -> void:
	def = d
	_cat = ScreenLayout.catalog(d)
	pieces = ScreenLayout.load_pieces(d)
	hud = ScreenLayout.hud()
	_asp.clear()
	_labels.clear()
	for c in _cat:
		_asp[c.id] = ScreenLayout.aspect(d, c.items)
		_labels[c.id] = c.label
	queue_redraw()


## The 16:9 screen inside this control (px).
func screen_rect() -> Rect2:
	var w := minf(size.x, size.y * 16.0 / 9.0)
	var s := Vector2(w, w * 9.0 / 16.0)
	return Rect2((size - s) * 0.5, s)


func box(id: String) -> Rect2:
	var sr := screen_rect()
	if id == HUD:
		var bar := Vector2(ScreenLayout.HUD_W * ScreenLayout.REF.x, ScreenLayout.HUD_H * ScreenLayout.REF.y) * sr.size.y / ScreenLayout.REF.y
		var r := ScreenLayout.hud_rect(hud, bar, sr.size)
		return Rect2(r.position + sr.position, r.size)
	var r2 := ScreenLayout.rect_px(pieces[id], _asp[id], sr.size)
	return Rect2(r2.position + sr.position, r2.size)


## Shown boxes, bottom first (the bar is drawn last, on top).
func shown() -> Array:
	var out := []
	for c in _cat:
		if pieces[c.id].on:
			out.append(c.id)
	if hud_on:
		out.append(HUD)
	return out


func _hit(p: Vector2) -> String:
	var ids := shown()
	ids.reverse()
	for id in ids:
		var b := box(id)
		if id == ScreenLayout.MINIMAP and b.get_center().distance_to(p) > b.size.x * 0.5 + HANDLE * 0.5:
			continue
		if b.grow(2.0).has_point(p):
			return id
	return ""


func _on_corner(id: String, p: Vector2) -> bool:
	var b := box(id)
	return p.distance_to(b.end) <= HANDLE


# ---- input -------------------------------------------------------------------------------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var id := _hit(e.position)
		if id != "":
			scale_box(id, WHEEL_STEP if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_STEP)
			_commit(id)
		accept_event()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_drag = _hit(e.position)
			_resize = _drag != "" and _on_corner(_drag, e.position)
			if _drag != "":
				_grab = e.position - box(_drag).position
		elif _drag != "":
			_commit(_drag)
			_drag = ""
		accept_event()
	elif e is InputEventMouseMotion:
		if _drag != "":
			if _resize:
				resize_to(_drag, e.position)
			else:
				move_to(_drag, e.position - _grab)
			queue_redraw()
		else:
			var h := _hit(e.position)
			mouse_default_cursor_shape = CURSOR_ARROW if h == "" else (CURSOR_FDIAGSIZE if _on_corner(h, e.position) else CURSOR_MOVE)
			if h != _hover:
				_hover = h
				queue_redraw()


## Put a box's top-left at `p` (px in this control), kept on the screen.
func move_to(id: String, p: Vector2) -> void:
	var sr := screen_rect()
	var b := box(id)
	var tl := (p - sr.position).clamp(Vector2.ZERO, (sr.size - b.size).max(Vector2.ZERO))
	if id == HUD:
		hud.x = (tl.x + b.size.x * 0.5) / sr.size.x
		hud.y = tl.y / sr.size.y
	else:
		pieces[id].x = tl.x / sr.size.x
		pieces[id].y = tl.y / sr.size.y


## Resize a box so its bottom-right corner follows `p`, keeping its shape.
func resize_to(id: String, p: Vector2) -> void:
	var sr := screen_rect()
	var b := box(id)
	var asp := b.size.x / maxf(b.size.y, 1.0)
	var h := maxf(p.y - b.position.y, (p.x - b.position.x) / asp)
	_set_height(id, h / sr.size.y, b)


func scale_box(id: String, k: float) -> void:
	var b := box(id)
	_set_height(id, b.size.y * k / screen_rect().size.y, b)  # the bar grows about its centre line, a piece from its top-left


func _set_height(id: String, h_frac: float, before: Rect2) -> void:
	if id == HUD:
		var base := ScreenLayout.HUD_H
		hud.scale = clampf(h_frac / base, ScreenLayout.HUD_MIN, ScreenLayout.HUD_MAX)
	else:
		pieces[id].h = clampf(h_frac, ScreenLayout.MIN_H, ScreenLayout.MAX_H)
		move_to(id, before.position)  # pull it back on screen if it grew past an edge
	queue_redraw()


func _commit(id: String) -> void:
	if def == null:
		return
	if id == HUD:
		ScreenLayout.save_hud(hud)
	else:
		ScreenLayout.save_pieces(def, pieces)
	ScreenLayout.use_custom()
	edited.emit()


# ---- drawing -----------------------------------------------------------------------------------

func _draw() -> void:
	var sr := screen_rect()
	var sky := Color(0.33, 0.5, 0.7)
	var horizon := Color(0.62, 0.72, 0.8)
	var ground := Color(0.3, 0.36, 0.26)
	var mid := sr.position.y + sr.size.y * 0.55
	draw_polygon(PackedVector2Array([sr.position, Vector2(sr.end.x, sr.position.y), Vector2(sr.end.x, mid), Vector2(sr.position.x, mid)]),
		PackedColorArray([sky, sky, horizon, horizon]))
	draw_polygon(PackedVector2Array([Vector2(sr.position.x, mid), Vector2(sr.end.x, mid), sr.end, Vector2(sr.position.x, sr.end.y)]),
		PackedColorArray([ground.lightened(0.15), ground.lightened(0.15), ground, ground]))
	draw_rect(sr, Color(1, 1, 1, 0.35), false, 1.5)
	var font := ThemeDB.fallback_font
	for id in shown():
		_draw_box(id, font)


func _draw_box(id: String, font: Font) -> void:
	var b := box(id)
	var hot := id == _hover or id == _drag
	var fill := Color(0.06, 0.08, 0.11, 0.85)
	var line := Color(1.0, 0.82, 0.35) if hot else Color(1, 1, 1, 0.55)
	var label: String = "Flight data bar" if id == HUD else str(_labels.get(id, id))
	if id == ScreenLayout.MINIMAP:
		draw_circle(b.get_center(), b.size.x * 0.5, Color(0.2, 0.32, 0.26, 0.92))
		draw_arc(b.get_center(), b.size.x * 0.5 - 1.0, 0.0, TAU, 64, line, 2.0, true)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(int(minf(b.size.y * 0.5, 10.0)) if id == HUD else 4)
		sb.border_color = line
		sb.set_border_width_all(2 if hot else 1)
		draw_style_box(sb, b)
	var upright := b.size.y > b.size.x * 1.4  # a tall narrow box reads its label sideways
	var room := (b.size.y if upright else b.size.x) - 8.0
	var fs := clampi(int(minf(b.size.x, b.size.y) * 0.22), 9, 14)
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	if ts.x > room:
		fs = maxi(7, int(fs * room / ts.x))
		ts = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_set_transform(b.get_center(), -PI * 0.5 if upright else 0.0)
	draw_string(font, Vector2(-ts.x * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, room, fs, Color(1, 1, 1, 0.92))
	draw_set_transform(Vector2.ZERO)
	var c := b.end
	draw_colored_polygon(PackedVector2Array([c, c - Vector2(HANDLE * 0.7, 0), c - Vector2(0, HANDLE * 0.7)]), line)
