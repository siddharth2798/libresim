class_name Display
extends Control
## Base class of the glass displays (PFD, ND, E/WD, SD, FCU, MCDU). A display draws in its own
## fixed design space (`design`, px) that is scaled uniformly into whatever rect the panel gives it, and
## reads ONLY Props (never the FDM), so replays and saved flights drive it like a live flight. Used
## from panel.json with "kind": "display". Subclasses override _paint(); buttons and knobs are
## registered while painting (button() / hot()) and answer clicks and the wheel through _press() /
## _wheel(). Text uses Godot's default font; digits are drawn right-aligned so values do not jitter.
## Colours follow the usual airliner convention: green = normal, white = scale, cyan = selected /
## target, magenta = managed / FMS, amber = caution, red = warning.

const BG := Color(0.015, 0.02, 0.03)
const GREEN := Color(0.1, 0.95, 0.25)
const WHITE := Color(0.95, 0.95, 0.95)
const CYAN := Color(0.1, 0.85, 1.0)
const MAGENTA := Color(1.0, 0.25, 0.95)
const AMBER := Color(1.0, 0.62, 0.05)
const RED := Color(1.0, 0.15, 0.1)
const GREY := Color(0.5, 0.52, 0.56)
const PANEL := Color(0.09, 0.1, 0.12)
const SKY := Color(0.0, 0.42, 0.85)
const GROUND := Color(0.42, 0.24, 0.1)

var design := Vector2(600, 600)  # drawing space, px; subclasses set it in _init
var font: Font
var _scale := 1.0
var calls := 0  # drawing commands issued by the last paint (dry_paint() in tests)
var _dry := false
var _hot := []  # [Rect2 (design px), id] of the clickable zones, rebuilt on every paint


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(100, 100)


func _draw() -> void:
	if font == null:
		font = ThemeDB.fallback_font
	_hot.clear()
	_scale = minf(size.x / design.x, size.y / design.y)
	if _scale <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(_scale, _scale))
	draw_rect(Rect2(Vector2.ZERO, design), BG)
	_paint()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint() -> void:
	pass


## Run _paint() without a canvas (tests): counts the drawing commands, fills the click zones.
func dry_paint() -> int:
	if font == null:
		font = ThemeDB.fallback_font
	_dry = true
	calls = 0
	_hot.clear()
	_scale = 1.0
	_paint()
	_dry = false
	return calls


## A clickable zone (design px). A press calls _press(id, button), the wheel _wheel(id, +-1).
func hot(r: Rect2, id: String) -> void:
	_hot.append([r, id])


func _zone_at(p: Vector2) -> String:
	for i in range(_hot.size() - 1, -1, -1):
		if (_hot[i][0] as Rect2).has_point(p):
			return _hot[i][1]
	return ""


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or not e.pressed or _scale <= 0.0:
		return
	var p: Vector2 = e.position / _scale
	var id := _zone_at(p)
	if id == "":
		return
	match e.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_press(id, e.button_index, p)
		MOUSE_BUTTON_WHEEL_UP:
			_wheel(id, 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_wheel(id, -1.0)
	accept_event()
	queue_redraw()


## Click on zone `id`; `p` is in design px (a knob uses it to tell its left half from its right).
func _press(_id: String, _button: int, _p: Vector2) -> void:
	pass


func _wheel(_id: String, _dir: float) -> void:
	pass


# --- drawing helpers (design px) ---------------------------------------------------------------------

## Text with its vertical centre on p.y; align -1 = p.x is the left edge, 0 = centre, 1 = right edge.
func txt(p: Vector2, s: String, fs: int, col := GREEN, align := -1) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := p.x - (w * 0.5 if align == 0 else (w if align > 0 else 0.0))
	if _dry:
		calls += 1
		return
	draw_string(font, Vector2(x, p.y + fs * 0.34), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func fill(r: Rect2, col: Color) -> void:
	if _dry:
		calls += 1
		return
	draw_rect(r, col)


func frame(r: Rect2, col := WHITE, w := 1.5) -> void:
	if _dry:
		calls += 1
		return
	draw_rect(r, col, false, w)


func line(a: Vector2, b: Vector2, col := WHITE, w := 2.0) -> void:
	if _dry:
		calls += 1
		return
	draw_line(a, b, col, w, true)


func poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3 and not _dry:
		draw_colored_polygon(pts, col)


## Arc on a compass: angles in rad, 0 = up, clockwise positive.
func arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w := 2.0) -> void:
	if _dry:
		calls += 1
		return
	draw_arc(c, r, a0 - PI * 0.5, a1 - PI * 0.5, maxi(int(absf(a1 - a0) * r / 6.0), 6), col, w, true)


func dot(c: Vector2, r: float, col: Color) -> void:
	if _dry:
		calls += 1
		return
	draw_circle(c, r, col)


func ring(c: Vector2, r: float, col: Color) -> void:
	arc(c, r, 0.0, TAU, col, 2.0)


## Filled triangle pointing along direction `dir_a` (compass rad) with its tip at `tip`.
func arrow(tip: Vector2, dir_a: float, len: float, half_w: float, col: Color) -> void:
	var d := Vector2(sin(dir_a), -cos(dir_a))
	var n := Vector2(-d.y, d.x)
	poly(PackedVector2Array([tip, tip - d * len + n * half_w, tip - d * len - n * half_w]), col)


## A lit / unlit push button with a label; registers the zone `id`.
func button(r: Rect2, id: String, label: String, lit: bool, lit_col := GREEN, fs := 15) -> void:
	fill(r, Color(0.2, 0.21, 0.24) if not lit else Color(0.22, 0.28, 0.24))
	frame(r, GREY, 1.5)
	if lit:
		fill(Rect2(r.position + Vector2(5, 4), Vector2(r.size.x - 10, 5)), lit_col)
	txt(r.get_center() + Vector2(0, 4), label, fs, WHITE, 0)
	hot(r, id)


## Boxed numeric window (FCU style): dim when `dashes`.
func window(r: Rect2, value: String, col := AMBER, fs := 30) -> void:
	fill(r, Color(0.02, 0.02, 0.02))
	frame(r, Color(0.3, 0.3, 0.32), 2.0)
	txt(Vector2(r.end.x - 8, r.get_center().y + 1), value, fs, col, 1)


## Value or "--" if the prop has never been published (a display must stay safe with defaults).
static func prop_text(path: String, fmt: String, missing := "--") -> String:
	return fmt % Props.get_f(path) if Props.has(path) else missing
